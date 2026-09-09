import json
import boto3


REGION = "us-east-1"

ENDPOINT_NAME = "여기에-실제-endpoint-name"


runtime = boto3.client(
    "sagemaker-runtime",
    region_name=REGION,
)


payload = {
    "inputs": [
        [0.1] * 1000
    ]
}


response = runtime.invoke_endpoint(
    EndpointName=ENDPOINT_NAME,
    ContentType="application/json",
    Accept="application/json",
    Body=json.dumps(payload),
)


result = response["Body"].read().decode()

print(result)
