# GitOps Best Practices for Leave Management System

This document outlines best practices for using Helm and ArgoCD with the leave management system.

## 🎯 Core GitOps Principles

1. **Declarative Infrastructure**: All infrastructure is defined in Git
2. **Single Source of Truth**: Git is the authoritative source
3. **Automated Deployment**: Changes in Git are automatically synchronized to the cluster
4. **Audit Trail**: All changes are tracked in Git history

## 📂 Repository Structure for GitOps

```
3tier-leave-system/
├── helm-chart/
│   ├── Chart.yaml
│   ├── values.yaml              # Base values
│   ├── values-dev.yaml          # Development overrides
│   ├── values-staging.yaml      # Staging overrides
│   ├── values-prod.yaml         # Production overrides
│   ├── templates/
│   │   └── [template files]
│   ├── README.md
│   ├── DEPLOYMENT_GUIDE.md
│   └── argocd-application-example.yaml
├── argocd/
│   ├── application.yaml         # ArgoCD App definition
│   └── applicationset.yaml      # (optional) Multi-env app management
├── k8s/                         # Original YAML (kept for reference)
│   └── [...]
└── README.md                    # Project README
```

## 🔐 Secrets Management Strategy

### Development Environment
- **Method**: Inline secrets in values-dev.yaml
- **Risk Level**: Low (local testing only)
- **Example**:
```yaml
backend:
  secrets:
    inline:
      dbPassword: "devpass"
```

### Staging Environment
- **Method**: External Secrets + AWS Secrets Manager
- **Risk Level**: Medium
- **Setup**:
```bash
# Create secret in AWS
aws secretsmanager create-secret \
  --name leave-system/staging \
  --secret-string '{"db-password":"..."}'

# Apply External Secrets definition
kubectl apply -f k8s-addational/eso-store.yaml
kubectl apply -f k8s-addational/eso-secret.yaml
```

### Production Environment
- **Method**: Sealed Secrets or External Secrets + AWS Secrets Manager ⭐
- **Risk Level**: High (must be fully secured)
- **Implementation**:
```yaml
backend:
  secrets:
    externalSecrets: true
    externalSecretsName: leave-secrets-production
```

**IMPORTANT**: NEVER commit production secrets to Git!

### Sealed Secrets Alternative

If using Sealed Secrets instead of External Secrets:

```bash
# Install sealed-secrets controller
helm repo add sealed-secrets https://charts.sealedsecrets.bitnami.com
helm install sealed-secrets -n kube-system sealed-secrets/sealed-secrets

# Seal a secret
kubectl create secret generic mysecret \
  --dry-run=client \
  -o yaml \
  --from-literal=password=mypassword | \
  kubeseal -f - > mysealedsecret.yaml

# Commit sealed secret to Git
git add mysealedsecret.yaml
```

## 🚀 Multi-Environment Deployment

### Strategy 1: Branch-Based Promotion

```
main (production)
  ↑
staging (staging environment)
  ↑
develop (development environment)
```

**ArgoCD Applications**:
- `leave-system-prod`: watches main branch
- `leave-system-staging`: watches staging branch
- `leave-system-dev`: watches develop branch

**Workflow**:
```bash
# 1. Develop on feature branch
git checkout -b feature/new-feature

# 2. Create PR to develop → auto-deploys to dev
git push origin feature/new-feature

# 3. Merge to develop → ArgoCD syncs dev environment
git checkout develop
git merge feature/new-feature
git push

# 4. After testing, create PR to staging
git checkout -b release/v1.1.0 develop
# Update versions, values-staging.yaml if needed
git push

# 5. After staging approval, merge to main
# This triggers production deployment via ArgoCD
```

### Strategy 2: Tag-Based Promotion

Use Git tags for image versions:

```bash
# Tag for production
git tag -a v1.1.0 -m "Release v1.1.0"
git push origin v1.1.0

# Update values-prod.yaml with new tag
# Example: backend.image.tag: v1.1.0
```

**ArgoCD Application watches**: `targetRevision: "v*"` (latest tag)

### Strategy 3: Kustomize Overlays (Alternative to Multiple Values files)

