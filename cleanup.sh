#!/bin/bash

REGION="us-east-1"
BUCKET="euiyul-sagemaker-demo-522982707211"
DEFAULT_BUCKET="sagemaker-us-east-1-522982707211"

echo "========================================"
echo "1. Delete SageMaker Endpoints"
echo "========================================"

for EP in $(aws sagemaker list-endpoints \
    --region "$REGION" \
    --query 'Endpoints[].EndpointName' \
    --output text); do

    echo "Deleting endpoint: $EP"

    aws sagemaker delete-endpoint \
        --endpoint-name "$EP" \
        --region "$REGION"
done


echo "========================================"
echo "2. Wait until endpoints disappear"
echo "========================================"

while true; do
    COUNT=$(aws sagemaker list-endpoints \
        --region "$REGION" \
        --query 'length(Endpoints)' \
        --output text)

    if [ "$COUNT" = "0" ]; then
        break
    fi

    echo "Waiting... remaining endpoints: $COUNT"
    sleep 10
done


echo "========================================"
echo "3. Delete Endpoint Configs"
echo "========================================"

for CFG in $(aws sagemaker list-endpoint-configs \
    --region "$REGION" \
    --query 'EndpointConfigs[].EndpointConfigName' \
    --output text); do

    echo "Deleting endpoint config: $CFG"

    aws sagemaker delete-endpoint-config \
        --endpoint-config-name "$CFG" \
        --region "$REGION"
done


echo "========================================"
echo "4. Delete SageMaker Models"
echo "========================================"

for MODEL in $(aws sagemaker list-models \
    --region "$REGION" \
    --query 'Models[].ModelName' \
    --output text); do

    echo "Deleting model: $MODEL"

    aws sagemaker delete-model \
        --model-name "$MODEL" \
        --region "$REGION"
done


echo "========================================"
echo "5. Delete demo S3 bucket"
echo "========================================"

aws s3 rm "s3://$BUCKET" --recursive 2>/dev/null || true
aws s3 rb "s3://$BUCKET" 2>/dev/null || true


echo "========================================"
echo "6. Delete SageMaker SDK artifacts"
echo "========================================"

# bucket 자체는 다른 SageMaker 작업이 있을 수 있으므로
# 이번 PyTorch inference artifact만 삭제
aws s3 rm "s3://$DEFAULT_BUCKET/" \
    --recursive \
    --exclude "*" \
    --include "pytorch-inference-*/*" \
    2>/dev/null || true


echo "========================================"
echo "Cleanup finished"
echo "========================================"
