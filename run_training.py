from sagemaker.pytorch import PyTorch
from sagemaker.local import LocalSession

session = LocalSession()
session.config = {
    "local": {
        "local_code": True
    }
}

role = "arn:aws:iam::522982707211:role/SageMakerExecutionRole"

estimator = PyTorch(
    entry_point="train_gpu.py",
    role=role,

    instance_type="local_gpu",
    instance_count=1,

    framework_version="2.6",
    py_version="py312",

    sagemaker_session=session,
)

estimator.fit()
