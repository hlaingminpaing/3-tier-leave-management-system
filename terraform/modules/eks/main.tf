terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }
}

# EKS Cluster
resource "aws_eks_cluster" "main" {
  name            = "${var.project_name}-${var.environment}"
  role_arn        = var.cluster_role_arn
  version         = var.kubernetes_version
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    security_group_ids      = [var.cluster_security_group_id]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-eks-${var.environment}"
    }
  )

  depends_on = []
}

# Node Group
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-node-group-${var.environment}"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.subnet_ids
  version         = var.kubernetes_version

  scaling_config {
    desired_size = var.desired_capacity
    max_size     = var.max_capacity
    min_size     = var.min_capacity
  }

  instance_types = [var.instance_type]

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-node-group-${var.environment}"
    }
  )

  depends_on = [aws_eks_cluster.main]
}

# ====================================================
# EKS Managed Add-ons (matching eksctl --install-addons)
# ====================================================

# VPC CNI Add-on (AWS VPC CNI Plugin for Kubernetes)
# Handles pod networking and IP address management
resource "aws_eks_addon" "vpc_cni" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "vpc-cni"
  addon_version            = data.aws_eks_addon_version.vpc_cni.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  service_account_role_arn = aws_iam_role.vpc_cni.arn

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-vpc-cni-addon-${var.environment}"
    }
  )

  depends_on = [aws_eks_node_group.main]
}

# CoreDNS Add-on (DNS Resolution)
# Provides DNS name resolution for pods
resource "aws_eks_addon" "coredns" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "coredns"
  addon_version            = data.aws_eks_addon_version.coredns.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-coredns-addon-${var.environment}"
    }
  )

  depends_on = [aws_eks_node_group.main]
}

# Kube Proxy Add-on (Network Proxy)
# Handles Kubernetes network proxy functionality
resource "aws_eks_addon" "kube_proxy" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "kube-proxy"
  addon_version            = data.aws_eks_addon_version.kube_proxy.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-kube-proxy-addon-${var.environment}"
    }
  )

  depends_on = [aws_eks_node_group.main]
}

# Optional: EBS CSI Driver Add-on (for persistent volumes)
resource "aws_eks_addon" "ebs_csi_driver" {
  count                    = var.enable_ebs_csi_driver ? 1 : 0
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = data.aws_eks_addon_version.ebs_csi_driver[0].version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  service_account_role_arn = aws_iam_role.ebs_csi_driver[0].arn

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-ebs-csi-driver-addon-${var.environment}"
    }
  )

  depends_on = [aws_eks_node_group.main]
}

# Optional: EFS CSI Driver Add-on (for EFS persistent volumes)
resource "aws_eks_addon" "efs_csi_driver" {
  count                    = var.enable_efs_csi_driver ? 1 : 0
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "aws-efs-csi-driver"
  addon_version            = data.aws_eks_addon_version.efs_csi_driver[0].version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  service_account_role_arn = aws_iam_role.efs_csi_driver[0].arn

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-efs-csi-driver-addon-${var.environment}"
    }
  )

  depends_on = [aws_eks_node_group.main]
}

# Get latest add-on versions
data "aws_eks_addon_version" "vpc_cni" {
  addon_name             = "vpc-cni"
  kubernetes_version     = aws_eks_cluster.main.version
  most_recent            = true
}

data "aws_eks_addon_version" "coredns" {
  addon_name             = "coredns"
  kubernetes_version     = aws_eks_cluster.main.version
  most_recent            = true
}

data "aws_eks_addon_version" "kube_proxy" {
  addon_name             = "kube-proxy"
  kubernetes_version     = aws_eks_cluster.main.version
  most_recent            = true
}

data "aws_eks_addon_version" "ebs_csi_driver" {
  count                  = var.enable_ebs_csi_driver ? 1 : 0
  addon_name             = "aws-ebs-csi-driver"
  kubernetes_version     = aws_eks_cluster.main.version
  most_recent            = true
}

