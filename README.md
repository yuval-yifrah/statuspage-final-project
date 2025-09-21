# StatusPage Infrastructure on AWS EKS

## Overview

This project deploys a production-ready StatusPage application on AWS using Infrastructure as Code (Terraform) and GitOps (ArgoCD). The infrastructure includes a scalable Kubernetes cluster, managed databases, SSL certificates, and comprehensive monitoring with CI/CD automation.

## Architecture

### High-Level Architecture

```
Internet
    ↓
Route 53 DNS (your-domain.com)
    ↓
┌─────────────────── AWS VPC (10.0.0.0/16) ──────────────────┐
│                                                            │
│  Internet Gateway (IGW)                                    │
│            ↓                                               │
│  ┌─── Public Subnets (2 AZs) ──-─┐                         │
│  │  NAT Gateway + Elastic IP     │                         │
│  │                               │                         │
│  │  ┌─ NLB #1 (StatusPage) ──────┼─→ EKS StatusPage Pods   │
│  │  │  Port 443 (HTTPS)          │   (Service: port 80)    │
│  │  │  ACM SSL Certificate       │                         │
│  │  │                            │                         │
│  │  ┌─ NLB #2 (ArgoCD) ──────────┼─→ EKS ArgoCD Server     │
│  │  │  Port 80/443               │   (Service: port 80)    │
│  │  │                            │                         │
│  │  └─ NLB #3 (Grafana) ─────────┼─→ EKS Grafana Service   │
│     │  Port 80                   │   (Service: port 80)    │
│     └────────────────────────────┼───────────────────────  │
│                                  │                         │
│  ┌─── Private Subnets (2 AZs) ──-┴───┐                     │
│  │                                   │                     │
│  │  EKS Cluster (3 t3.medium SPOT)   │                     │
│  │  ├── StatusPage App (2 pods)      │ ←── ECR Registry    │
│  │  │   └── Connects to RDS + Redis  │                     │
│  │  ├── ArgoCD (GitOps)              │                     │
│  │  │   └── Syncs from GitHub        │                     │
│  │  ├── Grafana + Prometheus         │                     │
│  │  │   └── Monitors all pods        │                     │
│  │  ├── Cert-Manager                 │                     │
│  │  └── CSI Secrets Store            │                     │
│  │                                   │                     │
│  │  RDS PostgreSQL (db.m5.large)     │                     │
│  │  └── Port 5432 (private only)     │                     │
│  │                                   │                     │
│  │  ElastiCache Redis (t3.micro)     │                     │
│  │  └── Port 6379 (private only)     │                     │
│  └───────────────────────────────────┘                     │
│                                                            │
│  External AWS Services:                                    │
│  ├── AWS Secrets Manager ←─── IRSA ──── ServiceAccounts    │
│  ├── S3 (Terraform State - Optional)                       │
│  └── ECR (Container Images)                                │
└────────────────────────────────────────────────────────────┘

External CI/CD Flow:
GitHub Actions (CI/CD)
    ↓ (build & push)
ECR Repository
    ↓ (pull images)
ArgoCD (Auto-sync every 3 min)
    ↓ (deploy)
EKS Cluster
```

### Infrastructure Components

#### AWS Infrastructure
- **EKS Cluster**: Managed Kubernetes (v1.28) with 3 SPOT worker nodes (t3.medium)
  - Private subnets deployment for enhanced security
  - Auto Scaling Group with desired: 3, min: 2, max: 4
- **VPC**: Custom VPC (10.0.0.0/16) with public/private subnets across 2 AZs
  - Public Subnets: 10.0.1.0/24, 10.0.2.0/24 (for Load Balancers and NAT Gateway)
  - Private Subnets: 10.0.3.0/24, 10.0.4.0/24 (for applications and databases)
- **Internet Gateway (IGW)**: Provides internet connectivity to public subnets
- **NAT Gateway**: Single NAT Gateway with Elastic IP for private subnet internet access
  - Cost optimization: Single NAT instead of multi-AZ setup
- **Network Load Balancers (NLBs)**:
  - **StatusPage NLB**: Internet-facing, SSL termination with ACM certificate (Port 443 → 80)
  - **ArgoCD NLB**: Internet-facing for GitOps management (Port 80)
  - **Grafana NLB**: Internet-facing for monitoring dashboards (Port 80)
- **S3 Bucket**: (Optional) Terraform state storage for team collaboration
  - Server-side encryption enabled
  - Versioning enabled for state history
- **ECR**: Container registry for application images
  - Image scanning enabled for vulnerability detection
  - Lifecycle policies for automatic image cleanup
  - Cross-region replication support
- **RDS PostgreSQL**: Primary database (db.m5.large, encrypted, v16.8)
  - Multi-AZ deployment for high availability
  - Automated backups with 7-day retention (03:00-04:00 UTC backup window)
  - Private subnets only - no public access
- **ElastiCache Redis**: Caching and session storage (cache.t3.micro)
  - Encryption at rest enabled
  - Single node for cost optimization
