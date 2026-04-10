variable "cluster_id" {
  description = "EKS cluster ID"
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS cluster endpoint"
  type        = string
}

variable "cluster_ca_certificate" {
  description = "EKS cluster CA certificate"
  type        = string
  sensitive   = true
}

variable "oidc_provider_arn" {
  description = "OIDC Provider ARN for IRSA"
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC Provider URL"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "prometheus_storage_size" {
  description = "Prometheus storage size (Gi)"
  type        = string
  default     = "50Gi"
}

variable "tempo_storage_bucket" {
  description = "S3 bucket for Tempo storage"
  type        = string
  default     = ""
}

variable "loki_storage_bucket" {
  description = "S3 bucket for Loki storage"
  type        = string
  default     = ""
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
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
  description = "Email for alerting"
  type        = string
  default     = "alerts@example.com"
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
