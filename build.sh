#!/bin/bash

# File to store version number
VERSION_FILE="./version.txt"

# Read current version or start at 1
if [ -f "$VERSION_FILE" ]; then
    CURRENT_VERSION=$(cat $VERSION_FILE)
else
    CURRENT_VERSION=0
fi

# Increment version
NEW_VERSION=$((CURRENT_VERSION + 1))
TAG="v$NEW_VERSION"

# Save new version
echo $NEW_VERSION > $VERSION_FILE

echo "Building and deploying with tag: $TAG"

# Update values.yaml with new tag
sed -i "s/tag: \".*\"/tag: \"$TAG\"/" terraform/charts/statuspage-chart/values.yaml

# Build and push (using the existing Dockerfile in status-page directory)
docker build -f status-page/Dockerfile -t statuspage-app:$TAG ./status-page/
docker tag statuspage-app:$TAG 992382545251.dkr.ecr.us-east-1.amazonaws.com/ly-statuspage-repo:$TAG
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 992382545251.dkr.ecr.us-east-1.amazonaws.com
docker push 992382545251.dkr.ecr.us-east-1.amazonaws.com/ly-statuspage-repo:$TAG

echo "Image built and pushed with tag: $TAG"
echo "values.yaml updated"
