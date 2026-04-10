variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-7"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "leave-system"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.35"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["ap-southeast-7a", "ap-southeast-7b", "ap-southeast-7c"]
}

variable "instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "desired_capacity" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 3
}

variable "min_capacity" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 10
}

variable "enable_argocd" {
  description = "Enable ArgoCD installation"
  type        = bool
  default     = true
}
# ============================================
# EKS Managed Add-ons Configuration
# ============================================

variable "enable_ebs_csi_driver" {
  description = "Enable AWS EBS CSI Driver add-on"
  type        = bool
  default     = true
}

variable "enable_efs_csi_driver" {
  description = "Enable AWS EFS CSI Driver add-on"
  type        = bool
  default     = false
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
  description = "Enable Ingress for ArgoCD"
  type        = bool
  default     = true
}

variable "argocd_ingress_hostname" {
  description = "Hostname for ArgoCD Ingress"
  type        = string
  default     = "argocd.example.com"
}

variable "github_token" {
  description = "GitHub personal access token for ArgoCD"
  type        = string
  sensitive   = true
  default     = ""
}

variable "github_username" {
  description = "GitHub username for ArgoCD"
  type        = string
  default     = ""
}

variable "github_repo_url" {
  description = "GitHub repository URL for GitOps"
  type        = string
  default     = ""
}

# ============================================
# Monitoring Stack Configuration
# ============================================

variable "enable_monitoring_stack" {
  description = "Enable Prometheus, Loki, Tempo, and Grafana monitoring stack"
  type        = bool
  default     = true
}

variable "prometheus_storage_size" {
  description = "Prometheus persistent volume size (Gi)"
  type        = string
  default     = "50Gi"
}

variable "grafana_admin_password" {
  description = "Grafana admin password (change this!)"
  type        = string
  sensitive   = true
  default     = "admin123"
}

variable "enable_alerting" {
  description = "Enable Prometheus alerting"
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email address for alert notifications"
  type        = string
  default     = "alerts@example.com"
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default = {
    "ManagedBy" = "Terraform"
    "CostCenter" = "Engineering"
  }
}
