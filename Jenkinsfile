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
                        apt-get update
                        apt-get install -y curl docker.io awscli wget

                        curl -LO "https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl"
                        chmod +x kubectl
                        mv kubectl /usr/local/bin/

                        curl https://get.helm.sh/helm-v3.12.0-linux-amd64.tar.gz | tar -xz
                        mv linux-amd64/helm /usr/local/bin/

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
                        echo "=== Version Management Started ==="

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

                        if [ -f "terraform/charts/statuspage-chart/values.yaml" ]; then
                            sed -i "s/tag: \\".*\\"/tag: \\"$IMAGE_TAG\\"/" terraform/charts/statuspage-chart/values.yaml
                            echo "Updated values.yaml with tag: $IMAGE_TAG"
                        fi

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
                    def newVersion = readFile('.jenkins_version').trim()
                    def imageTag = readFile('.jenkins_tag').trim()

                    echo "Building with version: ${newVersion}, tag: ${imageTag}"

                    sh """
                        docker build -f status-page/Dockerfile -t statuspage-app:${imageTag} ./status-page/
                        docker tag statuspage-app:${imageTag} ${ECR_REGISTRY}/${ECR_REPOSITORY}:${imageTag}
                        aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | docker login --username AWS --password-stdin ${ECR_REGISTRY}
                        docker push ${ECR_REGISTRY}/${ECR_REPOSITORY}:${imageTag}
                        echo "✅ Image built and pushed: ${imageTag}"
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
                    def imageTag = readFile('.jenkins_tag').trim()

                    sh """
                        aws eks update-kubeconfig --region ${AWS_DEFAULT_REGION} --name ${EKS_CLUSTER}
                        aws sts get-caller-identity

                        cd terraform/charts/statuspage-chart
                        helm upgrade statuspage . \
                            --namespace ${NAMESPACE} \
                            --install \
                            --wait \
                            --timeout 600s \
                            --set image.tag=${imageTag}

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
                        kubectl wait --for=condition=ready pod \
                            -l app.kubernetes.io/name=statuspage-chart \
                            -n ${NAMESPACE} \
                            --timeout=300s

                        echo "✅ Health check passed for deployment: ${imageTag}"
                    """
                }
            }
        }
    }

    post {
        always {
            script {
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
                    try { imageTag = readFile('.jenkins_tag').trim() } catch (Exception e) { imageTag = "unknown" }

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
                    rm -f .jenkins_version .jenkins_tag jenkins.env temp.env || true
                    docker logout ${ECR_REGISTRY} || true
                '''
            }
        }
    }
}

