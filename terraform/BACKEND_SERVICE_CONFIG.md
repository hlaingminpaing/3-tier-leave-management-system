# Backend K8s Service Integration Guide

## Overview

To fully integrate your Node.js backend with the monitoring stack, you need to:
1. Expose the metrics port (9464) in Kubernetes
2. Configure Tempo endpoint for trace export
3. Ensure service discovery works properly

## Backend Service Definition

Create a `backend-service.yaml` in your k8s or helm-chart/templates directory:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: leave-backend
  namespace: default
  labels:
    app: leave-backend
    version: v1
spec:
  type: ClusterIP
  selector:
    app: leave-backend
  ports:
  - name: api
    port: 3000
    targetPort: 3000
    protocol: TCP
  - name: metrics
    port: 9464
    targetPort: 9464
    protocol: TCP
```

## Backend Deployment Configuration

Update your deployment to include proper environment variables and port definitions:

### Via Helm Chart (Recommended)

Edit `helm-chart/templates/backend-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: leave-backend
  namespace: {{ .Values.namespace | default "default" }}
  labels:
    app: leave-backend
    version: v1
spec:
  replicas: {{ .Values.backend.replicaCount | default 1 }}
  selector:
    matchLabels:
      app: leave-backend
  template:
    metadata:
      labels:
        app: leave-backend
        version: v1
      annotations:
        # This tells Prometheus to scrape this pod
        prometheus.io/scrape: "true"
        prometheus.io/port: "9464"
        prometheus.io/path: "/metrics"
    spec:
      serviceAccountName: leave-backend
      containers:
      - name: backend
        image: {{ .Values.backend.image }}:{{ .Values.backend.tag }}
        imagePullPolicy: IfNotPresent
        ports:
        - name: api
          containerPort: 3000
          protocol: TCP
        - name: metrics
          containerPort: 9464
          protocol: TCP
        
        # Environment variables for OpenTelemetry
        env:
        # Database configuration
        - name: DB_HOST
          valueFrom:
            configMapKeyRef:
              name: backend-config
              key: db_host
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: backend-secrets
              key: db_user
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: backend-secrets
              key: db_password
        
        # OpenTelemetry configuration
        - name: OTEL_EXPORTER_OTLP_ENDPOINT
          # Tempo is in monitoring namespace, accessible via DNS
          value: "http://tempo-otlp-http.monitoring:4318"
        - name: OTEL_SERVICE_NAME
          value: "leave-backend"
        - name: OTEL_SDK_DISABLED
          value: "false"
        - name: OTEL_TRACES_EXPORTER
          value: "otlp"
        - name: OTEL_METRICS_EXPORTER
          value: "prometheus"
        
        # Application configuration
        - name: NODE_ENV
          value: "production"
        - name: PORT
          value: "3000"
        
        # Health checks
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        
        readinessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
        
        # Resource requests and limits
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
        
        # Security context
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          readOnlyRootFilesystem: false
          allowPrivilegeEscalation: false
```

### Via Direct Kubernetes Manifest

If using plain Kubernetes YAML (for ArgoCD):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: leave-backend
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: leave-backend
  template:
    metadata:
      labels:
        app: leave-backend
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9464"
    spec:
      containers:
      - name: backend
        image: your-registry/leave-backend:latest
        ports:
        - containerPort: 3000
          name: api
        - containerPort: 9464
          name: metrics
        
        env:
        # CRITICAL: Set Tempo endpoint for traces to be collected
        - name: OTEL_EXPORTER_OTLP_ENDPOINT
          value: "http://tempo-otlp-http.monitoring:4318"
        - name: OTEL_SERVICE_NAME
          value: "leave-backend"
        - name: NODE_ENV
          value: "production"
        
        # Health checks
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 10
          periodSeconds: 5
        
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
```

## ServiceMonitor Configuration

The Terraform monitoring module already creates a ServiceMonitor, but here's what it looks like:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: backend-metrics
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: leave-backend
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
    scheme: http
```

This tells Prometheus to:
- Find all Services with label `app: leave-backend`
- Scrape the `metrics` port
- Every 30 seconds
- At the `/metrics` endpoint

## Verification Steps

### 1. Verify Service is Created

```bash
kubectl get svc leave-backend
kubectl describe svc leave-backend
```

Expected output should show both ports:
```
Name:              leave-backend
Namespace:         default
Selector:          app=leave-backend

Port:              api  3000/TCP
TargetPort:        3000/TCP

Port:              metrics  9464/TCP
TargetPort:        9464/TCP
```

### 2. Verify Pod Labels Match

```bash
kubectl get pods -l app=leave-backend --show-labels
```

Should show labels including:
```
LABELS
app=leave-backend,version=v1
```

### 3. Test Metrics Endpoint

```bash
# Port forward to backend
kubectl port-forward svc/leave-backend 9464:9464

