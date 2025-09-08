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

provider "kubectl" {
  host                   = aws_eks_cluster.ly_eks.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.ly_eks.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
}

# התקנת CSI Driver לניהול Secrets
resource "helm_release" "csi_driver" {
  name       = "csi-secrets-store"
  repository = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
  chart      = "secrets-store-csi-driver"
  namespace  = "kube-system"

  set = [{
    name  = "syncSecret.enabled"
    value = "true"
  }]

  depends_on = [aws_eks_node_group.ly_nodes]
}

# התקנת AWS Provider ל-CSI Driver
resource "helm_release" "csi_driver_provider_aws" {
  name       = "csi-secrets-store-provider-aws"
  repository = "https://aws.github.io/secrets-store-csi-driver-provider-aws"
  chart      = "secrets-store-csi-driver-provider-aws"
  namespace  = "kube-system"
  version    = "0.3.8"

  depends_on = [helm_release.csi_driver]
}

# התקנת NGINX Ingress Controller
resource "helm_release" "nginx_ingress" {
  name       = "nginx-ingress"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = "ingress-nginx"
  create_namespace = true

  set = [
    {
      name  = "controller.service.type"
      value = "LoadBalancer"
    },
    {
      name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
      value = "nlb"
    },
    {
      name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-scheme"
      value = "internet-facing"
    }
  ]

  depends_on = [aws_eks_node_group.ly_nodes]
}

# התקנת cert-manager לניהול SSL certificates
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = "cert-manager"
  create_namespace = true
  version    = "v1.13.0"

  set = [{
    name  = "installCRDs"
    value = "true"
  }]

  depends_on = [helm_release.nginx_ingress]
}

# התקנת ArgoCD
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = "argocd"
  create_namespace = true

  values = [
    yamlencode({
      server = {
        service = {
          type = "LoadBalancer"
          annotations = {
            "service.beta.kubernetes.io/aws-load-balancer-type"   = "nlb"
            "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
          }
        }
        extraArgs = [
          "--insecure" # For HTTP access, remove in production with proper SSL
        ]
      }
      configs = {
        params = {
          "server.insecure" = true
        }
      }
    })
  ]

  depends_on = [helm_release.cert_manager]
}

# ClusterIssuer for Let's Encrypt (using kubectl provider)
resource "kubectl_manifest" "letsencrypt_issuer" {
  yaml_body = <<YAML
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: yuviyi1408@gmail.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
YAML

  depends_on = [helm_release.cert_manager]
}

# SecretProviderClass for database credentials
#resource "kubectl_manifest" "db_secret_provider_class" {
#  yaml_body = <<YAML
#apiVersion: secrets-store.csi.x-k8s.io/v1
#kind: SecretProviderClass
#metadata:
#  name: db-secrets
#  namespace: default
#spec:
#  provider: aws
#  parameters:
#    objects: |
#      - objectName: "ly-statuspage-db-credentials"
#        objectType: "secretsmanager"
#        jmesPath:
#          - path: "username"
#            objectAlias: "username"
#          - path: "password"
#            objectAlias: "password"
#  secretObjects:
#    - secretName: db-secrets
#      type: Opaque
#      data:
#        - objectName: "username"
#          key: "username"
#        - objectName: "password"
#          key: "password"
#YAML

# depends_on = [helm_release.csi_driver_provider_aws]
#}

# התקנת ה-Helm Chart של StatusPage
resource "helm_release" "statuspage" {
  name      = "statuspage"
  chart     = "${path.module}/charts/statuspage-chart"
  namespace = "default"

  depends_on = [
    helm_release.nginx_ingress,
  ]

  values = [
    file("${path.module}/charts/statuspage-chart/values.yaml"),
    <<-EOF
    serviceAccount:
      create: false
      name: statuspage-sa

    env:
      - name: SECRET_MANAGER_NAME
        value: "ly-statuspage-db-credentials"
      - name: AWS_REGION
        value: "us-east-1"
      - name: SECRET_KEY
        valueFrom:
          secretKeyRef:
            name: django-secret
            key: secret-key
    EOF
  ]
}



# ArgoCD Application for StatusPage (optional - for GitOps workflow)
resource "kubectl_manifest" "statuspage_argocd_application" {
  yaml_body = <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: statuspage
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/yuval-yifrah/statuspage-final-project.git
    targetRevision: HEAD
    path: charts/statuspage-chart
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
YAML

  depends_on = [helm_release.argocd]
  
  # This is optional - comment out if you don't want ArgoCD to manage the app initially
  count = 0
}

provider "kubernetes" {
  host                   = aws_eks_cluster.ly_eks.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.ly_eks.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

