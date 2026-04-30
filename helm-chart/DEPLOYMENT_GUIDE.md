# HELM CHART DEPLOYMENT GUIDE
# Complete guide for deploying the Leave Management System using Helm

## 📋 Prerequisites

- Kubernetes 1.19+ cluster
- Helm 3.0+ installed
- kubectl configured to access your cluster
- For production: AWS ALB Ingress Controller
- For production: External Secrets addon

## 🚀 Quick Start

### 1. Local Testing

```bash
# Validate the chart
helm lint ./helm-chart

# See generated manifests
helm template leave-system ./helm-chart \
  -f helm-chart/values.yaml \
  -f helm-chart/values-dev.yaml

# Dry-run installation
helm install leave-system ./helm-chart \
  -f helm-chart/values.yaml \
  -f helm-chart/values-dev.yaml \
  --dry-run --debug
```

### 2. Install in Development

```bash
# Create namespace
kubectl create namespace default

# Install chart with dev values
helm install leave-system ./helm-chart \
  -f helm-chart/values.yaml \
  -f helm-chart/values-dev.yaml \
  -n default

# Monitor deployment
kubectl get pods -n default -w

# Get logs
kubectl logs -n default -l component=backend -f
kubectl logs -n default -l component=frontend -f
```

### 3. Install in Staging

```bash
# Create namespace
kubectl create namespace staging

# Install chart with staging values
helm install leave-system ./helm-chart \
  -f helm-chart/values.yaml \
  -f helm-chart/values-staging.yaml \
  -n staging

# Verify deployment
kubectl rollout status deployment/leave-system-backend -n staging
kubectl get svc -n staging
kubectl get ingress -n staging
```

### 4. Install in Production

#### Step 1: Setup External Secrets (Recommended)

```bash
# Install External Secrets addon
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets external-secrets/external-secrets \
  -n external-secrets-system \
  --create-namespace

# Store secrets in AWS Secrets Manager
aws secretsmanager create-secret \
  --name leave-system/production \
  --secret-string '{
    "db-user": "prod_user",
    "db-password": "secure-password",
    "jwt-secret": "secure-jwt-secret",
    "root-password": "secure-root-password",
    "db-host": "mysql",
    "db-name": "leave_db"
  }'

# Apply External Secrets configuration
kubectl apply -f k8s-addational/eso-store.yaml
kubectl apply -f k8s-addational/eso-secret.yaml
```

#### Step 2: Setup AWS ALB Ingress Controller

```bash
# Add AWS EKS addon (if using EKS)
aws eks create-addon \
  --cluster-name my-cluster \
  --addon-name aws-load-balancer-controller

# Or install manually
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=my-cluster
```

#### Step 3: Update Production Values

Edit `helm-chart/values-prod.yaml`:

```yaml
ingress:
  enabled: true
  annotations:
    alb.ingress.kubernetes.io/certificate-arn: "arn:aws:acm:us-east-1:123456789:certificate/abc123"
  host: "leave.example.com"

backend:
  secrets:
    externalSecrets: true
    externalSecretsName: leave-secrets-production
```

#### Step 4: Create Production Namespace

```bash
kubectl create namespace production
```

#### Step 5: Install in Production

```bash
helm install leave-system ./helm-chart \
  -f helm-chart/values.yaml \
  -f helm-chart/values-prod.yaml \
  -n production

# Verify
kubectl get all -n production
kubectl get ingress -n production
```

## 📊 GitOps Deployment with ArgoCD

### 1. Install ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Visit: https://localhost:8080
# Default user: admin
# Password: (get with) kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### 2. Create ArgoCD Application

```bash
# Update the repository URL in argocd-application-example.yaml
kubectl apply -f helm-chart/argocd-application-example.yaml

# Or create via CLI
argocd app create leave-system-prod \
  --repo https://github.com/your-org/3tier-leave-system \
  --path helm-chart \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace production \
  --values values.yaml \
  --values values-prod.yaml \
  --auto-prune \
  --self-heal
```

### 3. Sync Application

```bash
# Manual sync
argocd app sync leave-system-prod

# Monitor sync
argocd app wait leave-system-prod

# View app status
argocd app get leave-system-prod
```

## 🔄 Updating Deployments

### Update Image Tag

Edit `values-prod.yaml`:

```yaml
backend:
  image:
    tag: sha-newversion

frontend:
  image:
    tag: sha-newversion
```

Commit and push to Git:

```bash
git add helm-chart/values-prod.yaml
git commit -m "Update images to sha-newversion"
git push
```

