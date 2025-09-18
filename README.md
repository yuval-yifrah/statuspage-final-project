# StatusPage Infrastructure on AWS EKS

## Overview

This project deploys a production-ready StatusPage application on AWS using Infrastructure as Code (Terraform) and GitOps (ArgoCD). The infrastructure includes a scalable Kubernetes cluster, managed databases, SSL certificates, and comprehensive monitoring with CI/CD automation.

## Architecture

### High-Level Architecture

```
Internet
    ↓
Route 53 DNS (ly-statuspage.click)
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
│  |  │  Port 80                   │   (Service: port 80)    │
│  |  └────────────────────────────┼───────────────────────- │
│                                  │                         │
│  ┌─── Private Subnets (2 AZs) -──┴───┐                     │
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
- **ECR**: Container registry (`992382545251.dkr.ecr.us-east-1.amazonaws.com/ly-statuspage-repo`)
  - Image scanning enabled for vulnerability detection
  - Lifecycle policies for automatic image cleanup
  - Cross-region replication support
- **RDS PostgreSQL**: Primary database (db.m5.large, encrypted, v16.8)
  - Endpoint: `ly-statuspage-rds.cx248m4we6k7.us-east-1.rds.amazonaws.com`
  - Multi-AZ deployment for high availability
  - Automated backups with 7-day retention (03:00-04:00 UTC backup window)
  - Private subnets only - no public access
- **ElastiCache Redis**: Caching and session storage (cache.t3.micro)
  - Endpoint: `ly-statuspage-redis.7fftml.ng.0001.use1.cache.amazonaws.com`
  - Encryption at rest enabled
  - Single node for cost optimization
- **ACM**: SSL certificates for HTTPS
  - Certificate ARN: `arn:aws:acm:us-east-1:992382545251:certificate/3ad26a05-3441-4914-9589-5e638012949c`
  - Automatic renewal via Route 53 DNS validation
  - Wildcard support for subdomains
- **Route 53**: DNS management for ly-statuspage.click
  - Hosted zone with DNS validation records
  - A records pointing to NLB endpoints
  - Health checks for failover scenarios
- **AWS Secrets Manager**: Secure storage for sensitive data
  - Database credentials: `ly-statuspage-db-credentials`
  - Grafana admin password: `ly-grafana-admin-password`
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

## Repository Structure

```
.
├── terraform/
│   ├── main.tf                 # Core AWS infrastructure
│   ├── helm.tf                 # Kubernetes applications deployment
│   ├── iam.tf                  # IRSA and IAM configurations
│   ├── variables.tf            # Configuration variables
│   ├── outputs.tf              # Infrastructure outputs
│   ├── fix-security-groups.sh  # Auto-fix connectivity script
│   └── charts/
│       └── statuspage-chart/
│           ├── Chart.yaml
│           ├── values.yaml     # Application configuration
│           └── templates/
├── status-page/                # Django application source code
│   ├── Dockerfile              # Multi-stage production build
│   └── statuspage/
├── .github/
│   └── workflows/
│       ├── ci-test.yml         # CI pipeline for PRs
│       └── cd-deploy.yml       # CD pipeline for main branch
└── README.md
```

## Terraform Infrastructure Deployment

### What Terraform Creates

Terraform automatically provisions the following AWS resources in the correct order:

#### **Phase 1: Core Networking**
```bash
terraform apply -target=aws_vpc.ly_vpc -target=aws_internet_gateway.ly_igw
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
terraform apply -target=aws_db_instance.ly_rds -target=aws_elasticache_replication_group.ly_redis
```
- **RDS PostgreSQL** database (db.m5.large) in private subnets
- **DB Subnet Group** spanning both private subnets
- **ElastiCache Redis** cluster (cache.t3.micro) in private subnets
- **ElastiCache Subnet Group** for Redis placement
- **ECR Repository** with image scanning enabled

#### **Phase 4: EKS Cluster**
```bash
terraform apply -target=aws_eks_cluster.ly_eks -target=aws_eks_node_group.ly_nodes
```
- **EKS Cluster** (v1.28) with public and private subnet access
- **EKS Node Group** with 3 t3.medium SPOT instances in private subnets
- **SSH access** configuration for worker nodes

#### **Phase 5: SSL & DNS**
```bash
terraform apply -target=aws_acm_certificate.statuspage_cert -target=aws_route53_record.*
```
- **ACM SSL Certificate** for ly-statuspage.click domain
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
terraform apply -target=aws_vpc.ly_vpc -target=aws_internet_gateway.ly_igw
terraform apply -target=aws_eks_cluster.ly_eks
terraform apply -target=helm_release.monitoring

# 5. Get important outputs
terraform output rds_endpoint
terraform output redis_endpoint
terraform output eks_cluster_endpoint

# 6. Update kubectl configuration
aws eks update-kubeconfig --name ly-statuspage-cluster --region us-east-1

# 7. Verify deployment
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

|          File            |                     Purpose                     |
|--------------------------|-------------------------------------------------|
| `main.tf`                | Core AWS infrastructure (VPC, EKS, RDS, Redis)  |
| `helm.tf`                | Kubernetes applications deployment              |
| `iam.tf`                 | IAM roles, policies, and IRSA configuration     |
| `variables.tf`           | Input variables and defaults                    |
| `outputs.tf`             | Important resource outputs                      |
| `fix-security-groups.sh` | Post-deployment connectivity fix                |

### Deployment Time

- **Total deployment time**: ~15-20 minutes
- **EKS Cluster creation**: ~10-12 minutes
- **RDS creation**: ~5-7 minutes
- **Helm applications**: ~3-5 minutes

## Installation

### 1. Clone Repository

```bash
git clone https://github.com/yuval-yifrah/statuspage-final-project.git
cd statuspage-final-project
```

### 2. Configure AWS Credentials

```bash
aws configure
# Enter your AWS Access Key ID, Secret Access Key, and region (us-east-1)
```

### 3. Set Up Secrets in AWS Secrets Manager

Create the following secrets in AWS Secrets Manager:

```bash
# Database credentials
aws secretsmanager create-secret \
    --name ly-statuspage-db-credentials \
    --description "StatusPage database credentials" \
    --secret-string '{"username":"statuspage","password":"your-secure-db-password"}'

