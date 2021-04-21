fileWrite = require 'fs-writefile-promise'
prometheusMetrics = require 'express-prom-bundle'
{spawn} = require 'child-process-promise'
status = require 'express-status-monitor'
{flow, map, compact, values, flatMap,
  toPairs, first, last, concat, remove,
  flatten, negate} = require 'lodash/fp'
health = require 'express-healthcheck'
promisePipe = require 'promisepipe'
bodyParser = require 'body-parser'
parallel = require 'bluebird'
tmp = require 'tmp-promise'
express = require 'express'
auth = require 'http-auth'
helmet = require 'helmet'
log = require 'morgan'
fs = require 'fs'
app = express()

payload_limit = process.env.PAYLOAD_LIMIT or '100kb'

basic = auth.basic {}, (user, pass, cb) ->
  cb(user == process.env.USER && pass == process.env.PASS)

app.use helmet()
app.use '/healthcheck', health()
app.use '/', express.static(__dirname + '/documentation')
app.use auth.connect(basic)
app.use status()
app.use prometheusMetrics()
app.use log('combined')

app.post '/', bodyParser.json(limit: payload_limit), (req, res) ->

  decode = (base64) ->
    Buffer.from(base64, 'base64').toString 'utf8' if base64?

  tmpFile = (ext) ->
    tmp.file(dir: '/tmp', postfix: '.' + ext).then (f) -> f.path

  tmpWrite = (content) ->
    tmpFile('html').then (f) -> fileWrite f, content if content?

  if process.env.LOGGING_LEVEL == 'verbose'
    console.log("Content-Type:" + req.get('Content-Type'))
    console.log(JSON.stringify(req.body))

  # compile options to arguments
  arg = flow(toPairs, flatMap((i) -> ['--' + first(i), last(i)]), compact)

  # if not logging, then we need to send all output from wkhtmltopdf to /dev/null
  # instead of the default piped streams otherwise nothing will consume the streams
  # and their buffers will fill and cause the generation to fail on large jobs where the pdf may
  # be hundreds of pages long
  logging_output = 'ignore'
  if process.env.LOGGING_LEVEL == 'info' || process.env.LOGGING_LEVEL == 'verbose'
    logging_output = 'pipe'


  parallel.join tmpFile('pdf'),
  map(flow(decode, tmpWrite), [req.body.header, req.body.footer, req.body.contents])...,
  (output, header, footer, content) ->
    files = [['--header-html', header],
             ['--footer-html', footer],
             [content, output]]
    # combine arguments and call pdf compiler using shell
    # injection save function 'spawn' goo.gl/zspCaC
    ls = spawn 'wkhtmltopdf', (arg(req.body.options)
    .concat(flow(remove(negate(last)), flatten)(files))), {stdio: logging_output}
    .then ->
      res.setHeader 'Content-type', 'application/pdf'
      promisePipe fs.createReadStream(output), res
    .catch (error) -> 
      console.error error
      res.status(BAD_REQUEST = 400).send 'invalid arguments'
    .then -> map fs.unlinkSync, compact([output, header, footer, content])

    if process.env.LOGGING_LEVEL == 'info' || process.env.LOGGING_LEVEL == 'verbose'
      ls.childProcess.stderr.on 'data', (data) -> console.log data.toString().trim()
      ls.childProcess.stdout.on 'data', (data) -> console.log data.toString().trim()
    if process.env.LOGGING_LEVEL == 'verbose'
      ls.childProcess.on 'exit', (code) -> console.log 'child process exited with code ' + code.toString()


app.listen process.env.PORT or 5555
module.exports = app