- **ACM**: SSL certificates for HTTPS
  - Automatic renewal via Route 53 DNS validation
  - Wildcard support for subdomains
- **Route 53**: DNS management
  - Hosted zone with DNS validation records
  - A records pointing to NLB endpoints
  - Health checks for failover scenarios
- **AWS Secrets Manager**: Secure storage for sensitive data
  - Database credentials
  - Grafana admin password
  - Automatic rotation policies available
- **Security Groups**: Controlled access between components
  - EKS Cluster SG, EKS Nodes SG, RDS SG, ElastiCache SG
  - Least-privilege network access rules
  - Dynamic rules updated by fix-security-groups.sh script

#### Kubernetes Components
- **StatusPage**: Django-based status page application with Gunicorn
- **ArgoCD**: GitOps continuous deployment
- **Grafana**: Monitoring dashboards with LoadBalancer service
- **Prometheus**: Metrics collection and alerting with persistent storage
- **AlertManager**: Alert routing and management
- **Cert-Manager**: SSL certificate automation
- **CSI Secrets Store**: AWS Secrets Manager integration
- **EBS CSI Driver**: Persistent volume management

## Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.5.0
- kubectl
- Docker
- Git
- GitHub repository with Actions enabled

## Complete Setup Guide

Follow these steps in order to deploy a fully functional StatusPage infrastructure identical to the original.

### Step 1: Prerequisites Setup

#### 1.1 Domain Configuration
```bash
# Option A: Purchase new domain via Route 53
aws route53domains register-domain --domain-name your-domain.com

# Option B: Use existing domain - create hosted zone
aws route53 create-hosted-zone --name your-domain.com --caller-reference $(date +%s)

# Get nameservers and update at your domain registrar
aws route53 get-hosted-zone --id YOUR_HOSTED_ZONE_ID
```

#### 1.2 Create EC2 Key Pair
```bash
# Create SSH key pair for EKS node access
aws ec2 create-key-pair --key-name your-statuspage-keypair --output text --query 'KeyMaterial' > ~/.ssh/your-statuspage-keypair.pem
chmod 400 ~/.ssh/your-statuspage-keypair.pem
```

#### 1.3 GitHub Repository Setup
```bash
# Fork or clone the repository
git clone https://github.com/your-username/statuspage-project.git
cd statuspage-project

# Add GitHub Secrets (in GitHub web interface):
# Settings → Secrets and variables → Actions → New repository secret
# Add:
#   AWS_ACCESS_KEY_ID: your-aws-access-key-id
#   AWS_SECRET_ACCESS_KEY: your-aws-secret-access-key
```

### Step 2: Configuration Files Setup

#### 2.1 Create Terraform Configuration
```bash
# Copy and edit terraform variables
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform/terraform.tfvars`:
```hcl
# AWS Configuration
aws_region = "us-east-1"

# Domain Configuration  
domain_name = "your-domain.com"
ssl_email = "your-email@example.com"

# Project Configuration
project_name = "statuspage"
prefix = "your-prefix-"
environment = "prod"

# Infrastructure Configuration
node_instance_type = "t3.medium"
node_desired_size = 3
node_max_size = 4
node_min_size = 2
db_instance_class = "db.m5.large"

# SSH Key for nodes
key_pair_name = "your-statuspage-keypair"
```

#### 2.2 Update Application Configuration
Edit `terraform/charts/statuspage-chart/values.yaml`:

```yaml
image:
  repository: YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/your-prefix-statuspage-repo
  tag: "v1"

django:
  env:
    SITE_URL: "https://your-domain.com"
    CSRF_TRUSTED_ORIGINS: "https://your-domain.com"
```

#### 2.3 Update CI/CD Configuration
Edit `.github/workflows/cd-deploy.yml` and `.github/workflows/ci-test.yml`:

**Important**: Make sure both files have consistent naming that matches your terraform.tfvars prefix.

```yaml
env:
  ECR_REGISTRY: YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com
  ECR_REPOSITORY: your-prefix-statuspage-repo  # Must match: ${prefix}${project_name}-repo
  AWS_REGION: us-east-1
```

**To get your AWS Account ID:**
```bash
aws sts get-caller-identity --query Account --output text
```

**Example**: If your prefix is "company-", then:
- ECR_REPOSITORY should be: `company-statuspage-repo`
- This matches the Terraform resource: `${var.prefix}${var.project_name}-repo`

#### 2.4 Update Security Groups Fix Script
Edit the first few lines of `terraform/fix-security-groups.sh`:

```bash
#!/bin/bash
# Configuration - Update these values to match your terraform.tfvars
PREFIX="your-prefix-"
PROJECT_NAME="statuspage"
AWS_REGION="us-east-1"

# Rest of the script uses these variables
CLUSTER_NAME="${PREFIX}${PROJECT_NAME}-cluster"
REGION="${AWS_REGION}"
```

#### 2.5 Update Terraform Resource References
Several Terraform files need updates to use variables instead of hardcoded names:

