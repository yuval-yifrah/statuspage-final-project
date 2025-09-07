provider "kubernetes" {
  host                   = aws_eks_cluster.ly_eks.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.ly_eks.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