# In another terminal
curl http://localhost:9464/metrics
```

Should output Prometheus format metrics like:
```
# HELP process_resident_memory_bytes Resident memory size in bytes.
# TYPE process_resident_memory_bytes gauge
process_resident_memory_bytes 84549632
```

### 4. Verify ServiceMonitor Detection

```bash
# Check if ServiceMonitor was created
kubectl get servicemonitor -n monitoring

# Check if Prometheus detected the target
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
```

Then visit `http://localhost:9090/targets` and look for:
- Job: `backend-metrics`
- Labels: `app=leave-backend`
- State: **UP** (green)

### 5. Verify Tempo Connection

```bash
# Check backend pod logs for connection
kubectl logs -l app=leave-backend | grep -i tempo

# Should see OpenTelemetry SDK initialization
```

### 6. Query Metrics in Prometheus

```bash
# Port forward to Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
```

Visit `http://localhost:9090` and try:
- Query: `up{job="backend-metrics"}`
- Query: `rate(http_requests_total[5m])`
- Query: `process_resident_memory_bytes`

## Debugging Connection Issues

### If metrics aren't appearing:

```bash
# 1. Check pod has metrics port
kubectl describe pod -l app=leave-backend | grep -A 5 "Ports:"

# 2. Check backend is running
kubectl logs -l app=leave-backend | head -20

# 3. Check metrics endpoint is accessible
kubectl exec -l app=leave-backend -- curl -s http://localhost:9464/metrics | head

# 4. Check service endpoints
kubectl get endpoints leave-backend
```

### If traces aren't reaching Tempo:

```bash
# 1. Verify environment variable is set
kubectl exec -l app=leave-backend -- env | grep OTEL

# 2. Check Tempo is reachable from pod
kubectl exec -l app=leave-backend -- curl -v http://tempo-otlp-http.monitoring:4318/

# 3. Check Tempo logs
kubectl logs -n monitoring -l app=tempo | tail

# 4. Verify DNS resolution
kubectl exec -l app=leave-backend -- nslookup tempo-otlp-http.monitoring
```

## Configuration Issues & Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| Metrics not scraped | Port not exposed in service | Add `- name: metrics port: 9464` to service |
| Traces not collected | OTEL_EXPORTER_OTLP_ENDPOINT wrong | Set to `http://tempo-otlp-http.monitoring:4318` |
| High memory usage | Sampling rate too high | Set `OTEL_TRACES_SAMPLE_RATE=0.1` |
| DNS resolution fails | Namespace not accessible | Use full DNS name: `<svc>.<namespace>.svc.cluster.local` |
| Pod won't start | Memory limits too low | Increase to `256Mi` minimum for Node.js |

## Production Recommendations

### 1. Resource Management

```yaml
resources:
  requests:
    cpu: 200m
    memory: 256Mi
  limits:
    cpu: 1000m
    memory: 1Gi
```

### 2. Sampling Configuration

For high-traffic backends, enable sampling to reduce trace volume:

```yaml
env:
- name: OTEL_TRACES_SAMPLE_RATE
  value: "0.1"  # 10% sampling
```

### 3. Multiple Replicas

```yaml
replicas: 3
```

### 4. Pod Affinity

```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchExpressions:
          - key: app
            operator: In
            values:
            - leave-backend
        topologyKey: kubernetes.io/hostname
```

## Helm Values Example

If using Helm, add to `values.yaml`:

```yaml
backend:
  image: your-registry/leave-backend
  tag: latest
  replicaCount: 2
  
  env:
    OTEL_EXPORTER_OTLP_ENDPOINT: "http://tempo-otlp-http.monitoring:4318"
    OTEL_SERVICE_NAME: "leave-backend"
    NODE_ENV: "production"
  
  service:
    type: ClusterIP
    ports:
      api: 3000
      metrics: 9464
  
  resources:
    requests:
      cpu: 200m
      memory: 256Mi
    limits:
      cpu: 1000m
      memory: 1Gi
  
  # Enable Prometheus scraping
  podAnnotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "9464"
    prometheus.io/path: "/metrics"
```

## Final Checklist

Before deploying to production:

- [ ] Service exposes both API (3000) and metrics (9464) ports
- [ ] OTEL_EXPORTER_OTLP_ENDPOINT is set to `http://tempo-otlp-http.monitoring:4318`
- [ ] Pod labels include `app: leave-backend`
- [ ] Health checks are configured
- [ ] Resource requests and limits are set
- [ ] ServiceMonitor shows UP in Prometheus targets
- [ ] Metrics appear in Prometheus within 30 seconds
- [ ] Traces appear in Grafana/Tempo within seconds of API calls
- [ ] Logs appear in Grafana/Loki
- [ ] Dashboards display data correctly

Once verified, your backend is fully integrated with the monitoring stack! 🎉
