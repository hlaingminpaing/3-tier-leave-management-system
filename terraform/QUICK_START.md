# Monitoring Stack Deployment Quick Start

## What's Ready to Deploy

Your Terraform configuration now includes a **production-ready monitoring stack**:

| Component | Status | Access |
|-----------|--------|--------|
| **Prometheus** | ✅ Configured | Port 9090 |
| **Grafana** | ✅ Configured | Port 3000 |
| **Loki** | ✅ Configured | Internal |
| **Tempo** | ✅ Configured | Port 4318 (OTLP HTTP) |
| **Backend Integration** | ✅ Ready | Metrics:9464 + Traces:4318 |

## 5-Minute Deployment

### Step 1: Navigate to Terraform
```bash
cd d:\Code\3tier-leave-system\terraform
```

### Step 2: Initialize Terraform (first time only)
```bash
terraform init
```

### Step 3: Review Changes
```bash
terraform plan
```

Look for the new monitoring stack resources:
- `aws_eks_addon` for EKS add-ons (vpc-cni, coredns, kube-proxy, ebs-csi)
- `helm_release` for Prometheus, Loki, Tempo, Grafana

### Step 4: Deploy Everything
```bash
terraform apply
```

**Type `yes` when prompted.**

This will deploy:
- EKS cluster (1.35) with 3 managed nodes (t3.medium)
- All EKS add-ons
- Complete monitoring stack
- Networking (VPC, subnets, ALB)
- Database (if configured)
- Total time: ~20-30 minutes

### Step 5: Verify Deployment
```bash
# Check monitoring namespace
kubectl get namespace monitoring

# Check monitoring pods
kubectl get pods -n monitoring

# Should see: prometheus, grafana, loki, tempo pods
```

## Access the Monitoring Stack

### Method 1: Port Forwarding (Recommended for Learning)

```powershell
# Terminal 1: Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Access: http://localhost:3000
# User: admin
# Password: ChangeMeInProductionEnv123! (or from terraform.tfvars)

# Terminal 2: Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Access: http://localhost:9090

# Terminal 3: Backend Metrics
kubectl port-forward svc/leave-backend 9464:9464
# Access: http://localhost:9464/metrics
```

### Method 2: ALB Ingress (For Production)

The monitoring stack is automatically exposed via ALB:
- Grafana: `grafana.example.com`
- Prometheus: `prometheus.example.com`
- Tempo: `tempo.example.com`

Update your DNS or /etc/hosts:
```
<ALB-DNS-NAME> grafana.example.com prometheus.example.com
```

## Verify Backend Integration

### 1. Check Backend Pod is Running
```bash
kubectl get pods -l app=leave-backend
```

### 2. Check Metrics are Being Exported
```bash
# Port forward to backend
kubectl port-forward svc/leave-backend 9464:9464

# In another terminal
curl http://localhost:9464/metrics | head -20
```

### 3. Verify Prometheus is Scraping Metrics
```bash
# Port forward to Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Visit http://localhost:9090/targets
# Look for job "backend-metrics" with status UP (green)
```

### 4. View Metrics in Grafana
```bash
# Port forward to Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Login: admin / ChangeMeInProductionEnv123!
# Navigate: Dashboards → Backend Metrics
```

### 5. Check Traces are Being Sent to Tempo
```bash
# In Grafana, go to Explore tab
# Select Tempo data source
# Select service: leave-backend
# View live traces from your API calls
```

## Deployment Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    AWS EKS Cluster (1.35)                    │
│                    ap-southeast-1 Region                      │
├─────────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────────────┐  │
│  │         Default Namespace (Leave System)                 │  │
│  ├────────────────────────────────────────────────────────┤  │
│  │  • leave-backend (3000) → /health + /api routes       │  │
│  │  • leave-backend (9464) → /metrics (Prometheus)       │  │
│  │  • leave-frontend (80) → React SPA                    │  │
│  │  • leave-mysql (3306) → Database                      │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                                │
│  ┌────────────────────────────────────────────────────────┐  │
│  │         Monitoring Namespace                            │  │
│  ├────────────────────────────────────────────────────────┤  │
│  │  • kube-prometheus-stack                              │  │
│  │    ├─ Prometheus (metrics scraper)                    │  │
│  │    ├─ Grafana (visualization)                         │  │
│  │    ├─ AlertManager (alerting)                         │  │
│  │    └─ Node Exporter                                   │  │
│  │  • Loki (log aggregator)                              │  │
│  │    └─ Promtail (log shipper)                          │  │
│  │  • Tempo (trace collector)                            │  │
│  │    └─ Receivers: gRPC:4317, HTTP:4318                │  │
│  └────────────────────────────────────────────────────────┘  │
│                         ↓                                      │
│  ┌────────────────────────────────────────────────────────┐  │
│  │              Storage (EBS)                              │  │
│  ├────────────────────────────────────────────────────────┤  │
│  │  • Prometheus: 50Gi                                   │  │
│  │  • Loki: 10Gi                                         │  │
│  │  • Tempo: 10Gi                                        │  │
│  │  • Grafana: 10Gi                                      │  │
│  └────────────────────────────────────────────────────────┘  │
│                         ↓                                      │
│  ┌────────────────────────────────────────────────────────┐  │
│  │         AWS ALB (Application Load Balancer)             │  │
│  ├────────────────────────────────────────────────────────┤  │
│  │  • Backend: backend.example.com                       │  │
│  │  • Frontend: frontend.example.com                     │  │
│  │  • Grafana: grafana.example.com                       │  │
│  │  • Prometheus: prometheus.example.com                 │  │
│  └────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Key Files to Review

