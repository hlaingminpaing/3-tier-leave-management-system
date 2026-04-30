# Helm Chart Quick Reference

## 📁 Project Structure

```
helm-chart/
├── Chart.yaml                          # Chart metadata (name, version, description)
├── values.yaml                         # Default values (base configuration)
├── values-dev.yaml                     # Development environment overrides
├── values-staging.yaml                 # Staging environment overrides
├── values-prod.yaml                    # Production environment overrides
├── .helmignore                         # Files to exclude from packaging
├── README.md                           # Complete Helm chart documentation
├── DEPLOYMENT_GUIDE.md                 # Step-by-step deployment instructions
├── GITOPS_BEST_PRACTICES.md            # GitOps workflow and security guide
├── argocd-application-example.yaml     # ArgoCD application definitions
│
└── templates/                          # Kubernetes manifests (Go templates)
    ├── _helpers.tpl                    # Helper functions for templates
    ├── NOTES.txt                       # Post-installation instructions
    ├── serviceaccount.yaml             # Service account for RBAC
    ├── secrets.yaml                    # Secrets for DB credentials
    ├── backend-deployment.yaml         # Backend application pod
    ├── backend-service.yaml            # Backend service
    ├── backend-hpa.yaml                # Horizontal Pod Autoscaler
    ├── frontend-deployment.yaml        # Frontend application pod
    ├── frontend-service.yaml           # Frontend service
    ├── mysql-deployment.yaml           # Database pod
    ├── mysql-service.yaml              # Database service
    ├── mysql-pvc.yaml                  # Persistent Volume Claim
    └── ingress.yaml                    # AWS ALB Ingress
```

## 🚀 Quick Commands

### Installation

```bash
# Development
helm install leave-system ./helm-chart -f helm-chart/values-dev.yaml

# Staging
helm install leave-system ./helm-chart -f helm-chart/values-staging.yaml -n staging

# Production (GitOps)
helm install leave-system ./helm-chart -f helm-chart/values-prod.yaml -n production
```

### Validation

```bash
# Lint chart
helm lint ./helm-chart

# Dry-run
helm install --dry-run --debug leave-system ./helm-chart -f helm-chart/values-dev.yaml

# Template preview
helm template leave-system ./helm-chart -f helm-chart/values-dev.yaml
```

### Management

```bash
# Upgrade release
helm upgrade leave-system ./helm-chart -f helm-chart/values-prod.yaml -n production

# Rollback to previous version
helm rollback leave-system -n production

# List releases
helm list -n production

# Get values used
helm get values leave-system -n production

# See deployed manifests
helm get manifest leave-system -n production
```

## 🔧 Configuration Matrix

| Environment | Replicas | Resources | HPA | External Secrets | Ingress |
|------------|----------|-----------|-----|------------------|---------|
| **Dev** | 1 | Low (minimal) | ❌ | ❌ | ❌ |
| **Staging** | 2 | Medium | ✅ (2-3) | ✅ (recommended) | ✅ |
| **Prod** | 3+ | High | ✅ (3-10) | ✅ (required) | ✅ |

## 📋 Key Components

### Frontend
- **Image**: `ghcr.io/hlaingminpaing/3-tier-leave-management-system/frontend`
- **Port**: 80
- **Purpose**: React/Vite web application
- **Probes**: HTTP liveness & readiness

### Backend
- **Image**: `ghcr.io/hlaingminpaing/3-tier-leave-management-system/backend`
- **Ports**: 3000 (API), 9464 (Metrics)
- **Purpose**: Express.js API server
- **Features**: OpenTelemetry instrumentation, auto-scaling
- **Probes**: HTTP liveness & readiness

### MySQL
- **Image**: `mysql:8`
- **Port**: 3306
- **Purpose**: Primary database
- **Storage**: Persistent Volume Claim
- **Stategy**: Recreate (single instance with persistence)

## 🎛️ Configuration Examples

### Change Image Tag

```yaml
# values-prod.yaml
backend:
  image:
    tag: v1.2.3
frontend:
  image:
    tag: v1.2.3
```

### Scale Backend Replicas

```yaml
backend:
  autoscaling:
    minReplicas: 5
    maxReplicas: 20
```

### Customize Storage

```yaml
mysql:
  persistence:
    size: 100Gi
    storageClassName: fast-ssd
```

### Enable Network Policies

```yaml
networkPolicies:
  enabled: true
```

### Use External Registry

```bash
helm install leave-system ./helm-chart \
  --set backend.image.repository=my-registry.com/backend \
  --set frontend.image.repository=my-registry.com/frontend
```

## 🔐 Secrets Management