**Edit `terraform/main.tf` (line 27):**
```hcl
# Change:
data "aws_secretsmanager_secret" "db_credentials" {
  name = "your-statuspage-db-credentials"
}

# To:
data "aws_secretsmanager_secret" "db_credentials" {
  name = "${var.prefix}statuspage-db-credentials"
}
```

**Edit `terraform/helm.tf`:**
```hcl
# Lines 1-6 - Change:
data "aws_eks_cluster" "cluster" {
  name = "ly-statuspage-cluster"
}

# To:
data "aws_eks_cluster" "cluster" {
  name = aws_eks_cluster.ly_eks.name
}

# Line 19 - Change:
data "aws_iam_role" "nodegroup_role" {
  name = "ly-statuspage-eks-nodegroup-role"
}

# To:
data "aws_iam_role" "nodegroup_role" {
  name = aws_iam_role.eks_nodegroup_role.name
}

# Line 72 - Change:
data "aws_secretsmanager_secret" "grafana_admin_password" {
  name = "ly-grafana-admin-password"
}

# To:
data "aws_secretsmanager_secret" "grafana_admin_password" {
  name = "${var.prefix}grafana-admin-password"
}

# Line 104 in SecretProviderClass - Change:
objectName: "ly-statuspage-db-credentials"

# To:
objectName: "${var.prefix}statuspage-db-credentials"

# Line 259 in ArgoCD Application - Update your GitHub repository URL:
repoURL: https://github.com/your-username/statuspage-project.git
```

#### 2.6 Verify build.sh Script
Check if `build.sh` contains any hardcoded values that need updating:
```bash
# Review the build script for any specific account IDs or repository names
cat build.sh

# Update any hardcoded values to use variables or make them generic
```

### Step 3: Create AWS Secrets (Required)

```bash
# Database credentials (Required)
aws secretsmanager create-secret \
    --name your-prefix-statuspage-db-credentials \
    --description "StatusPage database credentials" \
    --secret-string '{"username":"statuspage","password":"your-secure-db-password-here"}'

# Grafana admin password (Required)
aws secretsmanager create-secret \
    --name your-prefix-grafana-admin-password \
    --description "Grafana admin password" \
    --secret-string '{"password":"your-secure-grafana-password-here"}'
```

### Step 4: Optional - Configure Remote State for Team Collaboration

The project includes a `terraform/backend.tf` file for storing Terraform state in S3. This is useful for team collaboration but not required for single-user deployments.

#### Option A: Team/Shared Environment (Recommended for teams)
```bash
# Create S3 bucket for Terraform state
aws s3 mb s3://your-terraform-state-bucket-name

# Enable versioning for state history
aws s3api put-bucket-versioning \
    --bucket your-terraform-state-bucket-name \
    --versioning-configuration Status=Enabled

# Update terraform/backend.tf with your bucket name:
terraform {
  backend "s3" {
    bucket = "your-terraform-state-bucket-name"
    key    = "terraform.tfstate"
    region = "us-east-1"
  }
}
```

#### Option B: Single User (Local State)
```bash
# Simply remove the backend configuration file
rm terraform/backend.tf

# Terraform will use local state storage instead
```

**Why use S3 backend?**
- Enables team collaboration on the same infrastructure
- Provides state locking to prevent conflicts
- Keeps state history and versioning
- Allows disaster recovery of infrastructure state

**Note**: The project includes `backend.tf` by default for team environments, but it's perfectly fine to remove it for personal use.

### Step 4: Deploy Infrastructure

```bash
cd terraform

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy infrastructure (takes ~15-20 minutes)
terraform apply

# Note the outputs - you'll need them later
terraform output rds_endpoint
terraform output redis_endpoint
terraform output ecr_repository_url
```

### Step 5: Update Values with Terraform Outputs

After Terraform completes, update `terraform/charts/statuspage-chart/values.yaml` with actual values:

```bash
# Get the outputs
RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
REDIS_ENDPOINT=$(terraform output -raw redis_endpoint)
CERT_ARN=$(terraform output -raw statuspage_cert_arn)
ECR_URL=$(terraform output -raw ecr_repository_url)

# Update values.yaml
sed -i "s|host: \"\"|host: $RDS_ENDPOINT|g" terraform/charts/statuspage-chart/values.yaml
sed -i "s|host: \"\"|host: $REDIS_ENDPOINT|g" terraform/charts/statuspage-chart/values.yaml
sed -i "s|service.beta.kubernetes.io/aws-load-balancer-ssl-cert: \"\"|service.beta.kubernetes.io/aws-load-balancer-ssl-cert: $CERT_ARN|g" terraform/charts/statuspage-chart/values.yaml
sed -i "s|repository: .*|repository: $ECR_URL|g" terraform/charts/statuspage-chart/values.yaml
```

### Step 6: Configure kubectl and Fix Connectivity

