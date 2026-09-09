먼저 SageMaker를 빼고 **Docker pull 자체가 문제인지** 확인하자.

```bash
docker pull \
763104351884.dkr.ecr.us-east-1.amazonaws.com/pytorch-training:2.6-gpu-py312
```

그리고 다른 터미널에서:

```bash
docker system df
df -h
```

특히 `/var/lib/docker`가 있는 디스크 공간이 부족하지 않은지 봐.

### 가장 빠른 우회

사실 지금 목적이 **SageMaker → S3 → Endpoint → Bedrock 실습**이지, 로컬에서 AWS의 거대한 GPU DLC를 받는 게 목적은 아니잖아.

그래서 이 GPU Local Mode는 건너뛰어도 돼.

이미 로컬 NVIDIA GPU가 있으니까 그냥 로컬 PyTorch로 모델 하나 만들자:

```bash
python3 train_gpu.py
```

`train_gpu.py` 마지막에 이것만 추가:

```python
import os

os.makedirs("model", exist_ok=True)

torch.save(
    model.state_dict(),
    "model/model.pth"
)

print("saved: model/model.pth")
```

그러면:

```bash
ls -lh model/
```

에서

```text
model.pth
```

가 나오면 된다.

그걸 SageMaker artifact 형식으로:

```bash
tar -czf model.tar.gz -C model .
```

확인:

```bash
tar -tzf model.tar.gz
```

결과:

```text
./
./model.pth
```

그리고 S3:

```bash
aws s3 mb \
s3://euiyul-sagemaker-demo-522982707211 \
--region us-east-1
```

```bash
aws s3 cp model.tar.gz \
s3://euiyul-sagemaker-demo-522982707211/model.tar.gz
```

확인:

```bash
aws s3 ls \
s3://euiyul-sagemaker-demo-522982707211/
```

### 그러면 지금까지 구조가

```text
Local NVIDIA GPU
      ↓
PyTorch training
      ↓
model.pth
      ↓
model.tar.gz
      ↓
Amazon S3
      ↓
SageMaker Model
      ↓
Serverless Endpoint
      ↓
Bedrock
```

이렇게 된다.

다만 **이 방법은 이력서에서 `SageMaker managed training`을 했다고 쓰면 안 돼.** 정확하게는 local training + SageMaker managed deployment야. 네 계정의 managed-training quota가 0이라 그 부분만 아직 못 한 거고.

지금처럼 Docker DLC 하나 받는 데 하루를 쓰는 것보다 **이 경로로 S3 → SageMaker Serverless → Bedrock까지 끝내는 게 훨씬 낫다.**\

응. 지금 `model.tar.gz`가 S3에 있으니까 **SageMaker Model → Serverless Endpoint → 호출 → Bedrock** 순서로 가면 돼.

다만 네 모델은 우리가 만든 custom PyTorch `nn.Sequential`이라 **배포용 `inference.py`를 하나 만들어야 해.**

### 1. `inference.py` 만들기

`~/inference.py`:

```python
import os
import json
import torch
import torch.nn as nn


INPUT_DIM = 1000


def build_model():
    return nn.Sequential(
        nn.Linear(INPUT_DIM, 512),
        nn.ReLU(),
        nn.Linear(512, 256),
        nn.ReLU(),
        nn.Linear(256, 1),
    )


def model_fn(model_dir):
    model = build_model()

    checkpoint = torch.load(
        os.path.join(model_dir, "model.pth"),
        map_location="cpu",
    )

    model.load_state_dict(
        checkpoint["model_state_dict"]
    )

    model.eval()

    return model


def input_fn(request_body, content_type):
    if content_type == "application/json":
        data = json.loads(request_body)

        return torch.tensor(
            data["inputs"],
            dtype=torch.float32,
        )

    raise ValueError(
        f"Unsupported ContentType: {content_type}"
    )


def predict_fn(input_data, model):
    with torch.no_grad():
        return model(input_data)


def output_fn(prediction, accept):
    return json.dumps({
        "prediction": prediction.cpu().numpy().tolist()
    })
```

