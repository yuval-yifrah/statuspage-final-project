# outputs.tf - Fixed version
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.ly_vpc.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.ly_public_subnet[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets" 
  value       = aws_subnet.ly_private_subnet[*].id
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.ly_eks.name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = aws_eks_cluster.ly_eks.endpoint
}

output "eks_cluster_certificate_authority_data" {
  description = "EKS cluster CA data"
  value       = aws_eks_cluster.ly_eks.certificate_authority[0].data
}

output "rds_endpoint" {
  description = "RDS database endpoint"
  value       = aws_db_instance.ly_rds.endpoint
  sensitive   = true
}

output "rds_port" {
  description = "RDS database port"
  value       = aws_db_instance.ly_rds.port
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.ly_ecr.repository_url
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_eks_cluster.ly_eks.vpc_config[0].cluster_security_group_id
}

output "node_group_arn" {
  description = "EKS node group ARN"
  value       = aws_eks_node_group.ly_nodes.arn
}

output "jenkins_instance_id" {
  description = "Jenkins EC2 instance ID"
  value       = aws_instance.jenkins_server.id
}

output "jenkins_public_ip" {
  description = "Jenkins server public IP"
  value       = aws_instance.jenkins_server.public_ip
}

output "jenkins_url" {
  description = "Jenkins access URL"
  value       = "http://${aws_instance.jenkins_server.public_ip}:8080"
}

output "nat_gateway_ip" {
  description = "NAT Gateway Elastic IP"
  value       = aws_eip.ly_nat_eip.public_ip
}

output "redis_endpoint" {
  description = "ElastiCache Redis endpoint"
  value       = aws_elasticache_replication_group.ly_redis.primary_endpoint_address
  sensitive   = true
}

output "nginx_ingress_ip" {
  description = "NGINX Ingress Controller LoadBalancer IP"
  value       = "Get from: kubectl get svc -n ingress-nginx"
}

output "argocd_server_ip" {
  description = "ArgoCD Server LoadBalancer IP"
  value       = "Get from: kubectl get svc -n argocd"
}

output "db_host" {
  description = "RDS endpoint"
  value       = aws_db_instance.ly_rds.address
}

output "db_port" {
  description = "RDS port"
  value       = aws_db_instance.ly_rds.port
}

output "db_name" {
  description = "RDS database name"
  value       = aws_db_instance.ly_rds.db_name
}

