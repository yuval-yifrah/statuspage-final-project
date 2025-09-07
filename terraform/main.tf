# main.tf - Fixed version
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.9.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Prefix      = var.prefix
    }
  }
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# Secrets Manager - DB credentials
data "aws_secretsmanager_secret" "db_credentials" {
  name = "ly-statuspage-db-credentials" # זה השם שבחרת ב-Secrets Manager
}

data "aws_secretsmanager_secret_version" "db_credentials_version" {
  secret_id = data.aws_secretsmanager_secret.db_credentials.id
}

locals {
  db_credentials = jsondecode(data.aws_secretsmanager_secret_version.db_credentials_version.secret_string)
}


# VPC
resource "aws_vpc" "ly_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.prefix}${var.project_name}-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "ly_igw" {
  vpc_id = aws_vpc.ly_vpc.id

  tags = {
    Name = "${var.prefix}${var.project_name}-igw"
  }
}

# Public Subnets (2 for HA)
resource "aws_subnet" "ly_public_subnet" {
  count = 2

  vpc_id                  = aws_vpc.ly_vpc.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                     = "${var.prefix}${var.project_name}-public-subnet-${count.index + 1}"
    "kubernetes.io/role/elb" = "1"
  }
}

# Private Subnets
resource "aws_subnet" "ly_private_subnet" {
  count = 2
  vpc_id            = aws_vpc.ly_vpc.id
  cidr_block        = "10.0.${count.index + 3}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
  Name = "${var.prefix}${var.project_name}-private-subnet-${count.index + 1}"
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "ly_nat_eip" {
  domain = "vpc"
  depends_on = [aws_internet_gateway.ly_igw]

  tags = {
    Name = "${var.prefix}${var.project_name}-nat-eip"
  }
}

# NAT Gateway (single for cost optimization)
resource "aws_nat_gateway" "ly_nat" {
  allocation_id = aws_eip.ly_nat_eip.id
  subnet_id     = aws_subnet.ly_public_subnet[0].id

  tags = {
    Name = "${var.prefix}${var.project_name}-nat"
  }

  depends_on = [aws_internet_gateway.ly_igw]
}

# Route Tables for Private Subnets
resource "aws_route_table" "ly_private_rt" {
  count = 2

  vpc_id = aws_vpc.ly_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ly_nat.id
  }

  tags = {
    Name = "${var.prefix}${var.project_name}-private-rt-${count.index + 1}"
  }
}

# Route Table Associations - Private
resource "aws_route_table_association" "ly_private_rta" {
  count = length(aws_subnet.ly_private_subnet)

  subnet_id      = aws_subnet.ly_private_subnet[count.index].id
  route_table_id = aws_route_table.ly_private_rt[count.index].id
}

# Route Table for Public Subnets
resource "aws_route_table" "ly_public_rt" {
  vpc_id = aws_vpc.ly_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ly_igw.id
  }

  tags = {
    Name = "${var.prefix}${var.project_name}-public-rt"
  }
}

# Route Table Associations
resource "aws_route_table_association" "ly_public_rta" {
  count = length(aws_subnet.ly_public_subnet)

  subnet_id      = aws_subnet.ly_public_subnet[count.index].id
  route_table_id = aws_route_table.ly_public_rt.id
}

# Security Groups
resource "aws_security_group" "eks_cluster_sg" {
  name_prefix = "${var.prefix}${var.project_name}-eks-cluster-"
  vpc_id      = aws_vpc.ly_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.prefix}${var.project_name}-eks-cluster-sg"
  }
}

resource "aws_security_group" "eks_nodes_sg" {
  name_prefix = "${var.prefix}${var.project_name}-eks-nodes-"
  vpc_id      = aws_vpc.ly_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  
  ingress {
    from_port       = 30080
    to_port         = 30080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
  }

  ingress {
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster_sg.id]
  }

  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.prefix}${var.project_name}-eks-nodes-sg"
  }
}

resource "aws_security_group" "ly_db_sg" {
  name_prefix = "${var.prefix}${var.project_name}-db-"
  vpc_id      = aws_vpc.ly_vpc.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.prefix}${var.project_name}-db-sg"
  }
}

# IAM Roles for EKS
resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.prefix}${var.project_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role" "eks_nodegroup_role" {
  name = "${var.prefix}${var.project_name}-eks-nodegroup-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodegroup_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodegroup_role.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodegroup_role.name
}

# EKS Cluster
resource "aws_eks_cluster" "ly_eks" {
  name     = "${var.prefix}${var.project_name}-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = aws_subnet.ly_public_subnet[*].id
    endpoint_private_access = false
    endpoint_public_access  = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
  ]

  tags = {
    Name = "${var.prefix}${var.project_name}-cluster"
  }
}

# EKS Node Group
resource "aws_eks_node_group" "ly_nodes" {
  cluster_name    = aws_eks_cluster.ly_eks.name
  node_group_name = "${var.prefix}${var.project_name}-nodes"
  node_role_arn   = aws_iam_role.eks_nodegroup_role.arn
  subnet_ids      = aws_subnet.ly_private_subnet[*].id
  capacity_type   = "SPOT"
  instance_types  = [var.node_instance_type]

  remote_access {
    ec2_ssh_key = var.key_pair_name  # yuvalyhome
    source_security_group_ids = [aws_security_group.eks_nodes_sg.id]
  }

  scaling_config {
    desired_size = var.node_desired_size
    max_size     = var.node_max_size
    min_size     = var.node_min_size
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy,
  ]

  tags = {
    Name = "${var.prefix}${var.project_name}-node-group"
  }
}

