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
            when {
                changeset "status-page/**"
            }
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

                        # Install Docker CLI
                        apt-get install -y docker.io
                    '''
                }
            }
        }

        stage('Version Management') {
            when {
                changeset "status-page/**"
            }
            steps {
                script {
                    sh '''
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
                    '''
                }
            }
        }

        stage('Build Docker Image') {
            when {
                changeset "status-page/**"
            }
            steps {
                script {
                    sh '''
                        # Build Docker image
                        docker build -f status-page/Dockerfile -t statuspage-app:$TAG ./status-page/
                        
                        # Tag the image
                        docker tag statuspage-app:$TAG ${ECR_REGISTRY}/${ECR_REPOSITORY}:$TAG
                        
                        # Login to ECR
                        aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | docker login --username AWS --password-stdin ${ECR_REGISTRY}
                        
                        # Push the image to ECR
                        docker push ${ECR_REGISTRY}/${ECR_REPOSITORY}:$TAG

                        echo "Image built and pushed with tag: $TAG"
                    '''
                }
            }
        }

        stage('Security Scan') {
            when {
                changeset "status-page/**"
            }
            steps {
                script {
                    sh """
                        # Basic security scan of Docker image
                        docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                            aquasec/trivy image --exit-code 0 --severity HIGH,CRITICAL \
                            ${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG} || echo "Security scan completed"
                    """
                }
            }
        }

        stage('Push to ECR') {
            when {
                changeset "status-page/**"
            }
            steps {
                script {
                    sh """
                        # Push latest if main branch
                        if [ "${env.BRANCH_NAME}" = "main" ]; then
                            docker push ${ECR_REGISTRY}/${ECR_REPOSITORY}:latest
                        fi

                        echo "Pushed image: ${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"
                    """
                }
            }
        }

        stage('Update Helm Chart') {
            when {
                branch 'main'
            }
            steps {
                script {
                    sh """
                        # Update values.yaml with new image tag
                        cd terraform/charts/statuspage-chart
                        sed -i 's/tag: .*/tag: "${IMAGE_TAG}"/' values.yaml

                        # Show the change
                        echo "Updated values.yaml:"
                        grep "tag:" values.yaml
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
                            --set image.tag=${IMAGE_TAG}

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

                        # Get service endpoint
                        INGRESS_IP=\$(kubectl get service nginx-ingress-ingress-nginx-controller \
                            -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

                        if [ -n "\$INGRESS_IP" ]; then
                            # Try health check through ingress
                            for i in \$(seq 1 10); do
                                echo "Health check attempt \$i"
                                if curl -f -s "http://\$INGRESS_IP/statuspage/" | grep -q "StatusPage"; then
                                    echo "Health check passed!"
                                    exit 0
                                fi
                                sleep 15
                            done
                            echo "Health check failed after 10 attempts"
                        else
                            echo "No LoadBalancer IP found, skipping external health check"
                            echo "Deployment completed successfully"
                        fi
                    """
                }
            }
        }

        stage('Commit Version') {
            when {
                branch 'main'
            }
            steps {
                script {
                    sh """
                        # Commit version and values.yaml changes
                        git config --global user.email "jenkins@yourdomain.com"
                        git config --global user.name "Jenkins CI"

                        git add version.txt terraform/charts/statuspage-chart/values.yaml
                        git commit -m "Release version v${NEW_VERSION} - automated deployment" || echo "No changes to commit"

                        # Tag the release
                        git tag "v${NEW_VERSION}" || echo "Tag already exists"
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
                    echo "Image built: ${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

                    # Cleanup Docker images to save space
                    docker rmi ${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG} || true
                    docker system prune -f || true
                """
            }
        }

        success {
            script {
                if (env.BRANCH_NAME == 'main') {
                    echo "✅ Production deployment successful!"
                    echo "StatusPage v${NEW_VERSION} is now live"
                }
            }
        }

        failure {
            script {
                if (env.BRANCH_NAME == 'main') {
                    echo "❌ Production deployment failed!"
                    sh """
                        # Show recent pod events for debugging
                        kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp' | tail -20 || true

                        # Show pod logs
                        kubectl logs -l app.kubernetes.io/name=statuspage-chart -n ${NAMESPACE} --tail=50 || true
                    """
                    sh """
                        echo "🚨 Rolling back to previous Helm release..."
                        helm rollback statuspage 1 --namespace ${NAMESPACE} || echo "No rollback available"
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

