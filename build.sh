#!/bin/bash
set -euo pipefail

ECR_REGISTRY="YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com"
ECR_REPOSITORY="your-prefix-statuspage-repo"
REGION="us-east-1"

LATEST_TAG=$(aws ecr describe-images \
  --repository-name "$ECR_REPOSITORY" \
  --region "$REGION" \
  --query 'sort_by(imageDetails,& imagePushedAt)[-1].imageTags[0]' \
  --output text 2>/dev/null || echo "v0")

if [[ "$LATEST_TAG" =~ ^v[0-9]+$ ]]; then
    CURRENT_VERSION=${LATEST_TAG#v}
else
    CURRENT_VERSION=0
fi

NEW_VERSION=$((CURRENT_VERSION + 1))
TAG="v$NEW_VERSION"

echo "Latest tag in ECR: $LATEST_TAG"
echo "New build version: $TAG"

sed -i "s/tag: \".*\"/tag: \"$TAG\"/" terraform/charts/statuspage-chart/values.yaml

docker build -f status-page/Dockerfile -t statuspage-app:$TAG ./status-page/

docker tag statuspage-app:$TAG $ECR_REGISTRY/$ECR_REPOSITORY:$TAG

aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

docker push $ECR_REGISTRY/$ECR_REPOSITORY:$TAG

echo "✅ Image built and pushed: $TAG"
echo "values.yaml updated with tag: $TAG"