```
helm-chart/
├── base/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
└── overlays/
    ├── dev/
    │   └── values.yaml
    ├── staging/
    │   └── values.yaml
    └── prod/
        └── values.yaml
```

**ArgoCD Application**:
```yaml
source:
  path: helm-chart/overlays/prod
```

## 🔄 GitOps Workflow

### 1. Local Development Workflow

```bash
# 1. Clone repository
git clone https://github.com/your-org/3tier-leave-system.git
cd 3tier-leave-system

# 2. Make changes to Helm values
vim helm-chart/values-dev.yaml

# 3. Test locally with Helm
helm template leave-system ./helm-chart \
  -f helm-chart/values.yaml \
  -f helm-chart/values-dev.yaml > /tmp/manifests.yaml

# 4. Validate with kubectl dry-run
kubectl apply --dry-run=client -f /tmp/manifests.yaml

# 5. Commit and push
git add helm-chart/values-dev.yaml
git commit -m "Update dev environment configuration"
git push
```

### 2. Pull Request Review Process

Before merging, ensure:
- ✅ Helm chart lint passes: `helm lint ./helm-chart`
- ✅ Template rendering works: `helm template leave-system ./helm-chart --debug`
- ✅ All required fields are set
- ✅ No secrets in values files
- ✅ Security policies respected

### 3. Automatic Sync with ArgoCD

```bash
# ArgoCD continuously monitors Git
# When changes are pushed:

1. ArgoCD detects Git changes (every 3 minutes by default)
2. Re-renders Helm chart with updated values
3. Compares with cluster state
4. Automatically syncs if auto-sync is enabled
5. Updates application status in UI
```

### 4. Manual Control Points

For critical environments, require manual sync:

```yaml
# In argocd-application-example.yaml
syncPolicy:
  automated:
    prune: false      # Require manual approval for deletions
    selfHeal: false   # Manual sync control
```

**Manual sync command**:
```bash
argocd app sync leave-system-prod
```

## 📊 Monitoring Git-to-Cluster Drift

### Using ArgoCD UI
- Open ArgoCD Dashboard
- Click on Application
- View "App Diff" to see cluster vs Git differences

### Using ArgoCD CLI
```bash
# Get diff
argocd app diff leave-system-prod

# Get detailed status
argocd app get leave-system-prod

# Watch for changes
watch -n 5 'argocd app get leave-system-prod'
```

### Using Kubectl
```bash
# Check if deployed resources match Git definitions
kubectl diff -f helm-chart/templates/
```

## 🔒 Access Control with ArgoCD RBAC

```bash
# Create least-privilege service accounts
kubectl create serviceaccount argocd-deployer -n argocd
kubectl create clusterrolebinding argocd-deployer \
  --clusterrole=edit \
  --serviceaccount=argocd:argocd-deployer

# Create ArgoCD RBAC policy
kubectl edit configmap argocd-rbac-cm -n argocd
```

**Example RBAC Policy**:
```
policy.default: 'role:readonly'
policy.csv: |
  p, role:deployer, applications, get, */*, allow
  p, role:deployer, applications, sync, */*, allow
  g, deployer-group, role:deployer
```

## 🛡️ Security Hardening

### 1. Protect Main Branch

- Require code reviews (2 approvals)
- Require CI/CD checks to pass before merge
- Restrict who can merge to main

### 2. Sign Git Commits

```bash
# Configure GPG signing
git config user.signingkey <key-id>
git config commit.gpgsign true

# Make signing mandatory
git commit -S -m "Update production values"
```

### 3. Audit Git Changes

```bash
# View all changes to production values
git log -p helm-chart/values-prod.yaml

# Export audit log
git log --all --oneline helm-chart/values-prod.yaml > audit.log
```

### 4. Image Scanning

Before deploying, scan images for vulnerabilities:

```bash
# Using Trivy
trivy image ghcr.io/hlaingminpaing/3-tier-leave-management-system/backend:sha-e2ac005

# Using Snyk
snyk container test ghcr.io/.../backend:sha-e2ac005
```

### 5. Enable Network Policies

```yaml
networkPolicies:
  enabled: true
```

## 🔔 Notifications and Alerts

