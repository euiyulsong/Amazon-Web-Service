맞아. 이제는 개별 서비스 생성보다 **한 번에 연결된 미니 시스템**을 돌려보는 게 좋아.

먼저 아까 만든 Security Group 의미부터 정확히 보면:

```text
EC2_SG
└─ EC2에 붙이는 방화벽

RDS_SG
└─ RDS에 붙이는 방화벽
   inbound TCP 5432
   source = EC2_SG
```

즉 `RDS_SG` 규칙의 의미는 **“인터넷 전체가 아니라 EC2_SG가 붙어 있는 리소스에서 오는 PostgreSQL(5432) 연결만 받아라”**야.

최종 실습은 이걸 만들면 돼:

```text
                        Internet
                           │
                          IGW
                           │
                    Public Route
                           │
┌────────────────── VPC 10.0.0.0/16 ──────────────────┐
│                                                     │
│ Public Subnet                 Private Subnets       │
│ 10.0.1.0/24                   10.0.2/3.0/24         │
│                                                     │
│    EC2 ─────── TCP 5432 ───────────► RDS            │
│     │                                               │
│     └── HTTP :80                                    │
│                                                     │
│             Lambda ────────────────► RDS            │
│                │                                    │
└────────────────┼────────────────────────────────────┘
                 │
                 └──────────────────► DynamoDB

       CloudWatch
       ├─ Lambda Logs
       ├─ EC2 metrics
       └─ RDS metrics
```

## 1. EC2를 띄우고 실제 `curl`

먼저 네 network script 실행이 성공해서 환경변수가 만들어진 뒤:

```bash
source ~/aws-demo.env
```

Public subnet에서 public IP가 자동 할당되도록:

```bash
aws ec2 modify-subnet-attribute \
  --subnet-id "$PUBLIC_SUBNET" \
  --map-public-ip-on-launch \
  --region us-east-1
```

EC2 SG에 HTTP 80 허용:

```bash
aws ec2 authorize-security-group-ingress \
  --group-id "$EC2_SG" \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0 \
  --region us-east-1
```

Amazon Linux AMI 가져오고:

```bash
AMI=$(aws ec2 describe-images \
  --owners amazon \
  --filters \
    "Name=name,Values=al2023-ami-2023.*-x86_64" \
    "Name=state,Values=available" \
  --query 'sort_by(Images,&CreationDate)[-1].ImageId' \
  --output text \
  --region us-east-1)
```

EC2 생성:

```bash
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI" \
  --instance-type t3.micro \
  --subnet-id "$PUBLIC_SUBNET" \
  --security-group-ids "$EC2_SG" \
  --associate-public-ip-address \
  --user-data '#!/bin/bash
dnf install -y nginx
echo "Hello from EC2 inside my VPC" > /usr/share/nginx/html/index.html
systemctl enable nginx
systemctl start nginx' \
  --region us-east-1 \
  --query 'Instances[0].InstanceId' \
  --output text)

echo $INSTANCE_ID
```

기다리고:

```bash
aws ec2 wait instance-status-ok \
  --instance-ids "$INSTANCE_ID" \
  --region us-east-1
```

Public IP 확인:

```bash
PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region us-east-1 \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

echo $PUBLIC_IP
```

그리고 드디어:

```bash
curl http://$PUBLIC_IP
```

성공하면:

```text
Hello from EC2 inside my VPC
```

이게 뜬다.

즉 실제로

```text
내 PC
 ↓ HTTP
Public IP
 ↓
Internet Gateway
 ↓
Route Table
 ↓
Public Subnet
 ↓
Security Group :80 허용
 ↓
EC2/nginx
```

**전체 네트워크를 통과한 것**이야.

---

## 2. VPC 자체도 확인

VPC는 서버처럼 `curl VPC` 하는 대상은 아니야. **네트워크 구성 상태를 관찰**해야 해.

