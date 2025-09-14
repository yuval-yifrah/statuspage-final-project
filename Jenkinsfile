pipeline {
    agent {
        docker {
            image 'python:3.10-slim'
            args '-v /var/run/docker.sock:/var/run/docker.sock'
        }
    }
    
    environment {
        ECR_REGISTRY = "992382545251.dkr.ecr.us-east-1.amazonaws.com"
        ECR_REPOSITORY = 'ly-statuspage-repo'
        AWS_DEFAULT_REGION = "us-east-1"
        EKS_CLUSTER = "ly-statuspage-cluster"
        NAMESPACE = "default"
        // Initialize variables - will be set in Version Management stage
        IMAGE_TAG = ""
        NEW_VERSION = ""
    }
    
    stages {
        stage('Setup') {
            steps {
                script {
                    sh '''
                        # Install system dependencies
                        apt-get update
                        apt-get install -y curl docker.io awscli wget
                        
                        # Install kubectl
                        curl -LO "https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl"
                        chmod +x kubectl
                        mv kubectl /usr/local/bin/
                        
                        # Install Helm
                        curl https://get.helm.sh/helm-v3.12.0-linux-amd64.tar.gz | tar -xz
                        mv linux-amd64/helm /usr/local/bin/
                        
                        # Verify installations
                        docker --version
                        kubectl version --client
                        helm version
                        aws --version
                    '''
                }
            }
        }
        
        stage('Version Management') {
            steps {
                script {
                    sh '''
                        echo "Current directory: $(pwd)"
                        echo "Files in current directory:"
                        ls -la
                        echo "Looking for version.txt:"
                        find . -name "version.txt" -type f
                        
                        # Check if version.txt exists - FAIL if not found
                        if [ ! -f "version.txt" ]; then
                            echo "ERROR: version.txt file not found!"
                            echo "This file must exist and contain a valid version number."
                            exit 1
                        fi
                        
                        # Try to read version.txt - FAIL if can't read
                        if ! CURRENT_VERSION=$(cat version.txt 2>/dev/null); then
                            echo "ERROR: Failed to read version.txt!"
                            echo "Check file permissions or if file is corrupted."
                            exit 1
                        fi
                        
                        echo "Found version.txt with content: '$CURRENT_VERSION'"
                        
                        # Validate version is a number - FAIL if invalid
                        if ! echo "$CURRENT_VERSION" | grep -qE '^[0-9]+
        
        stage('Build and Push Docker Image') {
            steps {
                script {
                    sh """
                        echo "Building Docker image with tag: ${env.IMAGE_TAG}"
                        
                        # Build Docker image (exactly like your script)
                        docker build -f status-page/Dockerfile -t statuspage-app:${env.IMAGE_TAG} ./status-page/
                        
                        # Tag the image for ECR
                        docker tag statuspage-app:${env.IMAGE_TAG} ${ECR_REGISTRY}/${ECR_REPOSITORY}:${env.IMAGE_TAG}
                        
                        # Login to ECR
                        aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | docker login --username AWS --password-stdin ${ECR_REGISTRY}
                        
                        # Push the image to ECR
                        docker push ${ECR_REGISTRY}/${ECR_REPOSITORY}:${env.IMAGE_TAG}

                        echo "Image built and pushed with tag: ${env.IMAGE_TAG}"
                    """
                }
            }
        }
        
        stage('Deploy to EKS') {
            when {
                branch 'main'
            }
            steps {
                script {
                    sh """
                        echo "Deploying to EKS with image tag: ${env.IMAGE_TAG}"
                        
                        # Configure kubectl for EKS
                        aws eks update-kubeconfig --region ${AWS_DEFAULT_REGION} --name ${EKS_CLUSTER}
                        
                        # Deploy using Helm
                        cd terraform/charts/statuspage-chart
                        helm upgrade statuspage . \
                            --namespace ${NAMESPACE} \
                            --install \
                            --wait \
                            --timeout 600s \
                            --set image.tag=${env.IMAGE_TAG}
                        
                        # Verify deployment
                        kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=statuspage-chart
                    """
                }
            }
        }
        
        stage('Health Check') {
            when {
                branch 'main'
            }
            steps {
                script {
                    sh """
                        echo "Running health check for deployment with tag: ${env.IMAGE_TAG}"
                        
                        # Wait for pods to be ready
                        kubectl wait --for=condition=ready pod \
                            -l app.kubernetes.io/name=statuspage-chart \
                            -n ${NAMESPACE} \
                            --timeout=300s
                        
                        echo "Deployment completed successfully"
                    """
                }
            }
        }
    }
    
    post {
        always {
            script {
                sh """
                    echo "Pipeline completed for branch: ${BRANCH_NAME}"
                    if [ -n "${env.IMAGE_TAG}" ]; then
                        echo "Image built: ${ECR_REGISTRY}/${ECR_REPOSITORY}:${env.IMAGE_TAG}"
                        # Cleanup Docker images to save space
                        docker rmi ${ECR_REGISTRY}/${ECR_REPOSITORY}:${env.IMAGE_TAG} || true
                    fi
                    docker system prune -f || true
                """
            }
        }
        
        success {
            script {
                if (env.BRANCH_NAME == 'main') {
                    echo "Production deployment successful!"
                    echo "StatusPage ${env.IMAGE_TAG} is now live"
                }
            }
        }
        
        failure {
            script {
                if (env.BRANCH_NAME == 'main') {
                    echo "Production deployment failed!"
                    sh """
                        # Show recent pod events for debugging
                        kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp' | tail -20 || true
                        
                        # Show pod logs
                        kubectl logs -l app.kubernetes.io/name=statuspage-chart -n ${NAMESPACE} --tail=50 || true
                        
                        # Rollback to previous version
                        echo "Rolling back to previous Helm release..."
                        helm rollback statuspage --namespace ${NAMESPACE} || echo "No rollback available"
                    """
                }
            }
        }
        
        cleanup {
            script {
                sh 'docker logout ${ECR_REGISTRY} || true'
            }
        }
    }
}; then
                            echo "ERROR: version.txt contains invalid content: '$CURRENT_VERSION'"
                            echo "File must contain only a valid integer number."
                            exit 1
                        fi
                        
                        # Increment version
                        NEW_VERSION=$((CURRENT_VERSION + 1))
                        TAG="v$NEW_VERSION"
                        
                        echo "Current version: $CURRENT_VERSION"
                        echo "New version: $NEW_VERSION"
                        echo "Image tag: $TAG"
                        
                        # Try to write new version - FAIL if can't write
                        if ! echo $NEW_VERSION > version.txt; then
                            echo "ERROR: Failed to write to version.txt!"
                            echo "Check file permissions or disk space."
                            exit 1
                        fi
                        
                        # Verify the write was successful
                        if [ "$(cat version.txt)" != "$NEW_VERSION" ]; then
                            echo "ERROR: Failed to verify version.txt update!"
                            echo "Expected: $NEW_VERSION, Got: $(cat version.txt)"
                            exit 1
                        fi
                        
                        echo "Successfully updated version.txt"
                        
                        # Create environment file for Jenkins
                        echo "NEW_VERSION=$NEW_VERSION" > jenkins.env
                        echo "IMAGE_TAG=$TAG" >> jenkins.env
                        
                        # Update values.yaml with new tag
                        if [ -f "terraform/charts/statuspage-chart/values.yaml" ]; then
                            sed -i "s/tag: \\".*\\"/tag: \\"$TAG\\"/" terraform/charts/statuspage-chart/values.yaml
                            echo "Updated values.yaml:"
                            grep "tag:" terraform/charts/statuspage-chart/values.yaml
                        else
                            echo "WARNING: values.yaml not found, skipping tag update"
                        fi
                        
                        echo "Version management completed successfully"
                    '''
                    
                    // Load the environment variables from the file created in shell
                    def props = readProperties file: 'jenkins.env'
                    env.NEW_VERSION = props.NEW_VERSION
                    env.IMAGE_TAG = props.IMAGE_TAG
                    
                    echo "Jenkins environment variables set:"
                    echo "NEW_VERSION: ${env.NEW_VERSION}"
                    echo "IMAGE_TAG: ${env.IMAGE_TAG}"
                }
            }
        }
        
        stage('Build and Push Docker Image') {
            steps {
                script {
                    sh """
                        echo "Building Docker image with tag: ${env.IMAGE_TAG}"
                        
                        # Build Docker image (exactly like your script)
                        docker build -f status-page/Dockerfile -t statuspage-app:${env.IMAGE_TAG} ./status-page/
                        
                        # Tag the image for ECR
                        docker tag statuspage-app:${env.IMAGE_TAG} ${ECR_REGISTRY}/${ECR_REPOSITORY}:${env.IMAGE_TAG}
                        
                        # Login to ECR
                        aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | docker login --username AWS --password-stdin ${ECR_REGISTRY}
                        
                        # Push the image to ECR
                        docker push ${ECR_REGISTRY}/${ECR_REPOSITORY}:${env.IMAGE_TAG}

                        echo "Image built and pushed with tag: ${env.IMAGE_TAG}"
                    """
                }
            }
        }
        
        stage('Deploy to EKS') {
            when {
                branch 'main'
            }
            steps {
                script {
                    sh """
                        echo "Deploying to EKS with image tag: ${env.IMAGE_TAG}"
                        
                        # Configure kubectl for EKS
                        aws eks update-kubeconfig --region ${AWS_DEFAULT_REGION} --name ${EKS_CLUSTER}
                        
                        # Deploy using Helm
                        cd terraform/charts/statuspage-chart
                        helm upgrade statuspage . \
                            --namespace ${NAMESPACE} \
                            --install \
                            --wait \
                            --timeout 600s \
                            --set image.tag=${env.IMAGE_TAG}
                        
                        # Verify deployment
                        kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=statuspage-chart
                    """
                }
            }
        }
        
        stage('Health Check') {
            when {
                branch 'main'
            }
            steps {
                script {
                    sh """
                        echo "Running health check for deployment with tag: ${env.IMAGE_TAG}"
                        
                        # Wait for pods to be ready
                        kubectl wait --for=condition=ready pod \
                            -l app.kubernetes.io/name=statuspage-chart \
                            -n ${NAMESPACE} \
                            --timeout=300s
                        
                        echo "Deployment completed successfully"
                    """
                }
            }
        }
    }
    
    post {
        always {
            script {
                sh """
                    echo "Pipeline completed for branch: ${BRANCH_NAME}"
                    if [ -n "${env.IMAGE_TAG}" ]; then
                        echo "Image built: ${ECR_REGISTRY}/${ECR_REPOSITORY}:${env.IMAGE_TAG}"
                        # Cleanup Docker images to save space
                        docker rmi ${ECR_REGISTRY}/${ECR_REPOSITORY}:${env.IMAGE_TAG} || true
                    fi
                    docker system prune -f || true
                """
            }
        }
        
        success {
            script {
                if (env.BRANCH_NAME == 'main') {
                    echo "Production deployment successful!"
                    echo "StatusPage ${env.IMAGE_TAG} is now live"
                }
            }
        }
        
        failure {
            script {
                if (env.BRANCH_NAME == 'main') {
                    echo "Production deployment failed!"
                    sh """
                        # Show recent pod events for debugging
                        kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp' | tail -20 || true
                        
                        # Show pod logs
                        kubectl logs -l app.kubernetes.io/name=statuspage-chart -n ${NAMESPACE} --tail=50 || true
                        
                        # Rollback to previous version
                        echo "Rolling back to previous Helm release..."
                        helm rollback statuspage --namespace ${NAMESPACE} || echo "No rollback available"
                    """
                }
            }
        }
        
        cleanup {
            script {
                sh 'docker logout ${ECR_REGISTRY} || true'
            }
        }
    }
}
