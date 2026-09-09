import os

import torch
import torch.nn as nn
import torch.optim as optim


# ============================================================
# 1. GPU 확인
# ============================================================

print("=" * 60)
print("PyTorch version :", torch.__version__)
print("CUDA available  :", torch.cuda.is_available())
print("GPU count       :", torch.cuda.device_count())

if torch.cuda.is_available():
    print("GPU name        :", torch.cuda.get_device_name(0))

device = torch.device(
    "cuda" if torch.cuda.is_available() else "cpu"
)

print("Training device :", device)
print("=" * 60)


# ============================================================
# 2. 간단한 synthetic dataset
# ============================================================

NUM_SAMPLES = 10_000
INPUT_DIM = 1000

torch.manual_seed(42)

X = torch.randn(
    NUM_SAMPLES,
    INPUT_DIM,
    device=device
)

# regression target
true_weight = torch.randn(
    INPUT_DIM,
    1,
    device=device
)

y = X @ true_weight

y += 0.1 * torch.randn_like(y)


print("X shape:", X.shape)
print("y shape:", y.shape)


# ============================================================
# 3. 모델
# ============================================================

model = nn.Sequential(
    nn.Linear(INPUT_DIM, 512),
    nn.ReLU(),

    nn.Linear(512, 256),
    nn.ReLU(),

    nn.Linear(256, 1),
).to(device)


print(model)


# ============================================================
# 4. Optimizer / Loss
# ============================================================

optimizer = optim.Adam(
    model.parameters(),
    lr=0.001,
)

loss_fn = nn.MSELoss()


# ============================================================
# 5. Training
# ============================================================

EPOCHS = 20

print("\nStarting training...")
print("=" * 60)

for epoch in range(EPOCHS):

    model.train()

    optimizer.zero_grad()

    prediction = model(X)

    loss = loss_fn(
        prediction,
        y
    )

    loss.backward()

    optimizer.step()

    print(
        f"epoch={epoch + 1:02d}/{EPOCHS} "
        f"loss={loss.item():.6f}"
    )


# ============================================================
# 6. Model 저장
# ============================================================

MODEL_DIR = "model"

os.makedirs(
    MODEL_DIR,
    exist_ok=True
)

MODEL_PATH = os.path.join(
    MODEL_DIR,
    "model.pth"
)

torch.save(
    {
        "model_state_dict": model.state_dict(),
        "input_dim": INPUT_DIM,
    },
    MODEL_PATH
)


# ============================================================
# 7. 결과
# ============================================================

print("=" * 60)
print("Training finished")
print("Training device :", device)
print("Model saved     :", MODEL_PATH)

if torch.cuda.is_available():

    allocated = (
        torch.cuda.memory_allocated(0)
        / 1024**2
    )

    reserved = (
        torch.cuda.memory_reserved(0)
        / 1024**2
    )

    print(
        f"GPU allocated   : {allocated:.2f} MB"
    )

    print(
        f"GPU reserved    : {reserved:.2f} MB"
    )

print("=" * 60)
