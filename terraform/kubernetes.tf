resource "kubernetes_manifest" "aws_secrets_provider" {
  manifest = yamldecode(file("${path.module}/manifests/aws-provider-installer.yaml"))
}


