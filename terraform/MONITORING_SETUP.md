# Monitoring Stack Setup & Integration Guide

## Overview

Your Terraform configuration now includes a **complete monitoring stack** with:
- ✅ **Prometheus** - Metrics collection and alerting
- ✅ **Grafana** - Visualization and dashboards  
- ✅ **Loki** - Log aggregation
- ✅ **Tempo** - Distributed tracing
- ✅ **Backend OpenTelemetry Integration** - Ready to send metrics, logs, and traces

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│         Leave-System Backend (Node.js + OpenTelemetry)       │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌─────────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │ Metrics(9464)   │  │ Logs (stdout)│  │ Traces(4318) │   │
│  └────────┬────────┘  └──────┬───────┘  └──────┬───────┘   │
│           │                  │                  │            │
└───────────┼──────────────────┼──────────────────┼────────────┘
            │                  │                  │
       ┌────▼──────┐    ┌──────▼────────┐   ┌────▼────────┐
       │Prometheus │    │ Promtail/Loki │   │  Tempo      │
       │(metrics)  │    │ (logs)        │   │ (traces)    │
       └────┬──────┘    └──────┬────────┘   └────┬────────┘
            │                  │                  │
            └──────────────────┼──────────────────┘
                               │
                         ┌─────▼──────┐
                         │  Grafana   │
                         │ Dashboards │
                         └────────────┘
```

## What's Now Working

### ✅ Backend Instrumentation (Already Configured)

Your backend (`instrumentation.js`) exports:

```javascript
// Metrics: http://backend:9464/metrics (Prometheus format)
new PrometheusExporter({ port: 9464, endpoint: '/metrics' })

// Traces: Sent to Tempo via OTLP HTTP
new OTLPTraceExporter()  // Default: http://localhost:4318

// All auto-instrumented:
- HTTP requests/responses
- Database queries  
- Memory/CPU usage
- Error rates
```

### ✅ Prometheus Monitoring

```yaml
# Automatic scraping via ServiceMonitor
- Backend metrics endpoint: :9464/metrics
- Interval: 30s
- Retention: 30 days
- Persistent storage: 50Gi EBS
```

### ✅ Loki Log Collection

```yaml
# Promtail auto-discovers pods in all namespaces
- Scrapes pod logs (stdout/stderr)
- Labels pods by: app, namespace, pod name
- Sends to Loki for aggregation
- Retention: 30 days
```

### ✅ Tempo Distributed Tracing

```yaml
# Receives OTLP from backend instrumentation
- Accepts gRPC traces on :4317
- Accepts HTTP traces on :4318
- Enriches traces with service name
- Stores traces for 24 hours
```

### ✅ Grafana Dashboards

```yaml
# Pre-configured data sources:
- Prometheus (metrics)
- Loki (logs)
- Tempo (traces)
- Example dashboard for backend metrics
```

## Deployment

### 1. Enable Monitoring in Terraform

```hcl
# terraform.tfvars (already configured)
enable_monitoring_stack = true
prometheus_storage_size = "50Gi"
grafana_admin_password  = "ChangeMeInProductionEnv123!"
```

### 2. Deploy

```bash
cd terraform
terraform plan
terraform apply
```

**This will install:**
1. Prometheus + Grafana stack (kube-prometheus-stack Helm chart)
2. Loki for log aggregation
3. Tempo for distributed tracing
4. All necessary permissions and endpoints

### 3. Verify Installation

```bash
# Check namespace
kubectl get namespace monitoring

# Check pods
kubectl get pods -n monitoring

# Check services
kubectl get svc -n monitoring
```

**Expected output:**
```
NAME                                               READY
kube-prometheus-stack-prometheus-0                 2/2
kube-prometheus-stack-grafana-xxxxxxxxxx           1/1
loki-0                                             1/1
tempo-0                                            1/1
prometheus-kube-state-metrics-xxxxxxxxxx           1/1
prometheus-node-exporter-xxxxx                     1/1
```

## Accessing the Stack

### 1. Grafana

```bash
# Port forward to local machine
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Access at: http://localhost:3000
# Username: admin
# Password: (from terraform output or terraform.tfvars)
```

Then in Grafana:
1. Go to **Data Sources** (already configured)
2. Go to **Dashboards** → **Backend Metrics** (pre-populated)
3. View live metrics, logs, and traces

### 2. Prometheus UI

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Access at: http://localhost:9090
```

Here you can:
- Query metrics directly
- View scrape targets (should show backend)
- Test PromQL queries

### 3. Tempo (Tracing)

```bash
# Traces are viewed through Grafana's Tempo plugin
# In Grafana → Explore → Select Tempo datasource
# Search for traces from your backend
```

## Backend Integration Example

### 1. Backend Service Definition (Kubernetes)

Create a `backend-service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: leave-backend
  labels:
    app: leave-backend
spec:
  selector:
    app: leave-backend
  ports:
  - name: "3000"
    port: 3000
    targetPort: 3000
  - name: "9464"  # Prometheus metrics port
    port: 9464
    targetPort: 9464
```

### 2. Backend Deployment Environment Variables

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: leave-backend
  namespace: default
spec:
  template:
    spec:
      containers:
      - name: backend
        image: your-backend:latest
        ports:
        - containerPort: 3000
        - containerPort: 9464  # Metrics port
        env:
        # IMPORTANT: Set Tempo endpoint for tracing
        - name: OTEL_EXPORTER_OTLP_ENDPOINT
          value: "http://tempo-otlp-http.monitoring:4318"
        - name: OTEL_SERVICE_NAME
          value: "leave-backend"
        - name: NODE_ENV
          value: "production"
