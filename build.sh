#!/bin/bash -x
current_date=$(date +'%Y%m%d%H%M')

docker build -t wkhtmltopdf-aas:$current_date .

docker tag wkhtmltopdf-aas:$current_date 751075880680.dkr.ecr.us-east-1.amazonaws.com/wkhtmltopdf-aas:$current_date

if [ "$1" = "push" ]; then
  aws ecr get-login-password --profile dev | docker login -u AWS --password-stdin "https://$(aws sts get-caller-identity --profile dev --query 'Account' --output text).dkr.ecr.us-east-1.amazonaws.com"

  echo "Pushing to ECR..."
  docker push 751075880680.dkr.ecr.us-east-1.amazonaws.com/wkhtmltopdf-aas:$current_date
fi