data "aws_eks_addon_version" "efs_csi_driver" {
  count                  = var.enable_efs_csi_driver ? 1 : 0
  addon_name             = "aws-efs-csi-driver"
  kubernetes_version     = aws_eks_cluster.main.version
  most_recent            = true
}

# ====================================================
# IAM Roles for EKS Add-ons
# ====================================================

# VPC CNI IAM Role
resource "aws_iam_role" "vpc_cni" {
  name_prefix = "${var.project_name}-vpc-cni-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-node"
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-vpc-cni-role-${var.environment}"
    }
  )
}

resource "aws_iam_role_policy_attachment" "vpc_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.vpc_cni.name
}

# EBS CSI Driver IAM Role
resource "aws_iam_role" "ebs_csi_driver" {
  count       = var.enable_ebs_csi_driver ? 1 : 0
  name_prefix = "${var.project_name}-ebs-csi-driver-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-ebs-csi-driver-role-${var.environment}"
    }
  )
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  count      = var.enable_ebs_csi_driver ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi_driver[0].name
}

# EFS CSI Driver IAM Role
resource "aws_iam_role" "efs_csi_driver" {
  count       = var.enable_efs_csi_driver ? 1 : 0
  name_prefix = "${var.project_name}-efs-csi-driver-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:efs-csi-controller-sa"
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-efs-csi-driver-role-${var.environment}"
    }
  )
}

resource "aws_iam_role_policy_attachment" "efs_csi_driver" {
  count      = var.enable_efs_csi_driver ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
  role       = aws_iam_role.efs_csi_driver[0].name
}

# OIDC Provider for IRSA
data "tls_certificate" "cluster" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-oidc-${var.environment}"
    }
  )
}

# Kubernetes Provider Configuration
provider "kubernetes" {
  host                   = aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token

  load_config_file = false
}

provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

data "aws_eks_cluster_auth" "cluster" {
  name = aws_eks_cluster.main.name
}

# AWS Load Balancer Controller
resource "aws_iam_role" "aws_load_balancer_controller" {
  name_prefix = "${var.project_name}-alb-controller-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-alb-controller-role-${var.environment}"
    }
  )
}

resource "aws_iam_role_policy" "aws_load_balancer_controller" {
  name   = "${var.project_name}-alb-controller-policy"
  role   = aws_iam_role.aws_load_balancer_controller.id
  policy = file("${path.module}/policies/alb_controller_policy.json")
}

# Autoscaler IAM Role
resource "aws_iam_role" "cluster_autoscaler" {
  count       = var.enable_cluster_autoscaler ? 1 : 0
  name_prefix = "${var.project_name}-autoscaler-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:cluster-autoscaler"
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-autoscaler-role-${var.environment}"
    }
  )
}

resource "aws_iam_role_policy" "cluster_autoscaler" {
  count  = var.enable_cluster_autoscaler ? 1 : 0
  name   = "${var.project_name}-autoscaler-policy"
  role   = aws_iam_role.cluster_autoscaler[0].id
  policy = file("${path.module}/policies/autoscaler_policy.json")
}

# ====================================================
# ArgoCD - EKS Native Capability (GitOps Platform)
# ====================================================

# Create argocd namespace
resource "kubernetes_namespace" "argocd" {
  count = var.enable_argocd ? 1 : 0

  metadata {
    name = var.argocd_namespace
    labels = {
      "app.kubernetes.io/name"       = "argocd"
      "app.kubernetes.io/managed-by" = "eks-capability"
    }
  }

  depends_on = [aws_eks_cluster.main, aws_eks_node_group.main]
}

# Add ArgoCD Helm repository
resource "helm_repository" "argocd" {
  count           = var.enable_argocd ? 1 : 0
  name            = "argo"
  url             = "https://argoproj.github.io/argo-helm"
  repository_cafile = ""
}

