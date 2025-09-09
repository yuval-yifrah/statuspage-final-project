# IAM Role ל-Service Account
resource "aws_iam_role" "statuspage_irsa_role" {
  name = "statuspage-irsa-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
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

# Policy מצומצם ל-Secrets Manager
resource "aws_iam_role_policy" "statuspage_irsa_policy" {
  name = "statuspage-irsa-policy"
  role = aws_iam_role.statuspage_irsa_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ],
        Resource = "arn:aws:secretsmanager:us-east-1:992382545251:secret:ly-statuspage-db-credentials-*"
      }
    ]
  })
}

