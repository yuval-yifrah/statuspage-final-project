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

provider "kubernetes" {
  host                   = aws_eks_cluster.ly_eks.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.ly_eks.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

# Get node group IAM role for secrets manager permissions
data "aws_iam_role" "nodegroup_role" {
  name = "ly-statuspage-eks-nodegroup-role"
}

resource "aws_iam_role_policy_attachment" "node_secrets_manager_policy" {
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
  role       = data.aws_iam_role.nodegroup_role.name
}

# IRSA for Grafana: service account in EKS can assume this role
resource "aws_iam_role" "grafana_irsa" {
  name = "${var.prefix}${var.project_name}-grafana-irsa-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [ {
      Effect = "Allow",
      Action = "sts:AssumeRoleWithWebIdentity",
      Principal = { Federated = aws_iam_openid_connect_provider.eks.arn },
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com",
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:monitoring:monitoring-grafana"
        }
      }
    }]
  })
}

data "aws_secretsmanager_secret" "grafana_admin_password" {
  name = "ly-grafana-admin-password"
}

resource "aws_iam_role_policy" "grafana_sm_read" {
  role = aws_iam_role.grafana_irsa.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [ {
      Effect   = "Allow",
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"],
      Resource = data.aws_secretsmanager_secret.grafana_admin_password.arn
    }]
  })
}

# התקנת CSI Driver לניהול Secrets
resource "helm_release" "csi_driver" {
  name       = "csi-secrets-store"
  repository = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
  chart      = "secrets-store-csi-driver"
  namespace  = "kube-system"

  set = [ {
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

# יצירת SecretProviderClass לחיבור AWS Secrets Manager
resource "kubectl_manifest" "db_secrets_provider" {
  yaml_body = <<YAML
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: db-secrets
  namespace: default
spec:
  provider: aws
  parameters:
    objects: |
      - objectName: "ly-statuspage-db-credentials"
        objectType: "secretsmanager"
        jmesPath:
          - path: "username"
            objectAlias: "username"
          - path: "password"
            objectAlias: "password"
  secretObjects:
  - secretName: db-secrets
    type: Opaque
    data:
    - objectName: username
      key: username
    - objectName: password
      key: password
YAML

  depends_on = [helm_release.csi_driver_provider_aws]
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
      name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-name"
      value = "${var.prefix}nginx-nlb"
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

  set = [ {
    name  = "installCRDs"
    value = "true"
  }]

  depends_on = [helm_release.nginx_ingress]
}

# התקנת ArgoCD
resource "helm_release" "argocd" {
  count      = 0
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
            "service.beta.kubernetes.io/aws-load-balancer-name"   = "${var.prefix}argocd-nlb"
            "service.beta.kubernetes.io/aws-load-balancer-type"   = "nlb"
            "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
          }
        }
        extraArgs = [
          "--insecure"
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

# ClusterIssuer for Let's Encrypt
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

# התקנת StatusPage
resource "helm_release" "statuspage" {
  name       = "statuspage"
  chart      = "${path.module}/charts/statuspage-chart"
  namespace  = "default"
  create_namespace = true

  depends_on = [
    aws_eks_node_group.ly_nodes,
    kubectl_manifest.db_secrets_provider,
  ]

  values = [
    file("${path.module}/charts/statuspage-chart/values.yaml")
  ]
}

# התקנת AWS EBS CSI Driver (נדרש ל-Prometheus/Alertmanager PVC)
resource "helm_release" "aws_ebs_csi_driver" {
  name       = "${var.prefix}-ebs-csi-driver"
  repository = "https://kubernetes-sigs.github.io/aws-ebs-csi-driver"
  chart      = "aws-ebs-csi-driver"
  namespace  = "kube-system"

  depends_on = [aws_eks_node_group.ly_nodes]
}

# יצירת SecretProviderClass לGrafana
resource "kubectl_manifest" "grafana_secrets_provider" {
  yaml_body = file("${path.module}/charts/statuspage-chart/templates/SecretProviderClass-grafana.yaml")
  depends_on = [helm_release.csi_driver_provider_aws]
}

resource "helm_release" "monitoring" {
  name             = "monitoring"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true
  timeout          = 600
  version          = "77.6.1"

  values = [
    yamlencode({
      prometheus = {
        prometheusSpec = {
          resources = {
            requests = { memory = "128Mi", cpu = "50m" }
            limits   = { memory = "256Mi", cpu = "125m" }
          }
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "gp2"
                accessModes      = ["ReadWriteOnce"]
                resources        = { requests = { storage = "10Gi" } }
              }
            }
          }
        }
      }

      alertmanager = {
        alertmanagerSpec = {
          resources = {
            requests = { memory = "64Mi", cpu = "25m" }
            limits   = { memory = "128Mi", cpu = "50m" }
          }
        }
      }

      grafana = {
        admin = {
          existingSecret = "monitoring-grafana"
          passwordKey    = "password"
          userKey        = "admin"
        }

        serviceAccount = {
          create      = true
          name        = "monitoring-grafana"
          annotations = {
            "eks.amazonaws.com/role-arn" = aws_iam_role.grafana_irsa.arn
          }
        }

        extraVolumes = [{
          name = "secrets-store"
          csi  = {
            driver           = "secrets-store.csi.k8s.io"
            readOnly         = true
            volumeAttributes = { secretProviderClass = "grafana-secrets" }
          }
        }]
        extraVolumeMounts = [ {
          name      = "secrets-store"
          mountPath = "/mnt/secrets-store"
          readOnly  = true
        }]

        resources = {
          requests = { memory = "64Mi", cpu = "25m" }
          limits   = { memory = "128Mi", cpu = "50m" }
        }

        service = {
          type = "LoadBalancer"
          annotations = {
            "service.beta.kubernetes.io/aws-load-balancer-name"   = "${var.prefix}-grafana-nlb"
            "service.beta.kubernetes.io/aws-load-balancer-type"   = "nlb"
            "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
          }
        }
      }

      kubeStateMetrics = {
        enabled   = true
        resources = {
          requests = { memory = "32Mi", cpu = "12m" }
          limits   = { memory = "64Mi", cpu = "25m" }
        }
      }

      nodeExporter = {
        enabled   = true
        resources = {
          requests = { memory = "16Mi", cpu = "12m" }
          limits   = { memory = "32Mi", cpu = "25m" }
        }
      }
    })
  ]

  depends_on = [
    aws_eks_node_group.ly_nodes,
    helm_release.aws_ebs_csi_driver,
    kubectl_manifest.grafana_secrets_provider,
    aws_iam_role_policy.grafana_sm_read
  ]
}

# ArgoCD Application (אופציונלי)
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
    path: terraform/charts/statuspage-chart
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

  count = 0
}

