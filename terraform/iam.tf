# IAM Role ל-Service Account
resource "aws_iam_role" "statuspage_irsa_role" {
  name = "statuspage-irsa-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.id
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:default:statuspage-sa"
          }
        }
      }
    ]
  })
}

# הרשאות ל-Secrets Manager
resource "aws_iam_role_policy_attachment" "statuspage_secrets" {
  role       = aws_iam_role.statuspage_irsa_role.name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

