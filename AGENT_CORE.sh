가능. 지금 AWS 계정/CLI가 이미 있으니까 **Strands를 로컬에서 먼저 돌리고 → 같은 agent를 AgentCore Runtime에 올리는 순서**가 제일 빨라. 현재 공식 문서 기준 Strands는 라이브러리이고 Bedrock이 기본 모델 provider이며, AgentCore는 Strands 같은 framework로 작성한 agent를 managed runtime에 배포할 수 있어. ([Strands Agents SDK][1])

## 1. Strands Agent 로컬 실험

Python 3.10+에서:

```bash
mkdir -p ~/strands-demo
cd ~/strands-demo

python3 -m venv .venv
source .venv/bin/activate

pip install strands-agents strands-agents-tools
```

AWS credential부터 확인:

```bash
aws sts get-caller-identity
```

`agent.py`:

```python
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
```

실행:

```bash
python agent.py
```

Strands가 대략 이렇게 agent loop를 수행하는 거야. ([Strands Agents SDK][1])

```text
User
 │
 ▼
Strands Agent
 │
 ├─ LLM (Bedrock)
 │      │
 │      ▼
 │   "multiply 필요"
 │
 ├─ Tool call
 │   multiply(1234,5678)
 │
 └─ LLM
     │
     ▼
   Answer
```

즉 네가 예전에 보던 ReAct 구조와 거의 연결해서 이해하면 돼.

---

## 2. AgentCore까지 바로 실험

AgentCore CLI는 현재 npm으로 설치하는 게 공식 quickstart야. ([AWS 문서][2])

```bash
node --version
npm --version

sudo npm install -g @aws/agentcore
```

그다음 Strands 기반 프로젝트를 자동 생성:

```bash
cd ~

agentcore create \
  --project-name AgentCoreDemo \
  --name DemoAgent \
  --language Python \
  --framework Strands \
  --model-provider Bedrock \
  --memory none \
  --build CodeZip
```

```bash
cd AgentCoreDemo
```

이 명령이 **Strands agent + AgentCore 배포에 필요한 프로젝트 구조를 만들어준다.** 공식 문서상 CodeZip이면 Docker도 필요 없다. ([AWS 문서][2])

먼저 생성된 agent를 로컬 테스트하고, 그다음:

```bash
agentcore deploy
```

하면 AWS에 올라간다. 공식 quickstart 기준 배포는 CDK stack을 합성해서 AgentCore Runtime 쪽 리소스를 만든다. ([AWS 문서][3])

상태 확인:

```bash
agentcore status
```

---

## 3. 둘의 관계가 중요함

둘은 경쟁 제품이 아니라 **레이어가 다르다**고 보면 돼.

```text
               Agent Application
                      │
              ┌───────▼───────┐
              │    Strands    │
              │               │
              │ Agent loop    │
              │ Tools         │
              │ Memory logic  │
              │ Multi-agent   │
              └───────┬───────┘
                      │
               deploy / host
                      │
              ┌───────▼───────┐
              │   AgentCore   │
              │    Runtime    │
              │               │
              │ managed infra │
              └───────┬───────┘
                      │
                  Amazon Bedrock
                      │
                     LLM
```

**Strands = agent를 어떻게 동작시킬지 작성하는 SDK/framework**
**AgentCore = 그 agent를 AWS에서 실행·운영하기 위한 managed agent infrastructure**

그리고 AgentCore에는 Runtime만 있는 게 아니라 Browser, Code Interpreter, Gateway 같은 기능도 있다. 예를 들어 **Strands Agent + AgentCore Code Interpreter**는 공식적으로 바로 연동된다. ([AWS 문서][4])

네가 지금 AWS를 빠르게 훑는 목적이면 **`Strands custom tool → AgentCore Runtime deploy → AgentCore Code Interpreter`** 이 3개만 직접 돌려봐도 이력서에서 AgentCore/Strands를 설명할 정도의 전체 그림은 상당히 잘 잡힐 거야.

[Strands Python Quickstart](https://strandsagents.com/docs/user-guide/quickstart/python/?utm_source=chatgpt.com) · [AWS AgentCore Quickstart](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-get-started-cli.html?utm_source=chatgpt.com)

단, `agentcore deploy`부터는 AWS 리소스를 실제 생성하므로 실습 끝나면 공식 cleanup 절차까지 하는 게 좋아. 이전처럼 과금 안 남게 할 거면 실험 끝난 뒤 AgentCore까지 포함해서 정리하면 돼.

[1]: https://strandsagents.com/docs/user-guide/quickstart/python/?utm_source=chatgpt.com "Python Quickstart | Strands Agents"
[2]: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-get-started-code-deploy-python.html?utm_source=chatgpt.com "Direct code deployment for Python - Amazon Bedrock AgentCore"
[3]: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-quick-start.html?utm_source=chatgpt.com "Get started with AgentCore Gateway - Amazon Bedrock AgentCore"
[4]: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/code-interpreter-using-strands.html?utm_source=chatgpt.com "Using AgentCore Code Interpreter via AWS Strands - Amazon Bedrock AgentCore"