ArgoCD will automatically detect and sync if auto-refresh is enabled.

### Update Resource Limits

```yaml
backend:
  resources:
    requests:
      cpu: "500m"
      memory: "512Mi"
    limits:
      cpu: "1000m"
      memory: "1Gi"
```

### Scale Replicas

```yaml
backend:
  autoscaling:
    minReplicas: 5
    maxReplicas: 15
```

### Upgrade Helm Release

```bash
# Upgrade with new values
helm upgrade leave-system ./helm-chart \
  -f helm-chart/values.yaml \
  -f helm-chart/values-prod.yaml \
  -n production

# Rollback if needed
helm rollback leave-system -n production
```

## 🔍 Troubleshooting

### Check Chart Syntax

```bash
helm lint ./helm-chart
```

### Validate Rendered Templates

```bash
helm template leave-system ./helm-chart \
  -f helm-chart/values.yaml \
  -f helm-chart/values-prod.yaml | kubectl apply --dry-run=client -f -
```

### Check Deployment Status

```bash
kubectl rollout status deployment/leave-system-backend -n production

# View events
kubectl get events -n production --sort-by='.lastTimestamp'

# Describe pod
kubectl describe pod -n production -l component=backend
```

### Check Logs

```bash
# Backend logs
kubectl logs -n production -l component=backend -f

# Frontend logs
kubectl logs -n production -l component=frontend -f

# MySQL logs
kubectl logs -n production -l component=mysql -f

# Previous/failed pod logs
kubectl logs -n production -l component=backend --previous
```

### Check Ingress Status

```bash
kubectl describe ingress -n production leave-system-ingress

# Check ALB details
aws elbv2 describe-load-balancers | grep -i leave
```

### Database Connection Issues

```bash
# Test MySQL from inside cluster
kubectl run -it --rm debug --image=mysql:8 -n production -- \
  mysql -h leave-system-mysql -u root -p<password> -e "SELECT 1"

# Check Service DNS
kubectl run -it --rm debug --image=busybox -n production -- \
  nslookup leave-system-mysql
```

### Check HPA Status

```bash
kubectl get hpa -n production
kubectl describe hpa leave-system-backend-hpa -n production
kubectl get hpa leave-system-backend-hpa -n production -w  # Watch metrics
```

### Secret Issues

```bash
# Check if secrets are created
kubectl get secrets -n production

# Verify secret content (for debugging only)
kubectl get secret leave-system-secrets -n production -o yaml

# Check external secrets status
kubectl get externalsecret -n production
kubectl describe externalsecret leave-system-secrets -n production
```

## 🛡️ Security Best Practices

### 1. Never Commit Secrets

Ensure `.gitignore` includes:
```
values-secrets.yaml
secrets/
.env
*.pem
```

### 2. Use External Secrets in Production

```yaml
backend:
  secrets:
    externalSecrets: true
    externalSecretsName: leave-secrets-production
```

### 3. Enable Pod Security Policies

```bash
kubectl apply -f k8s-addational/network-policies.yaml
```

### 4. Setup Network Policies

Network policies are defined in templates and can be enabled:

```yaml
networkPolicies:
  enabled: true
```

### 5. Use Private Container Registries

```bash
helm install leave-system ./helm-chart \
  --set backend.image.repository=private-registry/backend \
  --set frontend.image.repository=private-registry/frontend \
  --set imageCredentials.create=true \
  --set imageCredentials.registry=private-registry \
  --set imageCredentials.username=user \
  --set imageCredentials.password=pass
```

## 📈 Monitoring

Monitor your deployments with:

```bash
# Pod metrics
kubectl top pods -n production

# Node metrics
kubectl top nodes

# Persistent Volume usage
kubectl get pv
kubectl describe pv

# HPA metrics in real-time
kubectl get hpa -n production -w
```

## 📝 Helm Chart Maintenance

### Update Chart Version

Edit `Chart.yaml`:

```yaml
version: 1.1.0  # Bump version
appVersion: "1.1.0"  # Update app version
```

### Package Chart

```bash
helm package ./helm-chart
# Creates: leave-management-system-1.0.0.tgz

# Upload to Helm repository
# (if hosting privately)
```

## 🆘 Getting Help

1. Check chart syntax: `helm lint ./helm-chart`
2. Dry-run templates: `helm template leave-system ./helm-chart --debug`
3. Review ArgoCD logs: `kubectl logs -n argocd deployment/argocd-application-controller`
4. Check Kubernetes events: `kubectl get events -n production`
5. Review application-specific logs via `kubectl logs`
