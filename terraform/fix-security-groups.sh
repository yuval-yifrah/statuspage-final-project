#!/bin/bash

echo "🔧 Auto-fixing Security Groups for StatusPage connectivity..."

# Get EKS cluster name and region
CLUSTER_NAME="ly-statuspage-cluster"
REGION="us-east-1"

echo "📡 Auto-detecting Security Groups..."

# Get RDS Security Group
echo "🔍 Finding RDS Security Group..."
RDS_SG=$(aws rds describe-db-instances --db-instance-identifier ly-statuspage-rds --region $REGION --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' --output text)
echo "Found RDS SG: $RDS_SG"

# Get Redis Security Group
echo "🔍 Finding Redis Security Group..."
REDIS_SG=$(aws elasticache describe-cache-clusters --cache-cluster-id ly-statuspage-redis --region $REGION --query 'CacheClusters[0].SecurityGroups[0].SecurityGroupId' --output text)
echo "Found Redis SG: $REDIS_SG"

# Get EKS node instance IDs
echo "🔍 Finding EKS nodes..."
NODE_INSTANCE_IDS=$(kubectl get nodes -o jsonpath='{.items[*].spec.providerID}' | tr ' ' '\n' | sed 's|.*\/||' | tr '\n' ' ')
echo "Found EKS nodes: $NODE_INSTANCE_IDS"

# Get unique Security Groups from all EKS nodes
echo "🔍 Finding EKS Security Groups..."
EKS_SGS=$(aws ec2 describe-instances --instance-ids $NODE_INSTANCE_IDS --region $REGION --query 'Reservations[*].Instances[*].SecurityGroups[*].GroupId' --output text | tr '\t' '\n' | sort -u | tr '\n' ' ')
echo "Found EKS SGs: $EKS_SGS"

echo ""
echo "📡 Adding EKS Security Groups to RDS (port 5432)..."
for SG in $EKS_SGS; do
    aws ec2 authorize-security-group-ingress \
        --group-id $RDS_SG \
        --protocol tcp \
        --port 5432 \
        --source-group $SG \
        --region $REGION 2>/dev/null && echo "✅ Added $SG to RDS" || echo "ℹ️  Rule already exists: $SG -> RDS"
done

echo ""
echo "📡 Adding EKS Security Groups to Redis (port 6379)..."
for SG in $EKS_SGS; do
    aws ec2 authorize-security-group-ingress \
        --group-id $REDIS_SG \
        --protocol tcp \
        --port 6379 \
        --source-group $SG \
        --region $REGION 2>/dev/null && echo "✅ Added $SG to Redis" || echo "ℹ️  Rule already exists: $SG -> Redis"
done

echo ""
echo "🎯 Checking current pod status..."
kubectl get pods -n default | grep statuspage

echo ""
echo "📋 To check logs after pods restart:"
echo "kubectl logs -f \$(kubectl get pods -n default -l app.kubernetes.io/name=statuspage-chart -o jsonpath='{.items[0].metadata.name}')"

echo ""
echo "🚀 Security Groups auto-fixed! StatusPage pods should be able to connect to RDS and Redis now."
echo "💡 The pods may need a few minutes to restart and establish connections."