# Grafana admin password
aws secretsmanager create-secret \
    --name ly-grafana-admin-password \
    --description "Grafana admin password" \
    --secret-string '{"password":"your-secure-grafana-password"}'
```

### 4. Deploy Infrastructure

```bash
cd terraform

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy infrastructure (takes ~15-20 minutes)
terraform apply
```

### 5. Configure kubectl

```bash
aws eks update-kubeconfig --name ly-statuspage-cluster --region us-east-1
```

### 6. Verify Deployment

```bash
# Check all pods are running
kubectl get pods -A

# Check services
kubectl get svc -A

# Check ArgoCD application status
kubectl get applications -n argocd
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
# Build and push manually
cd status-page
docker build -t ly-statuspage-repo:v12 .
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 992382545251.dkr.ecr.us-east-1.amazonaws.com
docker tag ly-statuspage-repo:v12 992382545251.dkr.ecr.us-east-1.amazonaws.com/ly-statuspage-repo:v12
docker push 992382545251.dkr.ecr.us-east-1.amazonaws.com/ly-statuspage-repo:v12

# Update values.yaml
sed -i 's/tag: "v11"/tag: "v12"/' terraform/charts/statuspage-chart/values.yaml

# ArgoCD will automatically deploy the changes
```

## Access Information

### URLs

- **StatusPage Application**: https://ly-statuspage.click
- **StatusPage Admin**: https://ly-statuspage.click/dashboard/login/
- **ArgoCD**: Get IP from `kubectl get svc -n argocd argocd-server`
- **Grafana**: Get IP from `kubectl get svc -n monitoring monitoring-grafana`

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
# Password: From AWS Secrets Manager (ly-grafana-admin-password)
aws secretsmanager get-secret-value --secret-id ly-grafana-admin-password --query SecretString --output text
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

# Test connectivity manually
kubectl exec -it <pod-name> -n default -- python -c "
import socket
s = socket.socket()
s.settimeout(5)
s.connect(('ly-statuspage-rds.cx248m4we6k7.us-east-1.rds.amazonaws.com', 5432))
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
aws rds describe-db-instances --db-instance-identifier ly-statuspage-rds --query 'DBInstances[0].PreferredMaintenanceWindow'

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

---

**Note**: This infrastructure is designed for production use. The automated CI/CD pipeline ensures safe deployments with proper testing and version management.
