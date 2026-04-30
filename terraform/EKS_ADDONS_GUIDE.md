# EKS Managed Add-ons Comparison Guide

## What Are EKS Managed Add-ons?

EKS Managed Add-ons are AWS-managed versions of popular open-source Kubernetes add-ons. AWS handles updates, security patches, and compatibility with your EKS cluster version automatically.

## Comparison: eksctl vs Terraform

### Using eksctl (OLD)

```bash
# Create cluster with auto add-ons
eksctl create cluster \
  --name leave-system-dev \
  --version 1.35 \
  --region ap-southeast-1 \
  --install-addons  # Auto-installs vpc-cni, coredns, kube-proxy
```

### Using Terraform (NEW)

```hcl
# Terraform automatically installs these add-ons:
enable_ebs_csi_driver = true
enable_efs_csi_driver = false
```

When you run `terraform apply`, it automatically installs:
- ✅ **vpc-cni** (AWS VPC CNI Plugin)
- ✅ **coredns** (DNS Resolution)
- ✅ **kube-proxy** (Network Proxy)
- ✅ **aws-ebs-csi-driver** (optional, EBS volumes)
- ✅ **aws-efs-csi-driver** (optional, EFS volumes)

## Core Add-ons (Always Installed)

These are essential for EKS to function properly. Equivalent to `eksctl --install-addons`:

### 1. VPC CNI (vpc-cni)

**Purpose**: Pod networking and IP address management

```bash
kubectl get pods -n kube-system -l k8s-app=aws-node
# Output: aws-node-xxxxx (running on each node)
```

**Why AWS-managed?**
- Handles AWS VPC integration
- Manages ENI (Elastic Network Interface) allocation
- Provides IP address management for pods

**Version Management**:
```bash
# Terraform automatically gets latest compatible version
aws eks describe-addon-versions \
  --addon-name vpc-cni \
  --kubernetes-version 1.35
```

### 2. CoreDNS (coredns)

**Purpose**: DNS resolution for pods

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
# Output: coredns-xxxxx replicas
```

**What it does**:
- Resolves `service-name` to `service.namespace.svc.cluster.local`
- Internal Kubernetes DNS queries
- Pod-to-pod communication

### 3. Kube Proxy (kube-proxy)

**Purpose**: Network proxy for Kubernetes services

```bash
kubectl get pods -n kube-system -l k8s-app=kube-proxy
# Output: kube-proxy-xxxxx (running on each node)
```

**What it does**:
- Service endpoint proxying
- Load balancing traffic to backend pods
- Network rules management (iptables, IPVS)

## Optional Storage Add-ons

### EBS CSI Driver (aws-ebs-csi-driver)

**Enabled by default** in Terraform configuration

```hcl
enable_ebs_csi_driver = true
```

**Purpose**: Mount EBS volumes as Kubernetes PVC/PV

**Example Usage**:
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ebs-pv
spec:
  storageClassName: ebs-sc
  capacity:
    storage: 50Gi
  accessModes:
    - ReadWriteOnce
  awsElasticBlockStore:
    volumeID: vol-xxxxx
    fsType: ext4
```

**Installation**:
```bash
# Check if running
kubectl get pods -n kube-system -l app=ebs-csi-controller
```

### EFS CSI Driver (aws-efs-csi-driver)

**Disabled by default** (optional)

```hcl
enable_efs_csi_driver = true  # Set to enable
```

**Purpose**: Mount EFS (managed NFS) as Kubernetes PVC/PV

**Difference from EBS**:
- **EBS**: Block storage (SSD/HDD), faster, single AZ
- **EFS**: File storage (NFS), shareable across pods/nodes, multi-AZ

**Example Usage**:
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: efs-pv
spec:
  storageClassName: efs-sc
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteMany  # Multiple pods can write!
  nfs:
    server: fs-xxxxx.efs.ap-southeast-1.amazonaws.com
    path: "/"
```

**Installation**:
```bash
# Check if running
kubectl get pods -n kube-system -l app=efs-csi-controller
```

## Version Management

### Automatic Version Selection

Terraform automatically selects the latest compatible version for your Kubernetes version:

```bash
# Example output after terraform apply:
eks_addons_installed = {
  coredns        = "v1.9.3-eksbuild.2"       # Compatible with K8s 1.35
  ebs_csi_driver = "v1.24.0-eksbuild.1"
  kube_proxy     = "v1.35.0-eksbuild.1"
  vpc_cni        = "v1.14.1-eksbuild.1"
}
```

### Manual Version Control (Optional)

To pin specific versions instead of always latest:

```hcl
# In modules/eks/main.tf - modify the addon creation:
resource "aws_eks_addon" "vpc_cni" {
  addon_version = "1.14.1-eksbuild.1"  # Pin specific version
  # ... rest of config
}
```

### Update Strategy

**Automatic updates** (recommended):
- Terraform/AWS automatically updates add-ons
- Security patches applied immediately
- Compatible with your cluster version

**Manual updates**:
```bash
# Update all add-ons to latest
aws eks update-addon \
  --cluster-name leave-system-dev \
  --addon-name vpc-cni \
  --resolve-conflicts OVERWRITE