### Development (Inline)
```yaml
backend:
  secrets:
    externalSecrets: false
    inline:
      dbUser: root
      dbPassword: root
      jwtSecret: dev-secret
      rootPassword: root
```

### Production (External)
```yaml
backend:
  secrets:
    externalSecrets: true
    externalSecretsName: leave-secrets-production
```

**Setup External Secrets**:
```bash
# 1. Install External Secrets addon
helm install external-secrets external-secrets/external-secrets -n external-secrets-system

# 2. Create AWS secret
aws secretsmanager create-secret --name leave-system/production --secret-string {...}

# 3. Apply External Secrets definition
kubectl apply -f k8s-addational/eso-store.yaml
kubectl apply -f k8s-addational/eso-secret.yaml
```

## 📊 Monitoring

```bash
# Check pod status
kubectl get pods -n production -l app.kubernetes.io/instance=leave-system

# View logs
kubectl logs -n production -l component=backend -f

# Check HPA metrics
kubectl get hpa -n production
kubectl top pods -n production

# Monitor ingress
kubectl get ingress -n production
kubectl describe ingress leave-system-ingress -n production
```

## 🐛 Troubleshooting

| Issue | Command |
|-------|---------|
| **Pods not starting** | `kubectl describe pod -n production <pod-name>` |
| **CrashLoopBackOff** | `kubectl logs -n production <pod-name> --previous` |
| **Pending PVC** | `kubectl describe pvc -n production` |
| **Ingress not working** | `kubectl describe ingress -n production` |
| **DB connection fails** | `kubectl exec -it <backend-pod> -- curl http://mysql:3306` |
| **Secret issues** | `kubectl get secret -n production; kubectl describe secret -n production <secret>` |

## 🔄 GitOps with ArgoCD

```bash
# Create ArgoCD Application
kubectl apply -f helm-chart/argocd-application-example.yaml

# Monitor sync
argocd app get leave-system-prod
argocd app sync leave-system-prod

# View diff
argocd app diff leave-system-prod

# Rollback
argocd app rollback leave-system-prod
```

## 📚 Documentation Files

| File | Purpose |
|------|---------|
| **README.md** | Complete chart documentation, configuration options |
| **DEPLOYMENT_GUIDE.md** | Step-by-step deployment for all environments |
| **GITOPS_BEST_PRACTICES.md** | GitOps workflows, security, and operations |
| **argocd-application-example.yaml** | Ready-to-use ArgoCD application definitions |
| **NOTES.txt** | Post-installation tips (shown after helm install) |

## 🔗 File References

### Frontend Configuration
- Container image & tag
- Resource requests/limits
- Environment variables
- Service type and port

### Backend Configuration
- Container image & tag
- Resource requests/limits
- Database connection details
- JWT secret management
- OpenTelemetry configuration
- Auto-scaling parameters

### Database Configuration
- MySQL version and image
- Persistent storage size
- Service type (headless)
- Security context

## ✅ Validation Checklist

Before deploying to production:

- [ ] Chart lints without errors: `helm lint ./helm-chart`
- [ ] Templates render correctly: `helm template leave-system ./helm-chart`
- [ ] All required secrets are configured
- [ ] External Secrets addon is installed (production)
- [ ] AWS ALB Ingress Controller is installed (production)
- [ ] ACM certificate ARN is set in ingress annotations
- [ ] Values-prod.yaml has no hardcoded secrets
- [ ] Resource requests and limits are defined
- [ ] Health checks (liveness/readiness) are configured
- [ ] Database persistence is enabled
- [ ] BackUp strategy is in place
- [ ] Monitoring is configured (optional)

## 🎓 Next Steps

1. **Read** [README.md](README.md) for detailed configuration options
2. **Review** [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) for step-by-step deployment
3. **Understand** [GITOPS_BEST_PRACTICES.md](GITOPS_BEST_PRACTICES.md) for GitOps workflows
4. **Customize** values YAML files for your environments
5. **Test** with `helm template` and `--dry-run`
6. **Deploy** using appropriate values file for environment
7. **Monitor** deployments and scale as needed
8. **Iterate** using GitOps principles with ArgoCD

## 💡 Pro Tips

- 🔒 Never commit production secrets to Git
- 🔄 Use values files for environment-specific configs
- 📊 Monitor HPA metrics to understand scaling behavior
- 🔍 Use `helm diff` plugin to preview changes
- 🚀 Start with dev environment before production
- 📈 Gradually increase replicas/resources as load grows
- 🛡️ Regular backups of ArgoCD and Git repository
- 🔐 Use Sealed Secrets or External Secrets for sensitive data