---

### 2. `deploy.py`

이게 **실제 AWS SageMaker Serverless Endpoint를 생성**하는 코드야.

```python
import sagemaker

from sagemaker.pytorch import PyTorchModel
from sagemaker.serverless import ServerlessInferenceConfig


REGION = "us-east-1"

ROLE = (
    "arn:aws:iam::522982707211:"
    "role/SageMakerExecutionRole"
)

MODEL_DATA = (
    "s3://euiyul-sagemaker-demo-522982707211/"
    "model.tar.gz"
)


session = sagemaker.Session()


model = PyTorchModel(
    model_data=MODEL_DATA,
    role=ROLE,

    entry_point="inference.py",

    framework_version="2.6",
    py_version="py312",

    sagemaker_session=session,
)


serverless_config = ServerlessInferenceConfig(
    memory_size_in_mb=2048,
    max_concurrency=1,
)


predictor = model.deploy(
    serverless_inference_config=serverless_config
)


print("=" * 60)
print("DEPLOY SUCCESS")
print("ENDPOINT NAME:")
print(predictor.endpoint_name)
print("=" * 60)
```

실행:

```bash
cd ~
python3 deploy.py
```

여기서 몇 분 걸릴 수 있어.

**중요:** 이 단계부터 실제 AWS Serverless 리소스를 만드는 거라 과금 가능성이 있어. 실습 끝나면 반드시 삭제할 거야.

그리고 IAM에서 또 `AccessDenied`가 날 가능성이 있어. 그러면 에러에 나온 action만 권한 추가하면 된다.

---

### 3. 성공 여부 확인

다른 터미널에서:

```bash
aws sagemaker list-endpoints \
  --region us-east-1 \
  --query "Endpoints[*].[EndpointName,EndpointStatus]" \
  --output table
```

처음에는:

```text
Creating
```

몇 분 후:

```text
InService
```

가 되면 성공.

---

### 4. Endpoint 실제 호출

우리가 만든 모델 input dimension이 **1000**이니까 1000개 숫자를 보내야 해.

`~/invoke.py`:

```python
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
```

`deploy.py`가 출력한 endpoint 이름을 복사해서:

```python
ENDPOINT_NAME = "pytorch-inference-2026-..."
```

넣고:

```bash
python3 invoke.py
```

성공하면 대략:

```json
{"prediction": [[...]]}
```

이렇게 나와.

그러면 진짜로:

```text
내 PC
  │
  │ HTTPS request
  ▼
AWS SageMaker Serverless Endpoint
  │
  ▼
PyTorch inference container
  │
  ▼
S3에서 받은 model.pth
  │
  ▼
prediction
  │
  ▼
내 PC
```

가 된 거야.

### 5. 그다음 Bedrock

Endpoint 성공한 뒤 Bedrock은 아주 간단해.

`bedrock.py`:

```python
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
```

```bash
python3 bedrock.py
```

Bedrock 호출까지 성공하면 우리가 원했던 전체 실습이 완성돼:

```text
Local NVIDIA GPU
       ↓
PyTorch Training
       ↓
model.pth
       ↓
model.tar.gz
       ↓
Amazon S3
       ↓
SageMaker Model
       ↓
Serverless Endpoint
       ↓
Boto3 invoke_endpoint
       ↓
Prediction
       ↓
Amazon Bedrock
       ↓
LLM explanation
```

그리고 **마지막에 바로 청소**하자. Endpoint뿐 아니라 `EndpointConfig`, `Model`, S3까지 전부 삭제해야 깔끔해.

지금은 **`inference.py`와 `deploy.py` 만들고 `python3 deploy.py`까지만 실행**해봐. 에러 나면 그 에러 기준으로 바로 고치면 된다.