```

### 3. Verify Backend Metrics

```bash
# Port forward to backend
kubectl port-forward -n default svc/leave-backend 9464:9464

# Check metrics endpoint
curl http://localhost:9464/metrics

# Should output Prometheus format metrics:
# TYPE process_resident_memory_bytes gauge
# process_resident_memory_bytes X.XXeXX
# TYPE http_request_duration_seconds histogram
# ...
```

## Dashboard Queries

### Common Prometheus Queries for Leave Backend

```promql
# Request rate (requests per second)
rate(process_http_requests_total[5m])

# Average response time (ms)
rate(process_http_request_duration_seconds_sum[5m]) / rate(process_http_request_duration_seconds_count[5m]) * 1000

# Error rate
rate(process_http_requests_total{status=~"5.."}[5m])

# Memory usage (MB)
process_resident_memory_bytes / 1024 / 1024

# CPU usage (%)
rate(process_cpu_seconds_total[5m]) * 100
```

### Loki Queries for Logs

```logql
# All backend logs
{app="leave-backend"}

# Error logs only
{app="leave-backend"} |= "error" or "Error" or "ERROR"

# Sequence logs by pod
{app="leave-backend"} | json

# Response time logs
{app="leave-backend"} | pattern "response_time=<time>"
```

### Tempo Queries for Traces

In Grafana → Explore → Tempo:
1. Service: `leave-backend`
2. Operation: Any (or specific endpoint)
3. Status: Any
4. Duration: Any
5. Search traces

## Alerting (Optional)

### Pre-configured Alerts in Prometheus

To enable email alerts, update Prometheus AlertManager config:

```yaml
# In kube-prometheus-stack values
alertmanager:
  config:
    global:
      smtp_smarthost: 'smtp.gmail.com:587'
      smtp_from: 'alerts@example.com'
      smtp_auth_username: 'your-email@gmail.com'
      smtp_auth_password: 'app-password'
```

### Example Alert Rules

Create `monitoring/alert-rules.yaml`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: backend-alerts
  namespace: monitoring
spec:
  groups:
  - name: backend.rules
    interval: 30s
    rules:
    - alert: HighErrorRate
      expr: rate(http_requests_total{app="leave-backend",status=~"5.."}[5m]) > 0.05
      for: 5m
      annotations:
        summary: "High error rate in backend"
    
    - alert: HighMemoryUsage
      expr: process_resident_memory_bytes{app="leave-backend"} / 1024 / 1024 > 512
      for: 10m
      annotations:
        summary: "Backend memory usage over 512MB"
```

## Troubleshooting

### Metrics Not Showing in Prometheus

```bash
# 1. Verify backend pod has metrics port
kubectl get pods -o=custom-columns=NAME:.metadata.name,PORTS:.spec.containers[*].ports[*].containerPort

# 2. Check ServiceMonitor detected
kubectl get servicemonitor -n monitoring
kubectl describe servicemonitor leave-backend-monitor -n monitoring

# 3. Check Prometheus targets
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Visit http://localhost:9090/targets
```

### Logs Not Appearing in Loki

```bash
# 1. Check Promtail is running
kubectl get pods -n monitoring | grep promtail

# 2. Check Loki is accessible
kubectl logs -n monitoring -l app=promtail

# 3. Verify pod labels match scrape config
kubectl describe pod -n default <backend-pod-name> | grep Labels
```

### Traces Not in Tempo

```bash
# 1. Verify backend has OTEL_EXPORTER_OTLP_ENDPOINT set
kubectl exec -n default <backend-pod> -- env | grep OTEL

# 2. Check Tempo receiver is working
kubectl logs -n monitoring -l app=tempo | grep "otlp"

# 3. Test connectivity from backend pod
kubectl exec -n default <backend-pod> -- curl -v http://tempo-otlp-http.monitoring:4318/v1/traces
```

## Best Practices

1. **Change Grafana Password**: On first login, configure a strong password
2. **Backup Dashboards**: Export Grafana dashboards regularly
3. **Alert Tuning**: Adjust alert thresholds based on application baselines
4. **Log Retention**: Increase retention period for compliance in production
5. **Trace Sampling**: In production, consider sampling to reduce storage costs
6. **Monitor the Monitors**: Set up alerts for monitoring stack itself

## Limits and Quotas

Current configuration:

| Component | Resource | Limit |
|-----------|----------|-------|
| Prometheus | Storage | 50Gi |
| Prometheus | Memory | 1Gi |
| Prometheus | CPU | 500m |
| Loki | Storage | 10Gi |
| Loki | Memory | 256Mi |
| Tempo | Storage | 10Gi |
| Grafana | Storage | 10Gi |
| Grafana | Memory | 256Mi |

To update, modify `terraform.tfvars` and reapply.

## Next Steps

1. ✅ Deploy monitoring stack with `terraform apply`
2. ✅ Verify backend metrics in Prometheus
3. ✅ View logs in Grafana/Loki
4. ✅ Check traces in Grafana/Tempo
5. Configure custom dashboards for your KPIs
6. Set up alerting rules for production
7. Integrate with incident management (PagerDuty, etc.)

## Summary

Your monitoring setup now provides:
- **Metrics**: Real-time backend performance monitoring
- **Logs**: Centralized log aggregation from all pods
- **Traces**: Distributed tracing for request flows
- **Dashboards**: Pre-configured Grafana visualizations
- **Alerts**: Automated alerting for anomalies

Everything is **Infrastructure as Code** via Terraform! 🎉
