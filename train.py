import os
import joblib
import numpy as np

from sklearn.datasets import load_iris
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score


# =========================
# Training
# =========================

MODEL_DIR = os.environ.get("SM_MODEL_DIR", "./model")

X, y = load_iris(return_X_y=True)

split = int(len(X) * 0.8)

X_train, X_test = X[:split], X[split:]
y_train, y_test = y[:split], y[split:]

model = RandomForestClassifier(
    n_estimators=100,
    random_state=42,
)

model.fit(X_train, y_train)

pred = model.predict(X_test)

print("accuracy:", accuracy_score(y_test, pred))

os.makedirs(MODEL_DIR, exist_ok=True)

joblib.dump(
    model,
    os.path.join(MODEL_DIR, "model.joblib")
)


# =========================
# Inference
# =========================

def model_fn(model_dir):
    return joblib.load(
        os.path.join(model_dir, "model.joblib")
    )


def input_fn(request_body, content_type):

    if content_type == "text/csv":

        return np.array([
            [float(x) for x in request_body.split(",")]
        ])

    raise ValueError(
        f"Unsupported content type: {content_type}"
    )


def predict_fn(data, model):
    return model.predict(data)


def output_fn(prediction, accept):
    return str(int(prediction[0]))
