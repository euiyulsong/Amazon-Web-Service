import boto3


bedrock = boto3.client(
    "bedrock-runtime",
    region_name="us-east-1",
)


prediction = 123.45


response = bedrock.converse(
    modelId="amazon.nova-micro-v1:0",

    messages=[
        {
            "role": "user",
            "content": [
                {
                    "text": (
                        f"My ML model returned "
                        f"{prediction:.2f}. "
                        "Explain this prediction "
                        "in one short sentence."
                    )
                }
            ],
        }
    ],

    inferenceConfig={
        "maxTokens": 50,
        "temperature": 0.1,
    },
)


text = response[
    "output"
]["message"]["content"][0]["text"]

print(text)
