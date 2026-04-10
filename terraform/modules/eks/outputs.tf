output "cluster_id" {
  description = "EKS cluster ID"
  value       = aws_eks_cluster.main.id
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  description = "EKS cluster version"
  value       = aws_eks_cluster.main.version
}

output "cluster_ca_certificate" {
  description = "EKS cluster CA certificate"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Security group id attached to the EKS cluster"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "node_group_id" {
  description = "EKS node group ID"
  value       = aws_eks_node_group.main.id
}

output "oidc_provider_arn" {
  description = "OIDC Provider ARN"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "OIDC Provider URL"
  value       = aws_iam_openid_connect_provider.eks.url
}

output "load_balancer_controller_role_arn" {
  description = "AWS Load Balancer Controller IAM Role ARN"
  value       = aws_iam_role.aws_load_balancer_controller.arn
}

output "cluster_autoscaler_role_arn" {
  description = "Cluster Autoscaler IAM Role ARN"
  value       = try(aws_iam_role.cluster_autoscaler[0].arn, null)
}

# ====================================================
# EKS Managed Add-ons Outputs
# ====================================================

output "vpc_cni_addon_version" {
  description = "VPC CNI Add-on version"
  value       = aws_eks_addon.vpc_cni.addon_version
}

output "coredns_addon_version" {
  description = "CoreDNS Add-on version"
  value       = aws_eks_addon.coredns.addon_version
}

output "kube_proxy_addon_version" {
  description = "Kube Proxy Add-on version"
  value       = aws_eks_addon.kube_proxy.addon_version
}

output "ebs_csi_driver_addon_version" {
  description = "EBS CSI Driver Add-on version"
  value       = try(aws_eks_addon.ebs_csi_driver[0].addon_version, null)
}

output "efs_csi_driver_addon_version" {
  description = "EFS CSI Driver Add-on version"
  value       = try(aws_eks_addon.efs_csi_driver[0].addon_version, null)
}

# ArgoCD EKS Capability Outputs
output "argocd_enabled" {
  description = "Whether ArgoCD is enabled as EKS capability"
  value       = var.enable_argocd
}

output "argocd_namespace" {
  description = "ArgoCD namespace"
  value       = var.enable_argocd ? kubernetes_namespace.argocd[0].metadata[0].name : null
}

output "argocd_release_name" {
  description = "ArgoCD Helm release name"
  value       = var.enable_argocd ? helm_release.argocd[0].name : null
}

output "argocd_version" {
  description = "ArgoCD version"
  value       = var.enable_argocd ? helm_release.argocd[0].version : null
}

output "argocd_default_admin_password" {
  description = "ArgoCD default admin password (change this immediately)"
  value       = var.enable_argocd ? "${var.project_name}@${var.environment}" : null
  sensitive   = true
}

output "argocd_access_info" {
  description = "Information to access ArgoCD"
  value = var.enable_argocd ? {
    namespace               = kubernetes_namespace.argocd[0].metadata[0].name
    service_name            = "argocd-server"
    port_forward_command    = "kubectl port-forward -n argocd svc/argocd-server 8080:443"
    ingress_hostname        = var.enable_argocd_ingress ? var.argocd_ingress_hostname : "N/A"
    default_username        = "admin"
    default_password        = "${var.project_name}@${var.environment}"
  } : null
  sensitive = true
}
