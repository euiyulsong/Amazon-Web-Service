# Amazon-Web-Service
가능. 다만 **완전 0원이라고 보장하면 안 돼**. 지금 AWS 공식 기준으로 신규 계정의 SageMaker AI Free Tier는 첫 2개월 동안 **training 50시간 + real-time inference 125시간 + serverless inference 150,000초** 등이 포함된다. Bedrock은 모델별 사용량 과금이라 호출을 조금만 하면 아주 소액이지만, 무조건 무료는 아니다. ([Amazon Web Services][1])

가장 빨리 이력서에 넣을 만한 건 **“SageMaker Training → SageMaker Serverless Endpoint → Bedrock LLM”** 하나를 1~2시간 안에 돌려보는 거다. Studio Lab은 신규 고객을 더 이상 받지 않고 모델 배포도 지원하지 않으니, 이 목적에는 실제 AWS 계정의 SageMaker AI를 쓰는 게 낫다. ([AWS 문서][2])

### 1. AWS CLI 세팅

```bash
aws configure

# 확인
aws sts get-caller-identity

pip install -U boto3 sagemaker scikit-learn pandas
```

리전은 Bedrock 모델 접근성이 좋은 `us-east-1`로 잡으면 편하다.

```bash
export AWS_DEFAULT_REGION=us-east-1
```

### 2. SageMaker에서 실제 Training Job 돌리기

로컬에서 `train.py` 생성:

```python
import os
import joblib
import pandas as pd

from sklearn.datasets import load_iris
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score

MODEL_DIR = os.environ.get("SM_MODEL_DIR", "/opt/ml/model")

X, y = load_iris(return_X_y=True, as_frame=True)

split = int(len(X) * 0.8)

X_train, X_test = X.iloc[:split], X.iloc[split:]
y_train, y_test = y.iloc[:split], y.iloc[split:]

model = RandomForestClassifier(
    n_estimators=100,
    random_state=42,
)

model.fit(X_train, y_train)

pred = model.predict(X_test)
print("accuracy:", accuracy_score(y_test, pred))

os.makedirs(MODEL_DIR, exist_ok=True)
joblib.dump(model, f"{MODEL_DIR}/model.joblib")
```

그리고 `run_training.py`:

```python
import sagemaker
from sagemaker.sklearn.estimator import SKLearn

session = sagemaker.Session()
role = sagemaker.get_execution_role()

estimator = SKLearn(
    entry_point="train.py",
    role=role,
    instance_type="ml.m5.xlarge",
    framework_version="1.2-1",
    py_version="py3",
    instance_count=1,
)

estimator.fit()
```

Studio/Notebook 환경에서 실행하면 실제 SageMaker managed training job이 뜬다.

```bash
python run_training.py
```

AWS 공식 Free Tier에는 처음 2개월간 `m4.xlarge` 또는 `m5.xlarge` training 50시간이 포함되어 있으므로, 해당 Free Tier 자격이 있는 계정이면 이런 짧은 실습은 범위 내에서 할 수 있다. ([Amazon Web Services][3])

### 3. 학습 모델을 Serverless Endpoint로 배포

training 스크립트에 inference handler를 추가한다.

```python
import os
import joblib
import numpy as np

def model_fn(model_dir):
    return joblib.load(
        os.path.join(model_dir, "model.joblib")
    )

def input_fn(request_body, content_type):
    if content_type == "text/csv":
        return np.array([
            [float(x) for x in request_body.split(",")]
        ])

    raise ValueError(f"Unsupported content type: {content_type}")

def predict_fn(data, model):
    return model.predict(data)

def output_fn(prediction, accept):
    return str(int(prediction[0]))
```

배포:

```python
from sagemaker.serverless import ServerlessInferenceConfig

serverless_config = ServerlessInferenceConfig(
    memory_size_in_mb=2048,
    max_concurrency=1,
)

predictor = estimator.deploy(
    serverless_inference_config=serverless_config
)
```