### ArgoCD Notifications

```bash
# Install ArgoCD Notifications
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-notifications/release-1.8/manifests/install.yaml

# Configure Slack notifications
kubectl patch configmap argocd-notifications-cm -n argocd \
  --type merge \
  -p '{"data":{"service.slack.token":"xoxb-..."}}'
```

### Git Webhook Notifications

Setup GitHub/GitLab webhooks to notify on:
- Commits to main/staging/develop
- Pull request merges
- Tag creation

## 📈 Metrics and Observability

### Track ArgoCD Metrics

```bash
# Port-forward to Prometheus
kubectl port-forward -n argocd svc/argocd-metrics 8082:8082

# Common metrics:
# argocd_app_sync_total - Total syncs performed
# argocd_app_reconcile_duration_seconds - Reconciliation time
# argocd_git_request_total - Git API requests
```

### Dashboard Example (Grafana)

Query: `argocd_app_info{name="leave-system-prod"}`

Shows:
- Last sync time
- Sync status
- Resource count
- Health status

## 🆘 Disaster Recovery

### Backup Strategy

```bash
# Backup ArgoCD Application definitions
kubectl get applications -n argocd -o yaml > argocd-apps-backup.yaml

# Backup Git repository
git clone --mirror https://github.com/your-org/3tier-leave-system.git backup.git

# Backup cluster state
velero backup create leave-system-backup
```

### Restore from Git

If cluster crashes, Git is the source of truth:

```bash
# 1. Create new cluster
# 2. Install ArgoCD
# 3. Point to Git repository
# 4. All resources recreated automatically
```

### Rollback Procedure

```bash
# 1. Identify problematic commit
git log --oneline helm-chart/values-prod.yaml

# 2. Revert commit
git revert <commit-hash>
git push

# 3. ArgoCD automatically syncs old version
# Or manually trigger
argocd app sync leave-system-prod

# 4. Verify
argocd app get leave-system-prod
```

## ✅ Helm Chart Versioning

Follow semantic versioning:

```yaml
# Chart.yaml
version: 1.1.0          # Chart version (Chart changes)
appVersion: "1.1.0"     # Application version (App changes)
```

**When to bump**:
- `PATCH` (1.0.1): Fix in chart template, no functional change
- `MINOR` (1.1.0): New feature in chart, backward compatible
- `MAJOR` (2.0.0): Breaking changes, incompatible configuration

## 📚 Useful Commands

```bash
# Lint chart
helm lint ./helm-chart

# Test chart rendering
helm template leave-system ./helm-chart \
  -f values.yaml -f values-prod.yaml

# Validate against Kube schema
helm template leave-system ./helm-chart | kubectl apply --dry-run=client -f -

# Check diff before upgrade
helm diff upgrade leave-system ./helm-chart -n production

# See what ArgoCD sees
argocd app manifests leave-system-prod

# Force sync even if healthy
argocd app sync leave-system-prod --force

# Watch sync progress
kubectl get events -n argocd -w
```

## 🎓 Learning Resources

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Helm Best Practices](https://helm.sh/docs/chart_best_practices/)
- [GitOps Best Practices](https://www.weave.works/technologies/gitops/)
- [Sealed Secrets Documentation](https://github.com/bitnami-labs/sealed-secrets)
- [External Secrets Operator](https://external-secrets.io/)

## 🚦 Troubleshooting GitOps Issues

### ArgoCD not syncing Git changes

```bash
# Check sync status
argocd app get leave-system-prod

# Force refresh
argocd app refresh leave-system-prod

# Check ArgoCD logs
kubectl logs -n argocd deployment/argocd-application-controller -f
```

### Values not being applied

```bash
# Check which values files are being used
argocd app get leave-system-prod

# View rendered manifests
argocd app manifests leave-system-prod | head -50

# Check if values file exists in Git
git ls-tree -r main helm-chart/values-prod.yaml
```

### Helm template errors

```bash
# Debug locally
helm template leave-system ./helm-chart --debug

# Check template syntax
helm lint ./helm-chart

# Validate required values
helm template leave-system ./helm-chart \
  -f values.yaml -f values-prod.yaml \
  --validate
```
