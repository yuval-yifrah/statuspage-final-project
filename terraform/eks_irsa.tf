# מביא את פרטי הקלאסטר
data "aws_eks_cluster" "ly_eks" {
  name = aws_eks_cluster.ly_eks.name
}

data "aws_eks_cluster_auth" "ly_eks" {
  name = aws_eks_cluster.ly_eks.name
}

# מביא את התעודה של ה-OIDC issuer
data "tls_certificate" "eks_oidc" {
  url = data.aws_eks_cluster.ly_eks.identity[0].oidc[0].issuer
}

# יוצר OIDC provider ל-IRSA
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
  url             = data.aws_eks_cluster.ly_eks.identity[0].oidc[0].issuer
}

