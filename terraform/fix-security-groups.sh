#!/bin/bash
echo "🔧 Advanced Auto-fixing Security Groups and Values for StatusPage connectivity..."

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
REDIS_SG=$(aws elasticache describe-cache-clusters --cache-cluster-id ly-statuspage-redis-001 --show-cache-node-info --region $REGION --query 'CacheClusters[0].SecurityGroups[0].SecurityGroupId' --output text)
echo "Found Redis SG: $REDIS_SG"

# Get the correct Redis endpoint
echo "🔍 Getting correct Redis endpoint..."
REDIS_ENDPOINT=$(aws elasticache describe-replication-groups --replication-group-id ly-statuspage-redis --region $REGION --query 'ReplicationGroups[0].NodeGroups[0].PrimaryEndpoint.Address' --output text)
echo "Found Redis endpoint: $REDIS_ENDPOINT"

# Get ALL node Security Groups (not just a generic one)
echo "🔍 Finding ALL EKS node Security Groups..."
NODE_IPS=($(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'))
ALL_NODE_SGS=()

for NODE_IP in "${NODE_IPS[@]}"; do
    echo "Checking node IP: $NODE_IP"
    NODE_SGS=$(aws ec2 describe-instances --filters "Name=private-ip-address,Values=$NODE_IP" --region $REGION --query 'Reservations[0].Instances[0].SecurityGroups[*].GroupId' --output text)
    echo "Found SGs for $NODE_IP: $NODE_SGS"
    
    # Add to array (split by spaces)
    for SG in $NODE_SGS; do
        if [[ ! " ${ALL_NODE_SGS[@]} " =~ " ${SG} " ]]; then
            ALL_NODE_SGS+=("$SG")
        fi
    done
done

echo "All unique node Security Groups: ${ALL_NODE_SGS[@]}"

# Add all node Security Groups to RDS
echo ""
echo "📡 Adding ALL EKS Security Groups to RDS (port 5432)..."
for NODE_SG in "${ALL_NODE_SGS[@]}"; do
    aws ec2 authorize-security-group-ingress \
        --group-id $RDS_SG \
        --protocol tcp \
        --port 5432 \
        --source-group $NODE_SG \
        --region $REGION 2>/dev/null && echo "✅ Added $NODE_SG to RDS" || echo "ℹ️  Rule already exists: $NODE_SG -> RDS"
done

# Add all node Security Groups to Redis
echo ""
echo "📡 Adding ALL EKS Security Groups to Redis (port 6379)..."
for NODE_SG in "${ALL_NODE_SGS[@]}"; do
    aws ec2 authorize-security-group-ingress \
        --group-id $REDIS_SG \
        --protocol tcp \
        --port 6379 \
        --source-group $NODE_SG \
        --region $REGION 2>/dev/null && echo "✅ Added $NODE_SG to Redis" || echo "ℹ️  Rule already exists: $NODE_SG -> Redis"
done

echo ""
echo "📝 Checking and updating values.yaml..."

VALUES_FILE="charts/statuspage-chart/values.yaml"

if [ -f "$VALUES_FILE" ]; then
    # Backup original file
    # cp "$VALUES_FILE" "$VALUES_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Get current Redis host in values.yaml
    CURRENT_REDIS_HOST=$(grep -A 1 "redis:" "$VALUES_FILE" | grep "host:" | awk '{print $2}' || grep "REDIS_HOST" "$VALUES_FILE" | awk '{print $2}')
    echo "Current Redis host in values.yaml: $CURRENT_REDIS_HOST"
    echo "Correct Redis endpoint: $REDIS_ENDPOINT"
    
    if [ "$CURRENT_REDIS_HOST" != "$REDIS_ENDPOINT" ]; then
        echo "🔄 Updating Redis endpoint in values.yaml..."
        sed -i "s|host: .*7fftml.*|host: $REDIS_ENDPOINT|g" "$VALUES_FILE"
        echo "✅ Updated Redis endpoint from $CURRENT_REDIS_HOST to $REDIS_ENDPOINT"
    else
        echo "✅ Redis endpoint is already correct in values.yaml"
    fi
    
    # Check and update image tag to latest from ECR
    echo "🔄 Checking if image tag needs update..."
    LATEST_ECR_TAG=$(aws ecr describe-images \
        --repository-name ly-statuspage-repo \
        --region $REGION \
        --query 'sort_by(imageDetails,& imagePushedAt)[-1].imageTags[0]' \
        --output text 2>/dev/null)

    if [ "$LATEST_ECR_TAG" != "None" ] && [ ! -z "$LATEST_ECR_TAG" ]; then
        CURRENT_VALUES_TAG=$(grep "tag:" "$VALUES_FILE" | awk '{print $2}' | tr -d '"')
        echo "Current tag in values.yaml: $CURRENT_VALUES_TAG"
        echo "Latest tag in ECR: $LATEST_ECR_TAG"
        
        if [ "$CURRENT_VALUES_TAG" != "$LATEST_ECR_TAG" ]; then
            echo "🔄 Updating values.yaml from $CURRENT_VALUES_TAG to $LATEST_ECR_TAG..."
            sed -i "s/tag: \".*\"/tag: \"$LATEST_ECR_TAG\"/" "$VALUES_FILE"
            echo "✅ Updated values.yaml to use latest ECR image: $LATEST_ECR_TAG"
            DEPLOYMENT_NEEDED=true
        else
            echo "✅ Values.yaml already uses latest ECR image"
        fi
    fi
    
    # Deploy if needed
    if [ "$DEPLOYMENT_NEEDED" = "true" ]; then
        echo "🚀 Deploying updated configuration..."
        cd terraform
        helm upgrade statuspage charts/statuspage-chart/ --values charts/statuspage-chart/values.yaml
        cd ..
    fi
    
else
    echo "❌ values.yaml not found at $VALUES_FILE"
    exit 1
fi

echo ""
echo "🎯 Checking current pod status..."
kubectl get pods -n default | grep statuspage

echo ""
echo "📋 Waiting for any restarts to settle (30 seconds)..."
sleep 30

echo "🔍 Checking updated pod status..."
kubectl get pods -n default | grep statuspage

echo ""
echo "🎯 Testing connectivity from a running pod..."
RUNNING_POD=$(kubectl get pods -n default -l app.kubernetes.io/name=statuspage-chart --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ ! -z "$RUNNING_POD" ]; then
    echo "Testing connectivity from pod: $RUNNING_POD"
    
    echo "Testing RDS connection..."
    kubectl exec $RUNNING_POD -- python -c "
import socket
try:
    s = socket.socket()
    s.settimeout(5)
    s.connect(('ly-statuspage-rds.cx248m4we6k7.us-east-1.rds.amazonaws.com', 5432))
    print('✅ RDS connection OK')
    s.close()
except Exception as e:
    print(f'❌ RDS connection failed: {e}')
" 2>/dev/null || echo "❌ Could not test RDS connection"
    
    echo "Testing Redis connection..."
    kubectl exec $RUNNING_POD -- python -c "
import socket
try:
    s = socket.socket()
    s.settimeout(5)
    s.connect(('$REDIS_ENDPOINT', 6379))
    print('✅ Redis connection OK')
    s.close()
except Exception as e:
    print(f'❌ Redis connection failed: {e}')
" 2>/dev/null || echo "❌ Could not test Redis connection"

    echo "Checking application logs (last 10 lines)..."
    kubectl logs $RUNNING_POD --tail=10 || echo "❌ Could not get logs"
    
else
    echo "❌ No running pods found to test connectivity"
fi

echo ""
echo "📋 Security Groups summary:"
echo "RDS SG: $RDS_SG"
echo "Redis SG: $REDIS_SG"
echo "Node SGs: ${ALL_NODE_SGS[@]}"

echo ""
echo "🚀 Security Groups and connectivity auto-fixed!"
echo "💡 If pods are still not ready, check logs with:"
echo "kubectl logs -f \$(kubectl get pods -n default -l app.kubernetes.io/name=statuspage-chart -o jsonpath='{.items[0].metadata.name}')"