# Check update status
aws eks describe-addon \
  --cluster-name leave-system-dev \
  --addon-name vpc-cni
```

## Comparison Table

| Feature | eksctl --install-addons | Terraform (New) |
|---------|-------------------------|-----------------|
| vpc-cni | ✅ Auto | ✅ Auto |
| coredns | ✅ Auto | ✅ Auto |
| kube-proxy | ✅ Auto | ✅ Auto |
| EBS CSI | ❌ Manual | ✅ Toggle (default ON) |
| EFS CSI | ❌ Manual | ✅ Toggle (default OFF) |
| Version Control | AWS-managed | Terraform-managed |
| Updates | Manual | Automatic (via Terraform) |
| IAM Integration | Manual IRSA | Automatic IRSA |
| Monitoring | Manual | Built-in outputs |

## Key Differences from eksctl

### What's Better with Terraform

1. **Explicit Control**: Every add-on is defined in code
2. **IRSA Automatic**: IAM roles created automatically for each add-on
3. **Versioning**: All versions tracked in terraform state
4. **Reproducibility**: Same `terraform apply` = same cluster everywhere
5. **Infrastructure as Code**: Complete cluster definition in git

### What's Simpler with eksctl

```bash
# One command does everything
eksctl create cluster --install-addons

# vs. with Terraform
terraform init
terraform plan
terraform apply
```

But Terraform benefits overcome the extra steps.

## Verification Commands

### Check Installed Add-ons

```bash
# Show all add-ons
aws eks list-addons --cluster-name leave-system-dev

# Show specific add-on details
aws eks describe-addon \
  --cluster-name leave-system-dev \
  --addon-name vpc-cni

# Check service account
kubectl get sa -n kube-system aws-node
```

### Verify Pod Readiness

```bash
# VPC CNI
kubectl get pods -n kube-system -l k8s-app=aws-node -o wide

# CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide

# Kube Proxy
kubectl get pods -n kube-system -l k8s-app=kube-proxy -o wide

# Storage drivers (if enabled)
kubectl get pods -n kube-system -l app=ebs-csi-controller
kubectl get pods -n kube-system -l app=efs-csi-controller
```

### Check Terraform State

```bash
# View add-on versions
terraform output eks_addons_installed

# Example output:
# eks_addons_installed = {
#   coredns        = "v1.9.3-eksbuild.2"
#   ebs_csi_driver = "v1.24.0-eksbuild.1"
#   kube_proxy     = "v1.35.0-eksbuild.1"
#   vpc_cni        = "v1.14.1-eksbuild.1"
# }
```

## Common Issues & Solutions

### Add-on Stuck in "Degraded" State

```bash
# Check status
aws eks describe-addon \
  --cluster-name leave-system-dev \
  --addon-name vpc-cni \
  --query 'addon.health.issues'

# Fix: Recreate add-on
terraform taint module.eks.aws_eks_addon.vpc_cni
terraform apply
```

### IRSA Not Working

```bash
# Verify OIDC provider exists
aws iam list-open-id-connect-providers

# Check service account token
kubectl describe sa aws-node -n kube-system

# Test OIDC token
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://169.254.169.254/latest/api/token
```

### Persistent Volume Not Mounting

```bash
# Check CSI driver pods
kubectl get pods -n kube-system | grep csi

# Check events
kubectl describe pvc <pvc-name>

# Check node logs
kubectl logs -n kube-system -l app=ebs-csi-node
```

## Best Practices

1. ✅ **Always enable storage drivers** if using persistent volumes
2. ✅ **Keep versions in sync** - Update terraform when updating K8s
3. ✅ **Monitor add-on health** - Check `eks_addons_installed` output
4. ✅ **Don't manually modify** - Let Terraform manage add-ons
5. ✅ **Test updates** - Plan before applying version changes

## Migration from eksctl

If migrating from eksctl cluster to Terraform:

```bash
# 1. List current add-ons (eksctl cluster)
aws eks list-addons --cluster-name old-cluster

# 2. Note the versions
aws eks describe-addon \
  --cluster-name old-cluster \
  --addon-name vpc-cni \
  --query 'addon.addonVersion'

# 3. Create new cluster with Terraform
terraform apply

# 4. Terraform automatically installs compatible versions
terraform output eks_addons_installed

# 5. Verify same add-ons installed
aws eks list-addons --cluster-name leave-system-dev
```

## Summary

Your Terraform configuration now:
- ✅ Installs the same core add-ons as `eksctl --install-addons`
- ✅ Adds optional storage support (EBS, EFS)
- ✅ Automatically manages versions
- ✅ Maintains IRSA configuration
- ✅ Provides complete infrastructure as code

This matches and exceeds what eksctl provides! 🎉
