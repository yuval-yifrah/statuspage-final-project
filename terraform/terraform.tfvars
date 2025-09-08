# --- AWS Region ---
aws_region = "us-east-1"

# --- Project Info ---
project_name = "statuspage"
prefix       = "ly-"
environment  = "prod"

# --- VPC ---
vpc_cidr = "10.0.0.0/16"

# --- EKS Cluster ---
cluster_version = "1.28"

# --- Node Group ---
node_desired_size   = 3
node_max_size       = 5
node_min_size       = 2
node_instance_type  = "t3.small"

# --- Database Credentials ---
db_name              = "statuspage"
db_instance_class    = "db.m5.large"
db_allocated_storage = 20


