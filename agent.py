from strands import Agent, tool


@tool
def multiply(a: int, b: int) -> int:
    """Multiply two integers."""
    print(f"[TOOL] multiply({a}, {b})")
    return a * b


agent = Agent(
    tools=[multiply],
    system_prompt="""
You are a helpful assistant.
Use the multiply tool whenever multiplication is required.
"""
)

result = agent("1234 * 5678 계산해줘. 반드시 tool을 사용해.")

print("\nRESULT:")
print(result)