```bash
# Configure kubectl
aws eks update-kubeconfig --name your-prefix-statuspage-cluster --region us-east-1

# Run security groups fix (important!)
bash terraform/fix-security-groups.sh

# Verify deployment
kubectl get pods -A
kubectl get svc -A
```

### Step 7: Deploy Application

#### Option A: Automatic Deployment (Recommended)
```bash
# Commit and push your changes to trigger CI/CD
git add .
git commit -m "Initial deployment configuration"
git push origin main

# The CI/CD pipeline will automatically:
# 1. Build Docker image
# 2. Push to ECR
# 3. Update values.yaml
# 4. ArgoCD will deploy automatically
```

#### Option B: Manual Initial Deployment
```bash
# Use the build script for first deployment
chmod +x build.sh
./build.sh

# The build.sh script will automatically:
# 1. Build Docker image
# 2. Login to ECR  
# 3. Tag and push image
# 4. Deploy via Helm

# Alternatively, you can run the individual commands:
# cd status-page
# docker build -t statuspage:v1 .
# aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_URL
# docker tag statuspage:v1 $ECR_URL:v1
# docker push $ECR_URL:v1
# cd ../terraform
# helm install statuspage charts/statuspage-chart/ --namespace default
```

### Step 8: Final Configuration

#### 8.1 Create StatusPage Admin User
```bash
# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=statuspage-chart --timeout=300s

# Create admin user
kubectl exec -it $(kubectl get pods -n default -l app.kubernetes.io/name=statuspage-chart -o jsonpath='{.items[0].metadata.name}') -- python manage.py createsuperuser
```

#### 8.2 Get Access URLs
```bash
# StatusPage Application
echo "StatusPage: https://your-domain.com"

# ArgoCD UI
kubectl get svc -n argocd argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Grafana UI  
kubectl get svc -n monitoring monitoring-grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

#### 8.3 Get Access Credentials

**ArgoCD:**
```bash
# Username: admin
# Password:
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

**Grafana:**
```bash
# Username: admin  
# Password:
aws secretsmanager get-secret-value --secret-id your-prefix-grafana-admin-password --query SecretString --output text | jq -r .password
```

### Step 9: Verification Checklist

Verify everything is working:

```bash
# ✓ All pods running
kubectl get pods -A | grep -v Running

# ✓ Application accessible
curl -I https://your-domain.com

# ✓ Database connectivity
kubectl exec -it $(kubectl get pods -n default -l app.kubernetes.io/name=statuspage-chart -o jsonpath='{.items[0].metadata.name}') -- python manage.py dbshell -c "SELECT 1;"

# ✓ Redis connectivity  
kubectl exec -it $(kubectl get pods -n default -l app.kubernetes.io/name=statuspage-chart -o jsonpath='{.items[0].metadata.name}') -- python -c "import redis; r=redis.Redis(host='$REDIS_ENDPOINT'); print(r.ping())"

# ✓ SSL certificate
openssl s_client -connect your-domain.com:443 -servername your-domain.com < /dev/null 2>/dev/null | openssl x509 -text | grep "Not After"

# ✓ ArgoCD sync status
kubectl get applications -n argocd
```

## Customizing Resource Names and Configuration

If you want to change the default resource naming or configuration beyond the basic setup, here are the key files to modify:

### Changing Project Prefix/Names

**Primary Configuration (terraform/terraform.tfvars):**
```hcl
# Change these values to customize resource naming
project_name = "statuspage"           # Changes all resource names
prefix = "your-company-"              # Changes resource prefix (default: ly-)
aws_region = "us-east-1"              # Keep as us-east-1 or change to your preferred region
```

**If you change the AWS region from us-east-1, also update:**

1. **terraform/charts/statuspage-chart/values.yaml:**
```yaml
image:
  repository: YOUR_ACCOUNT_ID.dkr.ecr.YOUR_REGION.amazonaws.com/your-prefix-statuspage-repo
```

2. **.github/workflows/ci-test.yml and cd-deploy.yml:**
```yaml
env:
  ECR_REGISTRY: YOUR_ACCOUNT_ID.dkr.ecr.YOUR_REGION.amazonaws.com
  AWS_REGION: your-aws-region
```

### Files That Auto-Update Based on terraform.tfvars:
- All Terraform resources (main.tf, helm.tf, iam.tf)
- EKS cluster name
- RDS instance name  
- Redis cluster name
- Security group names
- IAM role names

### Files That Require Manual Updates:
- `terraform/charts/statuspage-chart/values.yaml` (image repository URL)
- `.github/workflows/*.yml` (ECR registry and region)
- Domain-specific configurations

### Resource Naming Convention:
With `prefix = "company-"` and `project_name = "statuspage"`, you'll get:
- EKS Cluster: `company-statuspage-cluster`
- RDS: `company-statuspage-rds`
- Redis: `company-statuspage-redis`
- ECR: `company-statuspage-repo`

