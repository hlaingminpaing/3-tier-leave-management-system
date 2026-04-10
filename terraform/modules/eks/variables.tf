variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.35"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs"
  type        = list(string)
}

variable "cluster_security_group_id" {
  description = "Cluster security group ID"
  type        = string
}

variable "node_security_group_id" {
  description = "Node security group ID"
  type        = string
}

variable "cluster_role_arn" {
  description = "Cluster IAM role ARN"
  type        = string
}

variable "node_role_arn" {
  description = "Node IAM role ARN"
  type        = string
}

variable "node_instance_profile_arn" {
  description = "Node instance profile ARN"
  type        = string
}

variable "desired_capacity" {
  description = "Desired number of nodes"
  type        = number
  default     = 3
}

variable "min_capacity" {
  description = "Minimum number of nodes"
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Maximum number of nodes"
  type        = number
  default     = 10
}

variable "instance_type" {
  description = "EC2 instance type for nodes"
  type        = string
  default     = "t3.medium"
}

variable "enable_cluster_autoscaler" {
  description = "Enable cluster autoscaler"
  type        = bool
  default     = true
}

variable "enable_metrics_server" {
  description = "Enable metrics server"
  type        = bool
  default     = true
}

# ====================================================
# EKS Managed Add-ons Configuration
# ====================================================

variable "enable_ebs_csi_driver" {
  description = "Enable AWS EBS CSI Driver add-on (for EBS persistent volumes)"
  type        = bool
  default     = true
}

variable "enable_efs_csi_driver" {
  description = "Enable AWS EFS CSI Driver add-on (for EFS persistent volumes)"
  type        = bool
  default     = false
}

# ArgoCD - EKS Capability Configuration
variable "enable_argocd" {
  description = "Enable ArgoCD as EKS capability"
  type        = bool
  default     = true
}

variable "argocd_namespace" {
  description = "Namespace for ArgoCD"
  type        = string
  default     = "argocd"
}

variable "argocd_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "7.0.0"
}

variable "enable_argocd_ingress" {
  description = "Enable ALB Ingress for ArgoCD API Server"
  type        = bool
  default     = true
}

variable "argocd_ingress_hostname" {
  description = "Hostname for ArgoCD Ingress"
  type        = string
  default     = "argocd.example.com"
}

variable "github_token" {
  description = "GitHub token for repository credentials (optional)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "github_username" {
  description = "GitHub username for repository credentials (optional)"
  type        = string
  default     = ""
}

variable "github_repo_url" {
  description = "GitHub repository URL for GitOps (optional)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
