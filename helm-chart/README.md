# Helm Chart for Leave Management System

A comprehensive Helm chart for deploying a 3-tier leave management system with GitOps support using ArgoCD.

## Overview

This Helm chart provides a production-ready deployment configuration for:
- **Frontend**: React/Vite application running on Nginx
- **Backend**: Node.js API with OpenTelemetry instrumentation
- **Database**: MySQL 8 with persistent storage

## Features

- ✅ **GitOps Ready**: Designed for ArgoCD and declarative deployments
- ✅ **Environment Management**: Separate values files for dev/staging/production
- ✅ **Auto-scaling**: Horizontal Pod Autoscaler for backend
- ✅ **Security**: Supports both embedded and external secrets management
- ✅ **Observability**: OpenTelemetry integration for tracing metrics
- ✅ **High Availability**: StatefulSets pattern for MySQL with persistent storage
- ✅ **Ingress Support**: AWS ALB ingress controller integration
- ✅ **Resource Management**: Defined requests and limits for all components

## Chart Structure

```
helm-chart/
├── Chart.yaml                 # Chart metadata
├── values.yaml                # Default values
├── values-dev.yaml           # Development overrides
├── values-staging.yaml        # Staging overrides
├── values-prod.yaml          # Production overrides
├── templates/
│   ├── _helpers.tpl           # Helper functions
│   ├── backend-deployment.yaml
│   ├── backend-service.yaml
│   ├── backend-hpa.yaml
│   ├── frontend-deployment.yaml
│   ├── frontend-service.yaml
│   ├── mysql-deployment.yaml
│   ├── mysql-service.yaml
│   ├── mysql-pvc.yaml
│   ├── secrets.yaml
│   ├── ingress.yaml
│   ├── serviceaccount.yaml
│   └── NOTES.txt
└── README.md
```

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- For ingress: AWS ALB Ingress Controller (for production)
- For external secrets (production): External Secrets Addon

## Quick Start

### Local Development

```bash
# Install with development values
helm install leave-system ./helm-chart \
  -f helm-chart/values.yaml \
  -f helm-chart/values-dev.yaml \
  -n default

# Verify installation
kubectl get pods -n default -l app.kubernetes.io/instance=leave-system
```

### Staging Deployment

```bash
# Install with staging values
helm install leave-system ./helm-chart/leave-management-system \
  -f helm-chart/values.yaml \
  -f helm-chart/values-staging.yaml \
  -n staging

# Check status
kubectl rollout status deployment/leave-system-backend -n staging
kubectl get svc -n staging
```

### Production Deployment with ArgoCD

1. Create an ArgoCD Application:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: leave-system-prod
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/3tier-leave-system
    targetRevision: main
    path: helm-chart
    helm:
      releaseName: leave-system
      valuesFiles:
        - values.yaml
        - values-prod.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

2. Apply the ArgoCD Application:

```bash
kubectl apply -f argocd-app.yaml
```

## Configuration

### Global Settings

| Parameter | Default | Description |
|-----------|---------|-------------|
| `global.namespace` | `default` | Kubernetes namespace |
| `global.environment` | `production` | Environment name |

### Frontend Configuration

| Parameter | Default | Description |
|-----------|---------|-------------|
| `frontend.enabled` | `true` | Enable frontend deployment |
| `frontend.replicaCount` | `1` | Number of replicas |
| `frontend.image.repository` | `ghcr.io/hlaingminpaing/3-tier-leave-management-system/frontend` | Image repository |
| `frontend.image.tag` | `sha-e2ac005` | Image tag |
| `frontend.service.port` | `80` | Service port |
| `frontend.resources.requests.cpu` | `100m` | CPU request |
| `frontend.resources.requests.memory` | `128Mi` | Memory request |

### Backend Configuration

| Parameter | Default | Description |
|-----------|---------|-------------|
| `backend.enabled` | `true` | Enable backend deployment |
| `backend.replicaCount` | `1` | Number of replicas |
| `backend.image.repository` | `ghcr.io/hlaingminpaing/3-tier-leave-management-system/backend` | Image repository |
| `backend.image.tag` | `sha-e2ac005` | Image tag |
| `backend.service.port` | `3000` | Service port |
| `backend.database.host` | `mysql` | Database host |
| `backend.database.name` | `leave_db` | Database name |
| `backend.autoscaling.enabled` | `true` | Enable HPA |
| `backend.autoscaling.minReplicas` | `2` | Minimum replicas |
| `backend.autoscaling.maxReplicas` | `5` | Maximum replicas |

