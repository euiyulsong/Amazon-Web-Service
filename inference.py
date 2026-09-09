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