# Install ArgoCD as EKS Capability
resource "helm_release" "argocd" {
  count            = var.enable_argocd ? 1 : 0
  name             = "argocd"
  repository       = helm_repository.argocd[0].name
  chart            = "argo-cd"
  namespace        = kubernetes_namespace.argocd[0].metadata[0].name
  version          = var.argocd_version
  create_namespace = false
  wait             = true
  timeout          = 600

  values = [
    yamlencode({
      ## Global Configuration
      global = {
        logging = {
          level = "info"
        }
      }

      ## ArgoCD Server Configuration
      server = {
        service = {
          type = var.enable_argocd_ingress ? "ClusterIP" : "LoadBalancer"
        }

        admin = {
          enabled = true
        }

        ## Ingress Configuration for ArgoCD
        ingress = var.enable_argocd_ingress ? {
          enabled          = true
          ingressClassName = "alb"
          annotations = {
            "alb.ingress.kubernetes.io/scheme"        = "internet-facing"
            "alb.ingress.kubernetes.io/target-type"   = "ip"
            "alb.ingress.kubernetes.io/listen-ports"  = "[{\"HTTP\": 80}]"
            "alb.ingress.kubernetes.io/ssl-redirect"  = "443"
          }
          hosts = [var.argocd_ingress_hostname]
          paths = ["/"]
          pathType = "Prefix"
        } : {
          enabled = false
        }

        ## Extra arguments
        extraArgs = [
          "--insecure"  # ArgoCD behind ALB
        ]

        ## Resource limits
        resources = {
          requests = {
            cpu    = "250m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }

        metrics = {
          enabled = true
          service = {
            annotations = {
              "prometheus.io/scrape" = "true"
              "prometheus.io/port"   = "8083"
            }
          }
        }
      }

      ## Repo Server Configuration
      repoServer = {
        resources = {
          requests = {
            cpu    = "250m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }

        metrics = {
          enabled = true
          service = {
            annotations = {
              "prometheus.io/scrape" = "true"
              "prometheus.io/port"   = "8084"
            }
          }
        }

        service = {
          annotations = {
            "prometheus.io/scrape" = "true"
          }
        }
      }

      ## Application Controller Configuration
      controller = {
        resources = {
          requests = {
            cpu    = "250m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }

        metrics = {
          enabled = true
          service = {
            annotations = {
              "prometheus.io/scrape" = "true"
              "prometheus.io/port"   = "8085"
            }
          }
        }
      }

      ## Redis Configuration
      redis = {
        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
        }
      }

      ## Dex (OIDC provider)
      dex = {
        enabled = false
      }

      ## Notifications
      notifications = {
        enabled = false
      }

      ## Service Monitor for Prometheus (optional)
      serviceMonitor = {
        enabled = false
      }

      ## Enable Redis HA
      redis-ha = {
        enabled = false
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.argocd,
    aws_eks_node_group.main
  ]
}

# Create ArgoCD admin password secret
resource "kubernetes_secret" "argocd_admin_password" {
  count = var.enable_argocd ? 1 : 0

  metadata {
    name      = "argocd-admin-password"
    namespace = kubernetes_namespace.argocd[0].metadata[0].name
  }

  data = {
    "admin.password" = base64encode("${var.project_name}@${var.environment}")
  }

  type = "Opaque"

  depends_on = [helm_release.argocd]
}

# Create Repository Credentials Secret for ArgoCD (Optional)
resource "kubernetes_secret" "argocd_repo_creds" {
  count = var.enable_argocd && var.github_token != "" ? 1 : 0

  metadata {
    name      = "github-repository-credentials"
    namespace = kubernetes_namespace.argocd[0].metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    "url"      = var.github_repo_url
    "username" = var.github_username
    "password" = var.github_token
  }

  type = "Opaque"

  depends_on = [helm_release.argocd]
}