### MySQL Configuration

| Parameter | Default | Description |
|-----------|---------|-------------|
| `mysql.enabled` | `true` | Enable MySQL deployment |
| `mysql.image.tag` | `8` | MySQL version |
| `mysql.persistence.enabled` | `true` | Enable persistence |
| `mysql.persistence.size` | `1Gi` | Storage size |
| `mysql.persistence.storageClassName` | `` | Storage class (uses default) |

### Ingress Configuration

| Parameter | Default | Description |
|-----------|---------|-------------|
| `ingress.enabled` | `true` | Enable ingress |
| `ingress.className` | `alb` | Ingress class |
| `ingress.host` | `leave.example.com` | Hostname |
| `ingress.annotations` | ALB config | AWS ALB annotations |

### Secrets Management

Two approaches are supported:

#### 1. Embedded Secrets (Development/Testing)

```yaml
backend:
  secrets:
    externalSecrets: false
    inline:
      dbUser: root
      dbPassword: root
      jwtSecret: super-secure-jwt-secret-key
      rootPassword: root
```

#### 2. External Secrets (Production) ⭐

```yaml
backend:
  secrets:
    externalSecrets: true
    externalSecretsName: leave-secrets-production
```

For production, use AWS Secrets Manager with External Secrets addon:

```bash
# Install External Secrets addon
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets -n external-secrets-system

# Create SecretStore
kubectl apply -f k8s-addational/eso-store.yaml
kubectl apply -f k8s-addational/eso-secret.yaml
```

## Customization

### Custom Image Registry

```bash
helm install leave-system ./helm-chart \
  --set backend.image.repository=your-registry.azurecr.io/backend \
  --set frontend.image.repository=your-registry.azurecr.io/frontend
```

### Custom Storage Class

```bash
helm install leave-system ./helm-chart \
  --set mysql.persistence.storageClassName=fast-ssd
```

### Disable Components

```bash
helm install leave-system ./helm-chart \
  --set mysql.enabled=false \
  --set ingress.enabled=false
```

## Upgrading

```bash
# Update values and upgrade
helm upgrade leave-system ./helm-chart \
  -f helm-chart/values.yaml \
  -f helm-chart/values-prod.yaml
```

## Troubleshooting

### Check Deployment Status

```bash
# Overall status
kubectl get all -n production -l app.kubernetes.io/instance=leave-system

# Pod logs
kubectl logs -n production -l component=backend
kubectl logs -n production -l component=frontend
kubectl logs -n production -l component=mysql

# Describe pods for events
kubectl describe pod -n production -l component=backend
```

### Check Ingress Status

```bash
kubectl get ingress -n production
kubectl describe ingress leave-system-ingress -n production
```

### Database Connectivity Issues

```bash
# Test MySQL connectivity from backend pod
kubectl run -it --rm debug --image=mysql:8 -- \
  mysql -h mysql -u root -p<password> -e "SELECT 1"
```

### Check HPA Status

```bash
kubectl get hpa -n production
kubectl describe hpa leave-system-backend-hpa -n production
```

## Best Practices for GitOps

1. **Store sensitive data externally**: Use AWS Secrets Manager or HashiCorp Vault
2. **Use sealed-secrets or external-secrets**: Never commit plain text secrets
3. **Version control values**: Commit environment-specific values files
4. **Use ArgoCD for deployments**: Leverage Git as single source of truth
5. **Monitor deployments**: Use the included observability stack (Prometheus, Loki, Tempo)
6. **Health checks**: Define proper liveness and readiness probes
7. **Resource quotas**: Set requests and limits for all containers

## Example ArgoCD Integration

See `argocd/application.yaml` for a complete ArgoCD Application example.

## Contributing

To modify the chart:
1. Update `Chart.yaml` for version bumps
2. Modify templates in `templates/` directory
3. Update `values.yaml` with new parameters
4. Update this README with new configuration options

## Support

For issues or questions:
- Check K8s events: `kubectl describe pod <pod-name>`
- Review pod logs: `kubectl logs <pod-name>`
- Check chart syntax: `helm lint ./helm-chart`
- Dry-run installation: `helm install --dry-run --debug leave-system ./helm-chart`

## License

Same as the main project.
