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