### Automatic Updates
Once deployed, any changes to the `status-page/` directory will automatically trigger CI/CD:
1. GitHub Actions builds new Docker image
2. Pushes to ECR with incremented version
3. Updates values.yaml
4. ArgoCD syncs changes within 3 minutes

### Monitoring
Access Grafana to monitor:
- Application performance
- Infrastructure metrics  
- Database and Redis status
- SSL certificate expiration

### Maintenance
The system includes:
- Automatic SSL certificate renewal
- Automated database backups (7-day retention)
- HPA scaling (2-10 pods based on load)
- SPOT instance cost optimization

## Repository Structure

```
.
├── terraform/
│   ├── main.tf              # Core AWS infrastructure
│   ├── helm.tf              # Kubernetes applications deployment
│   ├── iam.tf               # IRSA and IAM configurations
│   ├── variables.tf         # Configuration variables
│   ├── outputs.tf           # Infrastructure outputs
│   ├── fix-security-groups.sh  # Auto-fix connectivity script
│   └── charts/
│       └── statuspage-chart/
│           ├── Chart.yaml
│           ├── values.yaml   # Application configuration
│           └── templates/
├── status-page/             # Django application source code
│   ├── Dockerfile           # Multi-stage production build
│   └── statuspage/
├── .github/
│   └── workflows/
│       ├── ci-test.yml      # CI pipeline for PRs
│       └── cd-deploy.yml    # CD pipeline for main branch
└── README.md
```

## Terraform Infrastructure Deployment

### What Terraform Creates

Terraform automatically provisions the following AWS resources in the correct order:

#### **Phase 1: Core Networking**
```bash
terraform apply -target=aws_vpc.main -target=aws_internet_gateway.main
```
- **VPC** (10.0.0.0/16) with DNS hostnames enabled
- **Internet Gateway** for public internet access
- **2 Public Subnets** across different AZs (10.0.1.0/24, 10.0.2.0/24)
- **2 Private Subnets** across different AZs (10.0.3.0/24, 10.0.4.0/24)
- **Elastic IP** for NAT Gateway
- **NAT Gateway** in first public subnet for private subnet internet access
- **Route Tables** and associations for public and private subnets

#### **Phase 2: Security & IAM**
```bash
terraform apply -target=module.iam -target=aws_security_group.*
```
- **Security Groups** for EKS cluster, nodes, RDS, and ElastiCache
- **IAM Roles** for EKS cluster and node groups
- **IAM Policies** for Secrets Manager access, EBS CSI driver
- **IRSA (IAM Roles for Service Accounts)** for StatusPage and Grafana
- **OIDC Identity Provider** for EKS cluster

#### **Phase 3: Databases & Storage**
```bash
terraform apply -target=aws_db_instance.main -target=aws_elasticache_replication_group.main
```
- **RDS PostgreSQL** database (db.m5.large) in private subnets
- **DB Subnet Group** spanning both private subnets
- **ElastiCache Redis** cluster (cache.t3.micro) in private subnets
- **ElastiCache Subnet Group** for Redis placement
- **ECR Repository** with image scanning enabled

#### **Phase 4: EKS Cluster**
```bash
terraform apply -target=aws_eks_cluster.main -target=aws_eks_node_group.main
```
- **EKS Cluster** (v1.28) with public and private subnet access
- **EKS Node Group** with 3 t3.medium SPOT instances in private subnets
- **SSH access** configuration for worker nodes

#### **Phase 5: SSL & DNS**
```bash
terraform apply -target=aws_acm_certificate.main -target=aws_route53_record.*
```
- **ACM SSL Certificate** for your domain
- **Route 53 DNS validation** records for certificate verification
- **Certificate validation** completion

#### **Phase 6: Kubernetes Applications** (via Helm)
```bash
# These are deployed after EKS cluster is ready
terraform apply -target=helm_release.*
```
- **CSI Secrets Store Driver** for AWS Secrets Manager integration
- **AWS Secrets Store Provider** for the CSI driver
- **EBS CSI Driver** for persistent volume management
- **Cert-Manager** for SSL certificate automation
- **ArgoCD** with LoadBalancer service (NLB)
- **Prometheus + Grafana Stack** with LoadBalancer service (NLB)
- **SecretProviderClass** resources for database credentials

### Terraform Execution Commands

```bash
# 1. Initialize Terraform
cd terraform
terraform init

# 2. Validate configuration
terraform validate

# 3. Plan deployment (review what will be created)
terraform plan -out=tfplan

# 4. Apply all resources (recommended - handles dependencies automatically)
terraform apply tfplan

# Alternative: Apply in phases for large deployments
terraform apply -target=aws_vpc.main -target=aws_internet_gateway.main
terraform apply -target=aws_eks_cluster.main
terraform apply -target=helm_release.monitoring

# 5. Get important outputs
terraform output rds_endpoint
terraform output redis_endpoint
terraform output eks_cluster_endpoint

# 6. Update kubectl configuration
aws eks update-kubeconfig --name ${var.prefix}${var.project_name}-cluster --region ${var.aws_region}

# 7. Run security groups fix (important!)
bash fix-security-groups.sh

# 8. Verify deployment
kubectl get pods -A
kubectl get svc -A
```

