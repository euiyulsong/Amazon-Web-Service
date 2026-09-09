#!/bin/bash
set -e

REGION="us-east-1"

# -------------------------------
# VPC
# -------------------------------

VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --region $REGION \
  --query 'Vpc.VpcId' \
  --output text)

echo "VPC=$VPC_ID"

aws ec2 create-tags \
  --resources $VPC_ID \
  --tags Key=Name,Value=demo-vpc \
  --region $REGION


# -------------------------------
# Public subnet
# -------------------------------

PUBLIC_SUBNET=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.1.0/24 \
  --availability-zone us-east-1a \
  --region $REGION \
  --query 'Subnet.SubnetId' \
  --output text)

aws ec2 create-tags \
  --resources $PUBLIC_SUBNET \
  --tags Key=Name,Value=demo-public \
  --region $REGION


# -------------------------------
# Private subnet 1
# -------------------------------

PRIVATE_SUBNET1=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.2.0/24 \
  --availability-zone us-east-1a \
  --region $REGION \
  --query 'Subnet.SubnetId' \
  --output text)


# RDS subnet group은 AZ 2개가 필요하므로 하나 더
PRIVATE_SUBNET2=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.3.0/24 \
  --availability-zone us-east-1b \
  --region $REGION \
  --query 'Subnet.SubnetId' \
  --output text)


# -------------------------------
# Internet Gateway
# -------------------------------

IGW_ID=$(aws ec2 create-internet-gateway \
  --region $REGION \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)

aws ec2 attach-internet-gateway \
  --internet-gateway-id $IGW_ID \
  --vpc-id $VPC_ID \
  --region $REGION


# -------------------------------
# Public Route Table
# -------------------------------

RT_ID=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query 'RouteTable.RouteTableId' \
  --output text)

aws ec2 create-route \
  --route-table-id $RT_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $IGW_ID \
  --region $REGION

aws ec2 associate-route-table \
  --route-table-id $RT_ID \
  --subnet-id $PUBLIC_SUBNET \
  --region $REGION


# -------------------------------
# EC2 Security Group
# -------------------------------

EC2_SG=$(aws ec2 create-security-group \
  --group-name demo-ec2-sg \
  --description "Demo EC2 SG" \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query GroupId \
  --output text)


# -------------------------------
# RDS Security Group
# -------------------------------

RDS_SG=$(aws ec2 create-security-group \
  --group-name demo-rds-sg \
  --description "Demo RDS SG" \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query GroupId \
  --output text)


# EC2 SG를 가진 resource만 PostgreSQL 접근 허용
aws ec2 authorize-security-group-ingress \
  --group-id $RDS_SG \
  --protocol tcp \
  --port 5432 \
  --source-group $EC2_SG \
  --region $REGION


cat > ~/aws-demo.env <<EOF
export REGION=$REGION
export VPC_ID=$VPC_ID
export PUBLIC_SUBNET=$PUBLIC_SUBNET
export PRIVATE_SUBNET1=$PRIVATE_SUBNET1
export PRIVATE_SUBNET2=$PRIVATE_SUBNET2
export IGW_ID=$IGW_ID
export RT_ID=$RT_ID
export EC2_SG=$EC2_SG
export RDS_SG=$RDS_SG
EOF

echo
echo "=============================="
echo "NETWORK CREATED"
echo "=============================="
cat ~/aws-demo.env