# DB Subnet Group (private subnets for security)
resource "aws_db_subnet_group" "ly_db_subnets" {
  name       = "${var.prefix}${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.ly_private_subnet[*].id

  tags = {
    Name = "${var.prefix}${var.project_name}-db-subnet-group"
  }
}

# RDS Instance
resource "aws_db_instance" "ly_rds" {
  identifier     = "${var.prefix}${var.project_name}-rds"
  engine         = "postgres"
  engine_version = "16.4"
  instance_class = "db.m5.large"
  
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = 100
  storage_type          = "gp2"
  storage_encrypted     = true
  
  db_name  = var.db_name
  username = local.db_credentials.username
  password = local.db_credentials.password

  vpc_security_group_ids = [aws_security_group.ly_db_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.ly_db_subnets.name
  
  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"
  
  skip_final_snapshot = true
  deletion_protection = false
  
  publicly_accessible = false

  tags = {
    Name = "${var.prefix}${var.project_name}-database"
  }
}

# ECR Repository
resource "aws_ecr_repository" "ly_ecr" {
  name         = "${var.prefix}${var.project_name}-repo"
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.prefix}${var.project_name}-ecr"
  }
}

# Jenkins EC2 Instance
resource "aws_instance" "jenkins_server" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.large"
  subnet_id     = aws_subnet.ly_public_subnet[0].id

  root_block_device {
    volume_size = 25
    volume_type = "gp3"
    encrypted   = true
  }
  
  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]
  
  key_name = var.key_pair_name
  
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y docker
              systemctl start docker
              systemctl enable docker
              usermod -a -G docker ec2-user
              
              # Install Jenkins
              wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
              rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
              yum install -y java-11-amazon-corretto jenkins
              systemctl start jenkins
              systemctl enable jenkins
              
              # Install kubectl
              curl -o kubectl https://amazon-eks.s3.us-west-2.amazonaws.com/1.28.1/2023-09-14/bin/linux/amd64/kubectl
              chmod +x ./kubectl
              mv ./kubectl /usr/local/bin
              
              # Install AWS CLI v2
              curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
              unzip awscliv2.zip
              ./aws/install
              EOF

  tags = {
    Name = "${var.prefix}${var.project_name}-jenkins"
  }
}

# Security Group for Jenkins
resource "aws_security_group" "jenkins_sg" {
  name_prefix = "${var.prefix}${var.project_name}-jenkins-"
  vpc_id      = aws_vpc.ly_vpc.id

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Restrict this to your IP in production
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Restrict this to your IP in production
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.prefix}${var.project_name}-jenkins-sg"
  }
}

# Data source for Amazon Linux AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# ElastiCache Subnet Group
resource "aws_elasticache_subnet_group" "ly_redis_subnet_group" {
  name       = "${var.prefix}${var.project_name}-redis-subnet-group"
  subnet_ids = aws_subnet.ly_private_subnet[*].id

  tags = {
    Name = "${var.prefix}${var.project_name}-redis-subnet-group"
  }
}

# Security Group for ElastiCache
resource "aws_security_group" "elasticache_sg" {
  name_prefix = "${var.prefix}${var.project_name}-redis-"
  vpc_id      = aws_vpc.ly_vpc.id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.prefix}${var.project_name}-redis-sg"
  }
}

# ElastiCache Redis Cluster
resource "aws_elasticache_replication_group" "ly_redis" {
  replication_group_id       = "${var.prefix}${var.project_name}-redis"
  description                = "Redis cluster for StatusPage"

  node_type                  = "cache.t3.micro"
  port                       = 6379
  parameter_group_name       = "default.redis7"

  num_cache_clusters         = 1

  subnet_group_name          = aws_elasticache_subnet_group.ly_redis_subnet_group.name
  security_group_ids         = [aws_security_group.elasticache_sg.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = false  

  tags = {
    Name = "${var.prefix}${var.project_name}-redis"
  }
}

# ALB Security Group
resource "aws_security_group" "alb_sg" {
  name_prefix = "${var.prefix}${var.project_name}-alb-"
  vpc_id      = aws_vpc.ly_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.prefix}${var.project_name}-alb-sg"
  }
}

# Application Load Balancer
resource "aws_lb" "ly_alb" {
  name               = "${var.prefix}${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.ly_public_subnet[*].id

  enable_deletion_protection = false

  tags = {
    Name = "${var.prefix}${var.project_name}-alb"
  }
}

# Target Group
resource "aws_lb_target_group" "ly_tg" {
  name     = "${var.prefix}${var.project_name}-tg"
  port     = 30080
  protocol = "HTTP"
  vpc_id   = aws_vpc.ly_vpc.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${var.prefix}${var.project_name}-tg"
  }
}

# ALB Listener
resource "aws_lb_listener" "ly_listener" {
  load_balancer_arn = aws_lb.ly_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ly_tg.arn
  }
}