### Terraform State Management

The project supports both local and remote state:

```hcl
# Optional: Remote state configuration (create backend.tf)
terraform {
  backend "s3" {
    bucket = "your-terraform-state-bucket"
    key    = "statuspage/terraform.tfstate"
    region = "us-east-1"
  }
}
```

### Key Terraform Files

| File | Purpose |
|------|---------|
| `main.tf` | Core AWS infrastructure (VPC, EKS, RDS, Redis) |
| `helm.tf` | Kubernetes applications deployment |
| `iam.tf` | IAM roles, policies, and IRSA configuration |
| `variables.tf` | Input variables and defaults |
| `outputs.tf` | Important resource outputs |
| `fix-security-groups.sh` | Post-deployment connectivity fix |

### Deployment Time

- **Total deployment time**: ~15-20 minutes
- **EKS Cluster creation**: ~10-12 minutes
- **RDS creation**: ~5-7 minutes
- **Helm applications**: ~3-5 minutes

## Configuration

### Key Variables (terraform/variables.tf)

Update these variables according to your environment:

```hcl
variable "aws_region" {
  default = "us-east-1"
}

variable "domain_name" {
  default = "your-domain.com"
}

variable "project_name" {
  default = "statuspage"
}

variable "prefix" {
  default = "your-prefix-"
}

variable "ssl_email" {
  default = "your-email@example.com"
}

variable "key_pair_name" {
  default = "your-key-pair-name"
}
```

### Environment Variables Template

Create a `.env` file or update `values.yaml` with your specific values:

```yaml
django:
  database:
    host: ${rds_endpoint}  # From terraform output
    name: statuspage
    port: 5432
  redis:
    host: ${redis_endpoint}  # From terraform output
    port: 6379
  env:
    SITE_URL: "https://your-domain.com"
    CSRF_TRUSTED_ORIGINS: "https://your-domain.com,https://${load_balancer_dns}"
    SECURE_SSL_REDIRECT: "true"
    DEBUG: "false"
```

### Resource Configuration

```yaml
resources:
  requests:
    memory: "1.5Gi"
    cpu: "350m"
  limits:
    memory: "2.5Gi"
    cpu: "750m"

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80
```

## Installation

### 1. Clone Repository

```bash
git clone <your-repository-url>
cd statuspage-project
```

### 2. Configure AWS Credentials

```bash
aws configure
# Enter your AWS Access Key ID, Secret Access Key, and region
```

### 3. Set Up Configuration Files

First, create the required configuration files from examples:

```bash
# Copy example files
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
cp .env.example .env
```

Then update the following files with your specific values:

#### terraform/terraform.tfvars
```hcl
# AWS Configuration
aws_region = "us-east-1"

# Domain Configuration  
domain_name = "your-domain.com"
ssl_email = "your-email@example.com"

# Project Configuration
project_name = "statuspage"
prefix = "your-prefix-"
environment = "prod"

# Infrastructure Configuration
node_instance_type = "t3.medium"
node_desired_size = 3
db_instance_class = "db.m5.large"

# SSH Key for nodes (create in AWS EC2 console first)
key_pair_name = "your-key-pair-name"
```

#### terraform/charts/statuspage-chart/values.yaml
Update the following sections:

```yaml
image:
  repository: YOUR_ACCOUNT_ID.dkr.ecr.YOUR_REGION.amazonaws.com/your-statuspage-repo
  tag: "v1"

django:
  database:
    host: ""  # Will be populated from Terraform output
    name: statuspage
  redis:
    host: ""  # Will be populated from Terraform output
  env:
    SITE_URL: "https://your-domain.com"
    CSRF_TRUSTED_ORIGINS: "https://your-domain.com"

service:
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-ssl-cert: ""  # Will be populated from Terraform

serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: ""  # Will be populated from Terraform
```

#### .github/workflows/cd-deploy.yml and ci-test.yml
Update the environment variables:

```yaml
env:
  ECR_REGISTRY: YOUR_ACCOUNT_ID.dkr.ecr.YOUR_REGION.amazonaws.com
  ECR_REPOSITORY: your-statuspage-repo
  AWS_REGION: your-aws-region
```

#### terraform/fix-security-groups.sh
Update the script variables at the top:

```bash
#!/bin/bash
# Configuration - Update these values
PREFIX=${PREFIX:-"your-prefix-"}
PROJECT_NAME=${PROJECT_NAME:-"statuspage"}
AWS_REGION=${AWS_REGION:-"us-east-1"}

# Rest of the script remains the same
CLUSTER_NAME="${PREFIX}${PROJECT_NAME}-cluster"
REGION="${AWS_REGION}"
```

### 4. Set Up Secrets in AWS Secrets Manager

Create the following secrets in AWS Secrets Manager:

