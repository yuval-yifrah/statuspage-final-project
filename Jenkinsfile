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
                    // Use a single shell script to handle everything and write final results
                    sh '''
    			echo "=== Version Management Started ==="

    			# Get latest tag from ECR
    			LATEST_TAG=$(aws ecr describe-images \
      			--repository-name ${ECR_REPOSITORY} \
      			--query 'sort_by(imageDetails,& imagePushedAt)[-1].imageTags[0]' \
      			--output text 2>/dev/null || echo "v0")

    			if [[ "$LATEST_TAG" =~ ^v[0-9]+$ ]]; then
        			CURRENT_VERSION=${LATEST_TAG#v}
    			else
        			CURRENT_VERSION=0
    			fi

    			NEW_VERSION=$((CURRENT_VERSION + 1))
    			IMAGE_TAG="v$NEW_VERSION"

    			echo "Latest tag in ECR: $LATEST_TAG"
    			echo "New version: $NEW_VERSION"
    			echo "Image tag: $IMAGE_TAG"

    			# Update values.yaml
    			if [ -f "terraform/charts/statuspage-chart/values.yaml" ]; then
        		sed -i "s/tag: \\".*\\"/tag: \\"$IMAGE_TAG\\"/" terraform/charts/statuspage-chart/values.yaml
        		echo "Updated values.yaml with tag: $IMAGE_TAG"
    			fi

    			# Save for next stages
    			echo "$NEW_VERSION" > .jenkins_version
    			echo "$IMAGE_TAG" > .jenkins_tag

    			echo "=== Version Management Completed ==="
		    '''

                }
            }
        }
        
        stage('Build and Push Docker Image') {
            steps {
                script {
                    // Read the values from files
                    def newVersion = readFile('.jenkins_version').trim()
                    def imageTag = readFile('.jenkins_tag').trim()
                    
                    echo "Building with version: ${newVersion}, tag: ${imageTag}"
                    
                    sh """
                        echo "Building Docker image with tag: ${imageTag}"
                        
                        # Build Docker image
                        docker build -f status-page/Dockerfile -t statuspage-app:${imageTag} ./status-page/
                        
                        # Tag for ECR
                        docker tag statuspage-app:${imageTag} ${ECR_REGISTRY}/${ECR_REPOSITORY}:${imageTag}
                        
                        # Login to ECR
                        aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | docker login --username AWS --password-stdin ${ECR_REGISTRY}
                        
                        # Push to ECR
                        docker push ${ECR_REGISTRY}/${ECR_REPOSITORY}:${imageTag}
                        
                        echo "Image built and pushed successfully: ${imageTag}"
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
                    // Read the tag from file
                    def imageTag = readFile('.jenkins_tag').trim()
                    
                    echo "Deploying to EKS with tag: ${imageTag}"
                    
                    sh """
                        echo "Configuring EKS access..."
                        
                        # Configure kubectl for EKS
                        aws eks update-kubeconfig --region ${AWS_DEFAULT_REGION} --name ${EKS_CLUSTER}
                        
                        # Test connection and get proper AWS identity
                        echo "Testing AWS credentials:"
                        aws sts get-caller-identity
                        
                        echo "Testing EKS connection:"
                        if ! kubectl get nodes --request-timeout=10s; then
                            echo "Failed to connect to EKS cluster"
                            echo "Checking if cluster exists:"
                            aws eks describe-cluster --name ${EKS_CLUSTER} --region ${AWS_DEFAULT_REGION} || true
                            exit 1
                        fi
                        
                        echo "EKS connection successful, deploying..."
                        
                        # Deploy using Helm
                        cd terraform/charts/statuspage-chart
                        helm upgrade statuspage . \
                            --namespace ${NAMESPACE} \
                            --install \
                            --wait \
                            --timeout 600s \
                            --set image.tag=${imageTag}
                        
                        echo "Deployment completed with tag: ${imageTag}"
                        
                        # Show deployment status
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
                    def imageTag = readFile('.jenkins_tag').trim()
                    
                    sh """
                        echo "Running health check for tag: ${imageTag}"
                        
                        # Wait for pods to be ready
                        kubectl wait --for=condition=ready pod \
                            -l app.kubernetes.io/name=statuspage-chart \
                            -n ${NAMESPACE} \
                            --timeout=300s
                        
                        echo "Health check passed for deployment: ${imageTag}"
                    """
                }
            }
        }
    }
    
    post {
        always {
            script {
                // Try to read the tag, but handle case where it doesn't exist
                def imageTag = ""
                try {
                    imageTag = readFile('.jenkins_tag').trim()
                } catch (Exception e) {
                    imageTag = "unknown"
                }
                
                sh """
                    echo "Pipeline completed for branch: ${BRANCH_NAME}"
                    if [ "${imageTag}" != "unknown" ] && [ "${imageTag}" != "" ]; then
                        echo "Image built: ${ECR_REGISTRY}/${ECR_REPOSITORY}:${imageTag}"
                        # Cleanup Docker images
                        docker rmi ${ECR_REGISTRY}/${ECR_REPOSITORY}:${imageTag} || true
                    fi
                    docker system prune -f || true
                """
            }
        }
        
        success {
            script {
                if (env.BRANCH_NAME == 'main') {
                    def imageTag = ""
                    try {
                        imageTag = readFile('.jenkins_tag').trim()
                    } catch (Exception e) {
                        imageTag = "unknown"
                    }
                    
                    echo "Production deployment successful!"
                    echo "StatusPage ${imageTag} is now live"
                }
            }
        }
        
        failure {
            script {
                if (env.BRANCH_NAME == 'main') {
                    echo "Production deployment failed!"
                    sh """
                        # Try to show debug info, but don't fail if kubectl doesn't work
                        echo "Attempting to gather debug information..."
                        kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp' 2>/dev/null | tail -20 || echo "Could not get events"
                        kubectl logs -l app.kubernetes.io/name=statuspage-chart -n ${NAMESPACE} --tail=50 2>/dev/null || echo "Could not get logs"
                        helm rollback statuspage --namespace ${NAMESPACE} 2>/dev/null || echo "Could not rollback"
                    """
                }
            }
        }
        
        cleanup {
            script {
                sh '''
                    # Clean up temporary files
                    rm -f .jenkins_version .jenkins_tag jenkins.env temp.env || true
                    docker logout ${ECR_REGISTRY} || true
                '''
            }
        }
    }
}
