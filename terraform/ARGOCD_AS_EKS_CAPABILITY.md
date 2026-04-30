# ArgoCD as EKS Capability - Architecture Guide

## Overview

This Terraform configuration uses **ArgoCD as an EKS Capability** - a new approach where ArgoCD is integrated directly into the EKS cluster infrastructure rather than deployed as a separate component.

## What Changed

### Before (Separate Module)
```
EKS Cluster
    ↓
(Optional) ArgoCD Module
    ↓
    └─→ Helm Release (argocd chart)
    └─→ Kubernetes Namespace
    └─→ Secrets & ConfigMaps
```

**Issues**: Separate lifecycle, IRSA configuration complexity, ALB setup delays

### After (EKS Capability)
```
EKS Cluster
    ├─→ Core Infrastructure
    ├─→ Node Groups
    ├─→ OIDC Provider
    └─→ ArgoCD (Capability)
        ├─→ Helm Release (automatic)
        ├─→ Kubernetes Namespace (auto-created)
        ├─→ ALB Ingress (integrated)
        ├─→ IRSA Support (built-in)
        └─→ CloudWatch Logs (unified)
```

**Benefits**: Unified management, automatic integration, simplified deployment

## Architecture

### 1. Cluster Creation

```hcl
module "eks" {
  source = "./modules/eks"
  
  # Standard EKS config
  cluster_name = "leave-system-dev"
  kubernetes_version = "1.35"
  
  # ArgoCD as capability
  enable_argocd = true
  argocd_namespace = "argocd"
  argocd_version = "7.0.0"
}
```

### 2. Automatic Components

When cluster is created, the following are automatically:

```
✓ ArgoCD namespace created
✓ Helm repository added
✓ ArgoCD Helm chart installed
✓ Default admin password set
✓ ALB Ingress configured (optional)
✓ Service accounts created
✓ RBAC policies applied
```

### 3. Integration Points

```
EKS → OIDC Provider → IAM Roles
        ↓
    Pod Identity
        ↓
    Service Accounts
        ↓
    AWS Services (ALB, ECR, etc.)
```

## Configuration

### Basic Configuration

```hcl
# terraform.tfvars

enable_argocd = true
argocd_namespace = "argocd"
argocd_version = "7.0.0"
enable_argocd_ingress = true
argocd_ingress_hostname = "argocd.example.com"
```

### With GitHub Integration

```hcl
enable_argocd = true
github_token = "ghp_xxxxxxxxxxxx"
github_username = "my-username"
github_repo_url = "https://github.com/org/repo"
```

## Deployment Flow

### Step 1: Initialize
```bash
cd terraform
terraform init
```

### Step 2: Review Plan
```bash
terraform plan
```

### Step 3: Apply (Everything Together)
```bash
terraform apply
```

This single command:
1. Creates VPC and subnets
2. Sets up security groups and IAM
3. Deploys EKS cluster
4. **Creates ArgoCD namespace**
5. **Installs ArgoCD via Helm**
6. **Configures ingress**
7. **Sets up credentials**

### Step 4: Verify

```bash
kubectl get namespaces | grep argocd
kubectl get pods -n argocd
kubectl get svc -n argocd
```

## Access Patterns

### Development

```bash
# Port forward for local testing
kubectl port-forward -n argocd svc/argocd-server 8080:443

# Access at https://localhost:8080
# Credentials: admin / leave-system@dev
```

### Production

```bash
# Via ALB Ingress
kubectl get ingress -n argocd
# Add DNS record pointing to ALB

# Access at https://argocd.yourdomain.com
```

## Key Advantages

### 1. Unified Deployment
- Single terraform apply command
- All components deployed together
- Consistent versioning

### 2. Better Integration
- Automatic OIDC configuration
- ALB ingress pre-configured
- Service mesh ready

### 3. Simplified Management
- Cluster and ArgoCD have same lifecycle
- Easier to version control
- Cleaner Terraform code

### 4. Enhanced Security
- IRSA automatically configured
- Service accounts created with proper roles
- Network policies aligned

