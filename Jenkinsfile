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
        // Initialize variables
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
                    // Debug: Show current directory and files
                    sh '''
                        echo "Current directory: $(pwd)"
                        echo "Files in current directory:"
                        ls -la
                        echo "Looking for version.txt:"
                        find . -name "version.txt" -type f
                    '''
                    
                    // Fail if version.txt doesn't exist
                    if (!fileExists('version.txt')) {
                        error("version.txt file not found! This file should exist with the current version number.")
                    }
                    
                    // Read current version
                    def versionContent = readFile('version.txt').trim()
                    echo "Found version.txt with content: '${versionContent}'"
                    
                    if (!versionContent || versionContent.isEmpty()) {
                        error("version.txt is empty! It should contain a version number.")
                    }
                    
                    def currentVersion = versionContent.toInteger()
                    echo "Parsed current version as integer: ${currentVersion}"
                    
                    def newVersion = currentVersion + 1
                    echo "Calculated new version: ${newVersion}"
                    
                    def imageTag = "v${newVersion}"
                    echo "Created image tag: ${imageTag}"
                    
                    // Set environment variables with explicit conversion
                    env.NEW_VERSION = String.valueOf(newVersion)
                    env.IMAGE_TAG = String.valueOf(imageTag)
                    
                    echo "Set env.NEW_VERSION to: ${env.NEW_VERSION}"
                    echo "Set env.IMAGE_TAG to: ${env.IMAGE_TAG}"
                    
                    // Save new version
                    echo "About to write '${env.NEW_VERSION}' to version.txt"
                    writeFile file: 'version.txt', text: env.NEW_VERSION
                    echo "Successfully wrote to version.txt"
                    
                    echo "Version updated from ${currentVersion} to ${newVersion}"
                    echo "Building and deploying with tag: ${env.IMAGE_TAG}"
                    
                    // Update values.yaml with new tag
                    sh """
                        sed -i 's/tag: ".*"/tag: "${env.IMAGE_TAG}"/' terraform/charts/statuspage-chart/values.yaml
                        echo "Updated values.yaml:"
                        grep "tag:" terraform/charts/statuspage-chart/values.yaml
                    """
                }
            }
        }
        
        stage('Build and Push Docker Image') {
            steps {
                script {
                    sh """
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