호출:

```python
import boto3

runtime = boto3.client("sagemaker-runtime")

response = runtime.invoke_endpoint(
    EndpointName=predictor.endpoint_name,
    ContentType="text/csv",
    Body="5.1,3.5,1.4,0.2"
)

result = response["Body"].read().decode()
print(result)
```

이렇게 하면 단순히 notebook에서 sklearn 돌린 게 아니라 **managed training + model artifact + managed inference endpoint**까지 경험한 셈이다.

SageMaker Free Tier에는 현재 처음 2개월 동안 serverless inference 150,000초와 real-time inference 125시간도 명시되어 있다. ([Amazon Web Services][1])

### 4. 여기에 Bedrock 붙이기

이제 endpoint 결과를 LLM에게 넘겨 자연어 설명을 생성하면 된다.

```python
import boto3
import json

bedrock = boto3.client(
    "bedrock-runtime",
    region_name="us-east-1"
)

prediction = 0

prompt = f"""
A machine learning model predicted Iris class {prediction}.

Explain this prediction in one short sentence
for a non-technical user.
"""

response = bedrock.converse(
    modelId="amazon.nova-micro-v1:0",
    messages=[
        {
            "role": "user",
            "content": [{"text": prompt}]
        }
    ],
    inferenceConfig={
        "maxTokens": 100,
        "temperature": 0.1
    }
)

print(
    response["output"]["message"]["content"][0]["text"]
)
```

`modelId`는 네 계정/리전에서 사용 가능한 Bedrock 모델로 바꾸면 된다. Bedrock은 모델과 티어별 사용량 기반 과금이므로 SageMaker처럼 이 부분을 무조건 무료라고 보면 안 된다. ([Amazon Web Services][4])

그러면 전체 architecture가:

```text
Iris Dataset
     │
     ▼
SageMaker Training Job
  sklearn / RF
     │
     │ model.tar.gz
     ▼
S3 Model Artifact
     │
     ▼
SageMaker Serverless Endpoint
     │
     │ prediction
     ▼
Amazon Bedrock
  Nova Micro
     │
     ▼
Natural-language explanation
```

이 정도면 AWS 실습으로는 꽤 깔끔하다. 단순히 "SageMaker 써봤음"보다 **training → deployment → inference → foundation model integration**이 한 번에 연결된다.

AWS도 사용하지 않는 리소스를 삭제하지 않으면 비용이 발생할 수 있다고 안내한다. ([Amazon Web Services][5])

[SageMaker AI 공식 요금/Free Tier](https://aws.amazon.com/sagemaker/ai/pricing/?utm_source=chatgpt.com) · [Amazon Bedrock 공식 요금](https://aws.amazon.com/bedrock/pricing/?utm_source=chatgpt.com)

원하면 이걸 **Iris 장난감 예제 말고 `HuggingFace DistilBERT → SageMaker training → Serverless serving → Bedrock RAG/Agent`**로 바꿔서, GitHub에 그대로 올리고 이력서 한 줄 넣기 좋은 버전으로 만들어줄 수 있다.

[1]: https://aws.amazon.com/sagemaker/ai/pricing/?utm_source=chatgpt.com "SageMaker Pricing"
[2]: https://docs.aws.amazon.com/sagemaker/latest/dg/studio-lab.html?utm_source=chatgpt.com "Amazon SageMaker Studio Lab - Amazon SageMaker AI"
[3]: https://aws.amazon.com/ko/sagemaker/ai/pricing/?utm_source=chatgpt.com "SageMaker 요금"
[4]: https://aws.amazon.com/ko/bedrock/pricing/?utm_source=chatgpt.com "Amazon Bedrock 요금"
[5]: https://aws.amazon.com/sagemaker/ai/faqs/?utm_source=chatgpt.com "Machine Learning Service – Amazon SageMaker FAQs – AWS"