### 5. Cost Efficiency
- No separate infrastructure
- Shared Kubernetes cluster
- Optimized resource allocation

## Scaling

### Horizontal Scaling

```yaml
# ArgoCD dynamically scales with workload
# Supports multiple applications
# Handles large repositories
```

### Vertical Scaling

```hcl
# Adjust node resources
instance_type = "t3.large"    # Upgrade from t3.medium
desired_capacity = 5          # Add more nodes
max_capacity = 20             # Increase max
```

## Monitoring & Logging

### CloudWatch Logs

```bash
# View EKS cluster logs
aws logs tail /aws/eks/leave-system-dev/cluster --follow

# Filter for ArgoCD
aws logs filter-log-events \
  --log-group-name /aws/eks/leave-system-dev/cluster \
  --filter-pattern "argocd"
```

### Kubernetes Metrics

```bash
kubectl top nodes
kubectl top pods -n argocd

# More detailed metrics
kubectl describe pod -n argocd <pod-name>
```

### ArgoCD Metrics

```bash
# Port forward to metrics
kubectl port-forward -n argocd svc/argocd-metrics 8083:8083

# Endpoints available
# Server metrics: :8083/metrics
# Repo server metrics: :8084/metrics
# Controller metrics: :8085/metrics
```

## Troubleshooting

### ArgoCD not starting

```bash
# Check logs
kubectl logs -n argocd deployment/argocd-server

# Check PVCs
kubectl get pvc -n argocd

# Check node status
kubectl get nodes
```

### Ingress not working

```bash
# Verify ingress
kubectl get ingress -n argocd

# Check ALB controller
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Describe ingress
kubectl describe ingress -n argocd argocd-server
```

### OIDC Provider issues

```bash
# Verify OIDC provider
aws iam list-open-id-connect-providers

# Check service account
kubectl get sa -n argocd

# Verify IRSA configuration
kubectl describe pod -n argocd <pod-name>
```

## Upgrading

### Upgrade ArgoCD Version

```hcl
# Update terraform.tfvars
argocd_version = "7.1.0"
```

```bash
# Apply update
terraform plan
terraform apply
```

### Upgrade Kubernetes

```hcl
# Update terraform.tfvars
kubernetes_version = "1.36"
```

```bash
# This will update the control plane first, then nodes
terraform plan
terraform apply
```

## Rollback

### Rollback ArgoCD

```bash
# If something goes wrong
helm rollback argocd -n argocd
```

### Rollback Cluster

```bash
# Terraform maintains state for easy rollback
terraform state list
terraform state show module.eks
```

## Best Practices

1. **Version Control**: Keep terraform.tfvars in git (without secrets)
2. **State Management**: Use S3 backend with locking
3. **Test Changes**: Always run terraform plan first
4. **Monitor**: Set up CloudWatch alarms
5. **Backup**: Regular EBS snapshots and etcd backups
6. **Security**: Use AWS Secrets Manager for sensitive data
7. **Scalability**: Plan node capacity ahead of time

## Comparison with Other Approaches

### vs. Manual installation
- ✅ Infrastructure as code
- ✅ Reproducible
- ✅ Versioned
- ✅ Automated

### vs. EKS Blueprints (preview)
- ✅ Simpler
- ✅ Custom + modular
- ✅ Clear and straightforward
- ✅ AWS provides official best practices

### vs. Helm charts only
- ✅ Not just application deployment
- ✅ Full infrastructure management
- ✅ AWS integration built-in
- ✅ Lifecycle management

## Migration Path

If migrating from separate module:

```bash
# 1. Backup current state
terraform state pull > backup.tfstate

# 2. Update main.tf (remove argocd module call)
# 3. Run plan to see changes
terraform plan

# 4. Apply to consolidate (safe, no downtime)
terraform apply -auto-approve

# 5. Verify
kubectl get pods -n argocd
```

## Support Resources

- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

## Next Steps

1. Customize the configuration for your environment
2. Set up GitHub integration
3. Deploy your applications via ArgoCD
4. Configure monitoring and alerting
5. Establish backup and disaster recovery procedures
