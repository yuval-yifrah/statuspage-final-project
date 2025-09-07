data "aws_eks_cluster_auth" "cluster" {
  name = aws_eks_cluster.ly_eks.name
}

provider "helm" {
  kubernetes = {
    host                   = aws_eks_cluster.ly_eks.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.ly_eks.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

# התקנת CSI Driver
resource "helm_release" "csi_driver" {
  name       = "csi-secrets-store"
  repository = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
  chart      = "secrets-store-csi-driver"
  namespace  = "kube-system"

  set_sensitive = []
  set = [
    {
      name  = "syncSecret.enabled"
      value = "true"
    }
  ]
}


# התקנת AWS Provider ל-CSI (מתוך Helm repo הרשמי של AWS)
resource "helm_release" "csi_driver_provider_aws" {
  name       = "csi-secrets-store-provider-aws"
  repository = "https://aws.github.io/secrets-store-csi-driver-provider-aws"
  chart      = "secrets-store-csi-driver-provider-aws"
  namespace  = "kube-system"
  version    = "0.3.8" # אפשר גם להוריד את השורה הזו כדי לקחת תמיד הכי עדכני

  depends_on = [helm_release.csi_driver]
}

# התקנת ה-Helm Chart שלך (statuspage)
resource "helm_release" "statuspage" {
  name       = "statuspage"
  chart      = "${path.module}/charts/statuspage-chart"
  namespace  = "default"

  depends_on = [
    helm_release.csi_driver_provider_aws
  ]

  values = [
    file("${path.module}/charts/statuspage-chart/values.yaml")
  ]
}