```bash
# Database credentials
aws secretsmanager create-secret \
    --name ${PREFIX}statuspage-db-credentials \
    --description "StatusPage database credentials" \
    --secret-string '{"username":"statuspage","password":"your-secure-db-password"}'

# Grafana admin password
aws secretsmanager create-secret \
    --name ${PREFIX}grafana-admin-password \
    --description "Grafana admin password" \
    --secret-string '{"password":"your-secure-grafana-password"}'
```

### 5. Update GitHub Workflows

Update `.github/workflows/` files with your ECR repository:

```yaml
env:
  ECR_REGISTRY: YOUR_ACCOUNT_ID.dkr.ecr.YOUR_REGION.amazonaws.com
  ECR_REPOSITORY: your-statuspage-repo
  AWS_REGION: your-aws-region
```

### 6. Deploy Infrastructure

```bash
cd terraform

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy infrastructure (takes ~15-20 minutes)
terraform apply
```

### 7. Configure kubectl

```bash
aws eks update-kubeconfig --name ${PREFIX}statuspage-cluster --region ${AWS_REGION}
```

### 8. Fix Security Groups (Important!)

```bash
# Run the automated security groups fix
bash fix-security-groups.sh
```

### 9. Verify Deployment

```bash
# Check all pods are running
kubectl get pods -A

# Check services
kubectl get svc -A

# Get endpoints
terraform output rds_endpoint
terraform output redis_endpoint
```

## CI/CD Pipeline

The project includes automated CI/CD pipelines using GitHub Actions:

### CI Pipeline (Pull Requests)
- **Trigger**: Pull requests to main branch affecting `status-page/` directory
- **Actions**: Code testing, linting, Docker build validation
- **File**: `.github/workflows/ci-test.yml`

### CD Pipeline (Production Deployment)
- **Trigger**: Push to main branch affecting `status-page/` directory
- **Actions**: 
  - Automatic version tagging (v1, v2, v3...)
  - Docker image build and push to ECR
  - Update `values.yaml` with new image tag
  - ArgoCD automatically syncs within 3 minutes
- **File**: `.github/workflows/cd-deploy.yml`

### Required GitHub Secrets

```bash
# Add these to your GitHub repository secrets
AWS_ACCESS_KEY_ID=your-aws-access-key
AWS_SECRET_ACCESS_KEY=your-aws-secret-key
```

## Application Deployment

### Automated Deployment (Recommended)

1. Make changes to the Django application in `status-page/` directory
2. Push changes to `main` branch
3. GitHub Actions automatically:
   - Builds new Docker image with incremented version tag
   - Pushes to ECR repository
   - Updates `values.yaml` with new image tag
   - ArgoCD syncs changes within 3 minutes

### Manual Deployment

```bash
# Get your ECR repository URL from terraform output
ECR_REPO=$(terraform output -raw ecr_repository_url)

# Build and push manually
cd status-page
docker build -t statuspage-app:v1 .
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REPO}
docker tag statuspage-app:v1 ${ECR_REPO}:v1
docker push ${ECR_REPO}:v1

# Update values.yaml with new tag
sed -i 's/tag: ".*"/tag: "v1"/' terraform/charts/statuspage-chart/values.yaml
```

## Access Information

### URLs

After deployment, get your access URLs:

```bash
# Application URL (your domain)
echo "https://$(terraform output -raw domain_name)"

# ArgoCD UI
kubectl get svc -n argocd argocd-server

# Grafana UI  
kubectl get svc -n monitoring monitoring-grafana
```

### Credentials

#### ArgoCD
```bash
# Username: admin
# Password:
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

#### Grafana
```bash
# Username: admin  
# Password: From AWS Secrets Manager
aws secretsmanager get-secret-value --secret-id ${PREFIX}grafana-admin-password --query SecretString --output text
```

#### StatusPage Admin
```bash
# Create admin user:
kubectl exec -it $(kubectl get pods -n default -l app.kubernetes.io/name=statuspage-chart -o jsonpath='{.items[0].metadata.name}') -n default -- python manage.py createsuperuser
```

## Monitoring

### Grafana Dashboards

The monitoring stack includes:
- **Kubernetes Cluster Metrics**: Node and pod resource usage
- **Application Metrics**: StatusPage performance metrics  
- **Infrastructure Metrics**: RDS, Redis, and network metrics
- **Alerting**: Prometheus alert rules for critical issues

### Key Metrics Monitored

- CPU and memory usage (pods and nodes)
- Database connections and performance
- Application response times
- SSL certificate expiration
- Pod health and availability
- Storage usage (PVC)

## Security

### SSL/TLS
- **ACM Certificate**: Automated SSL certificate from AWS Certificate Manager
- **HTTPS Enforcement**: All traffic redirected to HTTPS via NLB
- **Security Headers**: Django security headers enabled

### Network Security
- **Private Subnets**: Database and cache in private subnets only
- **Security Groups**: Least-privilege access between components
- **VPC**: Isolated network environment (10.0.0.0/16)
- **Secrets Management**: AWS Secrets Manager with IRSA

### Access Control
- **RBAC**: Kubernetes role-based access control
- **IRSA**: Service accounts use IAM roles for AWS access
- **Network Policies**: Controlled pod-to-pod communication

## Troubleshooting

### Common Issues

#### Pod Stuck in ContainerCreating
```bash
kubectl describe pod <pod-name> -n <namespace>
# Common causes: 
# - Secrets not accessible
# - Volume mounting issues
# - Resource constraints
```

#### Database/Redis Connection Issues
```bash
# Run the automated fix script
bash terraform/fix-security-groups.sh

