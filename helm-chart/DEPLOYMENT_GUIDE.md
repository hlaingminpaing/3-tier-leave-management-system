# HELM CHART DEPLOYMENT GUIDE
# Complete guide for deploying the Leave Management System using Helm

## 📋 Prerequisites

- Kubernetes 1.19+ cluster
- Helm 3.0+ installed
- kubectl configured to access your cluster
- `kubeseal` CLI installed locally (for Sealed Secrets encryption)
- For production: AWS ALB Ingress Controller
- For production secrets: Sealed Secrets controller in `kube-system` (see below)

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

#### Step 1: Install Sealed Secrets Controller

Sealed Secrets runs in `kube-system` and holds the RSA private key used to decrypt
secrets. The public key is safe to commit to Git and used by developers/CI to encrypt.

```bash
# Add the Bitnami sealed-secrets chart repo
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update

# Install controller in kube-system namespace
helm install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system \
  --set fullnameOverride=sealed-secrets-controller

# Verify controller is running
kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets
```

#### Step 2: Fetch the Public Certificate

```bash
# Fetch and save the cluster's public certificate
kubeseal --fetch-cert \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=kube-system \
  > pub-sealed-secrets.pem

# Commit this cert to your repo (it is safe to share)
git add pub-sealed-secrets.pem
git commit -m "chore: add sealed secrets public certificate"
```

#### Step 3: Encrypt Your Production Secrets

```bash
# Create a temporary plain secret (do NOT commit this file)
cat > /tmp/leave-plain-secret.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: leave-system-leave-management-system-secrets
  namespace: production
type: Opaque
stringData:
  db-user: prod_db_user
  db-password: YourStrongPassword123!
  jwt-secret: YourVeryLongJWTSecretKeyHere!!
  root-password: YourStrongRootPassword123!
  db-host: leave-system-leave-management-system-mysql
  db-name: leave_db
EOF

# Encrypt with kubeseal
kubeseal \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=kube-system \
  --format=yaml \
  < /tmp/leave-plain-secret.yaml

# The output will contain encryptedData keys — copy them into values-prod.yaml
```

#### Step 4: Update `values-prod.yaml` with Encrypted Values

```yaml
# helm-chart/values-prod.yaml
backend:
  secrets:
    externalSecrets: false
    sealedSecrets: true
    sealedSecretsData:
      db-user: AgB...        # paste kubeseal output here
      db-password: AgB...    # paste kubeseal output here
      jwt-secret: AgB...     # paste kubeseal output here
      root-password: AgB...  # paste kubeseal output here
      db-host: AgB...        # paste kubeseal output here
      db-name: AgB...        # paste kubeseal output here
```

> 📖 For detailed instructions, see **[SEALED_SECRETS_SETUP.md](./SEALED_SECRETS_SETUP.md)**

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

#### Step 5: Update Production Ingress Values

Edit `helm-chart/values-prod.yaml`:

```yaml
ingress:
  enabled: true
  annotations:
    alb.ingress.kubernetes.io/certificate-arn: "arn:aws:acm:us-east-1:123456789:certificate/abc123"
  host: "leave.example.com"
```

#### Step 6: Create Production Namespace

```bash
kubectl create namespace production
```

#### Step 7: Install in Production

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
# Check if the SealedSecret exists
kubectl get sealedsecret -n production

# Check SealedSecret status and events
kubectl describe sealedsecret leave-system-leave-management-system-secrets -n production

# Check controller logs for decryption errors
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets

# Verify the resulting plain Secret was created
kubectl get secret -n production | grep leave-management

# Check secret content (for debugging only)
kubectl get secret leave-system-leave-management-system-secrets -n production -o yaml
```

Common errors:
- `no key could decrypt` → SealedSecret was encrypted for a different cluster. Re-encrypt.
- `namespace mismatch` → Ensure the plain secret's `namespace` matches the target namespace before encrypting.
- Controller not running → `kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets`

## 🛡️ Security Best Practices

### 1. Never Commit Secrets

Ensure `.gitignore` includes:
```
values-secrets.yaml
secrets/
.env
*.pem
```

### 2. Use Sealed Secrets in Production

Seal your secrets with `kubeseal` before committing to Git:

```bash
kubeseal \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=kube-system \
  --format=yaml \
  < plain-secret.yaml
# Copy encryptedData values into values-prod.yaml -> backend.secrets.sealedSecretsData
```

See [SEALED_SECRETS_SETUP.md](./SEALED_SECRETS_SETUP.md) for full details.

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
