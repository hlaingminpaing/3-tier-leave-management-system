# Data source for AWS account ID
data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"

  project_name           = var.project_name
  environment            = var.environment
  vpc_cidr               = var.vpc_cidr
  availability_zones     = var.availability_zones
  tags                   = var.tags
}

# Security Module (Security Groups & IAM Roles)
module "security" {
  source = "./modules/security"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  tags         = var.tags
}

# EKS Module with ArgoCD as built-in capability
module "eks" {
  source = "./modules/eks"

  project_name               = var.project_name
  environment                = var.environment
  kubernetes_version         = var.kubernetes_version
  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = concat(module.vpc.public_subnet_ids, module.vpc.private_subnet_ids)
  cluster_security_group_id  = module.security.eks_cluster_sg_id
  node_security_group_id     = module.security.eks_nodes_sg_id
  cluster_role_arn           = module.security.eks_cluster_role_arn
  node_role_arn              = module.security.eks_node_role_arn
  node_instance_profile_arn  = module.security.eks_node_instance_profile_arn
  desired_capacity           = var.desired_capacity
  min_capacity               = var.min_capacity
  max_capacity               = var.max_capacity
  instance_type              = var.instance_type
  enable_cluster_autoscaler  = true
  enable_metrics_server      = true
  enable_ebs_csi_driver      = var.enable_ebs_csi_driver
  enable_efs_csi_driver      = var.enable_efs_csi_driver
  
  # ArgoCD as EKS Capability
  enable_argocd               = var.enable_argocd
  argocd_namespace            = var.argocd_namespace
  argocd_version              = var.argocd_version
  enable_argocd_ingress       = var.enable_argocd_ingress
  argocd_ingress_hostname     = var.argocd_ingress_hostname
  github_token                = var.github_token
  github_username             = var.github_username
  github_repo_url             = var.github_repo_url
  
  tags                       = var.tags
}

# ============================================
# Monitoring Stack Module
# (Prometheus, Grafana, Loki, Tempo)
# ============================================

module "monitoring" {
  count = var.enable_monitoring_stack ? 1 : 0

  source = "./modules/monitoring"

  cluster_id             = module.eks.cluster_id
  cluster_endpoint       = module.eks.cluster_endpoint
  cluster_ca_certificate = module.eks.cluster_ca_certificate
  oidc_provider_arn      = module.eks.oidc_provider_arn
  oidc_provider_url      = module.eks.oidc_provider_url
  project_name           = var.project_name
  environment            = var.environment
  prometheus_storage_size = var.prometheus_storage_size
  grafana_admin_password = var.grafana_admin_password
  enable_alerting        = var.enable_alerting
  alert_email            = var.alert_email
  tags                   = var.tags

  depends_on = [module.eks]
}
