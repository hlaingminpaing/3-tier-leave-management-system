output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = module.vpc.vpc_cidr
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

output "eks_cluster_id" {
  description = "EKS Cluster ID"
  value       = module.eks.cluster_id
}

output "eks_cluster_arn" {
  description = "EKS Cluster ARN"
  value       = module.eks.cluster_arn
}

output "eks_cluster_endpoint" {
  description = "EKS Cluster Endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_version" {
  description = "EKS Cluster Version"
  value       = module.eks.cluster_version
}

output "eks_cluster_security_group_id" {
  description = "EKS Cluster Security Group ID"
  value       = module.eks.cluster_security_group_id
}

output "eks_node_group_id" {
  description = "EKS Node Group ID"
  value       = module.eks.node_group_id
}

output "oidc_provider_arn" {
  description = "OIDC Provider ARN (for IRSA)"
  value       = module.eks.oidc_provider_arn
}

output "load_balancer_controller_role_arn" {
  description = "AWS Load Balancer Controller IAM Role ARN"
  value       = module.eks.load_balancer_controller_role_arn
}

# ============================================
# EKS Managed Add-ons Outputs
# ============================================

output "eks_addons_installed" {
  description = "EKS Managed Add-ons Information"
  value = {
    vpc_cni          = module.eks.vpc_cni_addon_version
    coredns          = module.eks.coredns_addon_version
    kube_proxy       = module.eks.kube_proxy_addon_version
    ebs_csi_driver   = module.eks.ebs_csi_driver_addon_version
    efs_csi_driver   = module.eks.efs_csi_driver_addon_version
  }
}

# ============================================
# Monitoring Stack Outputs
# ============================================

output "monitoring_enabled" {
  description = "Whether monitoring stack is enabled"
  value       = var.enable_monitoring_stack
}

output "monitoring_namespace" {
  description = "Kubernetes namespace for monitoring stack"
  value       = try(module.monitoring[0].monitoring_namespace, null)
}

output "monitoring_stack_info" {
  description = "Complete monitoring stack information and access endpoints"
  value       = try(module.monitoring[0].monitoring_stack_info, null)
  sensitive   = true
}

output "grafana_info" {
  description = "Grafana access information"
  value = var.enable_monitoring_stack ? {
    username  = "admin"
    password  = "Change this in Grafana UI!"
    port_forward = "kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
    access_url   = "http://localhost:3000"
  } : null
}

output "tempo_otlp_endpoint" {
  description = "Tempo OTLP endpoint for backend OpenTelemetry instrumentation"
  value       = try(module.monitoring[0].tempo_otlp_endpoint, null)
}

# ============================================
# ArgoCD - EKS Capability Outputs
# ============================================

output "argocd_enabled" {
  description = "Whether ArgoCD is enabled as EKS capability"
  value       = module.eks.argocd_enabled
}

output "argocd_namespace" {
  description = "ArgoCD Namespace (EKS Capability)"
  value       = module.eks.argocd_namespace
}

output "argocd_version" {
  description = "ArgoCD Version (EKS Capability)"
  value       = module.eks.argocd_version
}

output "argocd_access_info" {
  description = "ArgoCD access information"
  value       = module.eks.argocd_access_info
  sensitive   = true
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_id}"
}

output "aws_account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}
