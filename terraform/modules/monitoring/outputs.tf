output "monitoring_namespace" {
  description = "Kubernetes namespace for monitoring"
  value       = kubernetes_namespace.monitoring.metadata[0].name
}

output "prometheus_release_name" {
  description = "Prometheus Helm release name"
  value       = helm_release.kube_prometheus_stack.name
}

output "prometheus_version" {
  description = "Prometheus version"
  value       = helm_release.kube_prometheus_stack.version
}

output "grafana_admin_username" {
  description = "Grafana admin username"
  value       = "admin"
}

output "grafana_admin_password" {
  description = "Grafana admin password (change this!)"
  value       = var.grafana_admin_password
  sensitive   = true
}

output "loki_release_name" {
  description = "Loki Helm release name"
  value       = helm_release.loki.name
}

output "tempo_release_name" {
  description = "Tempo Helm release name"
  value       = helm_release.tempo.name
}

output "tempo_otlp_endpoint" {
  description = "Tempo OTLP HTTP endpoint for backend instrumentation"
  value       = "http://tempo-otlp-http.monitoring:4318"
}

output "monitoring_stack_info" {
  description = "Complete monitoring stack information"
  value = {
    namespace              = kubernetes_namespace.monitoring.metadata[0].name
    prometheus_endpoint    = "http://kube-prometheus-stack-prometheus:9090"
    grafana_endpoint       = "http://kube-prometheus-stack-grafana:80"
    loki_endpoint          = "http://loki:3100"
    tempo_endpoint         = "http://tempo:3100"
    tempo_otlp_http        = "http://tempo-otlp-http.monitoring:4318"
    grafana_username       = "admin"
    grafana_default_password = var.grafana_admin_password
    access_methods = {
      port_forward_grafana    = "kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
      port_forward_prometheus = "kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090"
      port_forward_loki       = "kubectl port-forward -n monitoring svc/loki 3100:3100"
      port_forward_tempo      = "kubectl port-forward -n monitoring svc/tempo 3100:3100"
    }
  }
}