# Test connectivity manually from a pod
kubectl exec -it <pod-name> -n default -- python -c "
import socket
s = socket.socket()
s.settimeout(5)
# Use your actual RDS endpoint
s.connect(('your-rds-endpoint', 5432))
print('Database connection OK')
s.close()
"
```

#### ArgoCD Sync Issues
```bash
# Check ArgoCD application status
kubectl get applications -n argocd

# Force sync
kubectl patch application statuspage -n argocd --type merge -p='{"operation":{"sync":{"syncStrategy":{"force":true}}}}'
```

### Log Analysis
```bash
# Application logs
kubectl logs -f deployment/statuspage-statuspage-chart -n default

# ArgoCD logs
kubectl logs -f deployment/argocd-server -n argocd

# Grafana logs
kubectl logs -f deployment/monitoring-grafana -n monitoring
```

## Maintenance

### Updating Application
1. Make changes to source code in `status-page/` directory
2. Commit and push to `main` branch
3. GitHub Actions automatically builds and deploys
4. ArgoCD syncs changes within 3 minutes

### Scaling
```bash
# Scale application replicas
kubectl scale deployment statuspage-statuspage-chart --replicas=5 -n default

# Scale cluster nodes (via Terraform)
# Update node_desired_size in variables.tf and run terraform apply
```

### SSL Certificate Management
Certificates are automatically renewed by ACM. No manual action required.

### Database Maintenance
```bash
# View RDS maintenance windows
aws rds describe-db-instances --db-instance-identifier ${PREFIX}statuspage-rds --query 'DBInstances[0].PreferredMaintenanceWindow'

# Default settings:
# Backup window: 03:00-04:00 UTC
# Maintenance window: Sunday 04:00-05:00 UTC
```

## Cost Optimization

### Current Resources & Estimated Costs
- **EKS Cluster**: ~$72/month (control plane)
- **EC2 Instances**: 3x t3.medium SPOT ~$45/month (vs ~$95 on-demand)
- **RDS db.m5.large**: ~$140/month
- **ElastiCache t3.micro**: ~$15/month
- **Network Load Balancer**: ~$16/month
- **Data Transfer**: Variable (~$10-30/month)
- **Total**: ~$290-320/month

### Cost Optimization Features
- **SPOT Instances**: 50-70% cost savings on worker nodes
- **Single NAT Gateway**: Cost optimization (vs HA setup)
- **Resource Limits**: Prevents resource over-allocation
- **HPA**: Automatic scaling based on demand

## Backup and Disaster Recovery

### Database Backups
- **RDS Automated Backups**: 7-day retention
- **Backup Window**: 03:00-04:00 UTC
- **Point-in-time Recovery**: Available
- **Encrypted**: At rest and in transit

### Configuration Backup
- **Infrastructure as Code**: All infrastructure defined in Terraform
- **GitOps**: Application configuration stored in Git
- **State Management**: Terraform state securely managed

## Support and Contributing

### Getting Help
- Check application logs: `kubectl logs -f <pod-name>`
- Review ArgoCD status: `kubectl get applications -n argocd`
- Monitor Grafana dashboards for system health
- Run connectivity fix: `bash terraform/fix-security-groups.sh`

### Development Workflow
1. Create feature branch from `main`
2. Make changes to `status-page/` directory
3. Create pull request (triggers CI pipeline)
4. After approval and merge to `main` (triggers CD pipeline)
5. ArgoCD automatically deploys to production

### Environment Variables Reference

Create a `.env.example` file for reference:

```bash
# AWS Configuration
AWS_REGION=us-east-1
AWS_ACCOUNT_ID=your-account-id

# Domain Configuration
DOMAIN_NAME=your-domain.com
SSL_EMAIL=your-email@example.com

# Project Configuration
PROJECT_NAME=statuspage
PREFIX=your-prefix-

# Database Configuration (from AWS Secrets Manager)
DATABASE_HOST=terraform-output-rds-endpoint
DATABASE_NAME=statuspage
DATABASE_PORT=5432

# Redis Configuration
REDIS_HOST=terraform-output-redis-endpoint
REDIS_PORT=6379

# Application Configuration
SITE_URL=https://your-domain.com
DEBUG=false
```

---

**Note**: This infrastructure is designed for production use. Make sure to replace all placeholder values with your actual configuration before deployment. The automated CI/CD pipeline ensures safe deployments with proper testing and version management.