After deployment, check:

1. **Monitoring Configuration**
   - [terraform/modules/monitoring/main.tf](../modules/monitoring/main.tf) - Helm charts and Pod configs
   - [terraform/modules/monitoring/outputs.tf](../modules/monitoring/outputs.tf) - Access endpoints

2. **Backend Configuration**
   - [backend/instrumentation.js](../backend/instrumentation.js) - OpenTelemetry setup
   - [backend/package.json](../backend/package.json) - Dependencies

3. **Deployment Manifests**
   - [k8s/backend.yaml](../k8s/backend.yaml) - Backend deployment
   - [helm-chart/templates/backend-deployment.yaml](../helm-chart/templates/backend-deployment.yaml) - Helm version

## Important Environment Variables

The monitoring stack uses these critical settings:

```hcl
# terraform/terraform.tfvars
enable_monitoring_stack = true              # Deploy the stack
grafana_admin_password  = "YourPasswordHere"  # Change this!
prometheus_storage_size = "50Gi"            # Metrics retention
enable_alerting         = false             # Change to true for alerts
alert_email             = "your@email.com"  # Update this
```

## Next Steps After Deployment

### 1. Generate Sample Data
```bash
# Make API calls to backend to generate metrics/traces
for i in {1..100}; do curl http://localhost:3000/api/leave; done
```

### 2. Create Custom Dashboards
- Open Grafana
- Explore → Create new panel
- Query Prometheus metrics or Tempo traces
- Add to dashboard

### 3. Set Up Alerting
- Configure AlertManager SMTP settings
- Define alert rules in monitoring/alert-rules.yaml
- Set enable_alerting = true in terraform.tfvars

### 4. Scale Up to Production
- Increase node replicas and backend replicas
- Enable S3 storage for Tempo/Loki (instead of EBS)
- Configure network policies
- Set up backups

## Troubleshooting Deployment

### Pods not starting?
```bash
# Check pod events
kubectl describe pod -n monitoring <pod-name>
kubectl logs -n monitoring <pod-name>
```

### Prometheus not scraping?
```bash
# Check targets
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Visit http://localhost:9090/targets
```

### Out of storage?
```bash
# Check PVC usage
kubectl get pvc -n monitoring
kubectl describe pvc -n monitoring

# Increase in terraform.tfvars
prometheus_storage_size = "100Gi"
terraform apply
```

### DNS issues?
```bash
# Test DNS from backend pod
kubectl exec -l app=leave-backend -- nslookup tempo-otlp-http.monitoring

# Test connectivity
kubectl exec -l app=leave-backend -- curl -v http://tempo-otlp-http.monitoring:4318
```

## Cleanup (If Needed)

To destroy the entire stack:
```bash
terraform destroy
```

To keep the cluster but remove monitoring:
```hcl
# In terraform.tfvars
enable_monitoring_stack = false

terraform apply
```

## Performance Expectations

| Metric | Expected | Note |
|--------|----------|------|
| Prometheus scrape interval | 30s | Configurable in module |
| Trace latency | <100ms | From backend to Tempo |
| Log ingestion | Real-time | Via Promtail |
| Dashboard load | <2s | From multiple datasources |
| Metrics query response | <1s | For 24-hour range |

## Documentation Links

- [Backend Service Configuration](./BACKEND_SERVICE_CONFIG.md) - Kubernetes manifests and environment setup
- [Monitoring Setup Details](./MONITORING_SETUP.md) - Complete monitoring stack guide
- [Terraform Code](./main.tf) - Infrastructure as Code

---

**You're all set!** Deploy with `terraform apply` and start observing your leave management system. 🚀

Questions? Check the troubleshooting section or review the detailed guides above.
