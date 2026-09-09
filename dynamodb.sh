aws dynamodb create-table \
  --table-name DemoUsers \
  --attribute-definitions AttributeName=user_id,AttributeType=S \
  --key-schema AttributeName=user_id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1

aws dynamodb wait table-exists \
  --table-name DemoUsers \
  --region us-east-1

aws dynamodb put-item \
  --table-name DemoUsers \
  --item '{
    "user_id":{"S":"user-001"},
    "name":{"S":"Alice"},
    "score":{"N":"95"}
  }' \
  --region us-east-1