```bash
aws ec2 describe-vpcs \
  --vpc-ids "$VPC_ID" \
  --region us-east-1 \
  --query 'Vpcs[0].[VpcId,CidrBlock,State]' \
  --output table
```

Subnet:

```bash
aws ec2 describe-subnets \
  --filters Name=vpc-id,Values="$VPC_ID" \
  --region us-east-1 \
  --query 'Subnets[*].[SubnetId,CidrBlock,AvailabilityZone,MapPublicIpOnLaunch]' \
  --output table
```

Route:

```bash
aws ec2 describe-route-tables \
  --filters Name=vpc-id,Values="$VPC_ID" \
  --region us-east-1 \
  --query 'RouteTables[*].Routes[*].[DestinationCidrBlock,GatewayId]' \
  --output table
```

여기서 public route에

```text
10.0.0.0/16 → local
0.0.0.0/0   → igw-xxxxx
```

가 보이면 돼.

---

## 3. RDS도 실제 연결까지 해야 함

맞아. RDS도 단순히 `available`만 보는 건 약해.

우리가 최종적으로:

```text
EC2 → PostgreSQL RDS → SELECT
```

까지 해야 해.

RDS는 private subnet에 넣고:

```text
EC2 10.0.1.x
      │
      │ TCP 5432
      ▼
RDS endpoint
      │
      ▼
PostgreSQL
```

EC2 안에서:

```bash
psql \
  -h <RDS_ENDPOINT> \
  -U demoadmin \
  -d postgres
```

한 다음:

```sql
CREATE TABLE demo (
    id SERIAL PRIMARY KEY,
    message TEXT
);

INSERT INTO demo(message)
VALUES ('Hello from EC2');

SELECT * FROM demo;
```

까지 확인하면 된다.

**여기서 일부러 RDS SG의 5432를 한번 닫아보면 접속 실패하고, 다시 열면 성공**하니까 Security Group 실습도 제대로 된다.

---

## 4. Lambda도 연결

그다음 Lambda에서 DynamoDB를 읽게 만들자.

예를 들면 Lambda:

```python
import boto3

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table("DemoUsers")

def lambda_handler(event, context):

    response = table.get_item(
        Key={"user_id": "user-001"}
    )

    print("DynamoDB result:", response)

    return {
        "statusCode": 200,
        "body": response.get("Item")
    }
```

실행하면:

```text
Lambda
   │
   │ AWS SDK
   ▼
DynamoDB
   │
   ▼
user-001
```

그리고 `print()`가 자동으로 **CloudWatch Logs**에 들어가.

---

## 5. CloudWatch까지 확인

EC2 CPU:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
  --statistics Average \
  --period 300 \
  --start-time "$(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --region us-east-1
```

RDS도:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=demo-postgres \
  --statistics Average \
  --period 300 \
  --start-time "$(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --region us-east-1
```

Lambda는 invocation 후 CloudWatch Logs에서 실제 로그를 보면 돼.

---

그러면 이번 실습 하나로 실제로 확인하는 게 꽤 많아:

```text
VPC
 ├─ CIDR
 ├─ Public/Private Subnet
 ├─ Internet Gateway
 ├─ Route Table
 └─ Security Group
        ↓
EC2 + nginx
        ↓
curl로 HTTP 확인

EC2
 └─ private RDS PostgreSQL
        ↓
     실제 SQL

Lambda
 └─ DynamoDB
        ↓
     실제 GetItem

CloudWatch
 ├─ EC2 CPU
 ├─ RDS CPU
 └─ Lambda logs
```

**순서는 `01_network.sh → EC2 curl → RDS 실제 SQL → DynamoDB → Lambda → CloudWatch → 전체 삭제`가 제일 깔끔해.** 지금은 먼저 `01_network.sh`가 IAM 권한 추가 후 성공해야 다음 리소스 ID를 그대로 이어서 쓸 수 있어.
