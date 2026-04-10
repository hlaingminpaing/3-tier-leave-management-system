# EKS Deployment Guide

This guide provides step-by-step instructions for deploying the Leave Management System on AWS EKS using Terraform.

## 🎯 New Feature: ArgoCD as EKS Capability

ArgoCD is now **integrated directly as an EKS capability** rather than a separate deployment. This means:
- ✅ ArgoCD is installed automatically with the EKS cluster
- ✅ Unified cluster management (single lifecycle)
- ✅ Direct integration with EKS IRSA and ALB
- ✅ Simplified monitoring and logging
- ✅ Better resource management

- [ ] AWS Account with appropriate IAM permissions
- [ ] AWS CLI v2 installed and configured
- [ ] Terraform >= 1.0 installed
- [ ] kubectl installed
- [ ] Helm installed (for manually managing charts)
- [ ] Git access (for ArgoCD)
- [ ] GitHub token (optional, for private repositories)

## Installation Steps

### 1. Clone and Setup Repository

```bash
# Clone the repository
git clone <your-repo-url>
cd 3tier-leave-system/terraform

# Initialize Terraform
terraform init
```

### 2. Customize Configuration

Edit `terraform.tfvars` with your specific settings:

```bash
# Copy the example values and customize
vi terraform.tfvars
```

Key configurations to update:

```hcl
# Change these to production values for production environments
environment         = "prod"
desired_capacity    = 3
max_capacity        = 10
argocd_ingress_hostname = "argocd.yourdomain.com"

# If using GitHub integration
github_token      = var.github_personal_access_token  # Provide via -var flag
github_username   = "your-username"
github_repo_url   = "https://github.com/org/repo"
```

### 3. Review Deployment Plan

```bash
# Generate and review the execution plan
terraform plan -out=tfplan

# Review the output for any issues
```

### 4. Deploy Infrastructure

```bash
# Apply the Terraform configuration
terraform apply tfplan

# This will take approximately 15-20 minutes
```

Monitor the deployment:

```bash
# In another terminal, watch the EKS cluster creation
watch -n 10 'aws eks describe-cluster --name leave-system-dev --region ap-southeast-1'
```

### 5. Configure kubectl

After deployment completes:

```bash
# Update kubeconfig
aws eks update-kubeconfig --region ap-southeast-1 --name leave-system-dev

# Verify access
kubectl get nodes
kubectl get namespaces
```

### 6. Verify Cluster Health

```bash
# Check cluster info
kubectl cluster-info

# Verify nodes are ready
kubectl get nodes -o wide

# Check system namespaces
kubectl get pods -n kube-system
kubectl get pods -n argocd
```

## Post-Deployment Configuration

### ArgoCD Access

#### Option 1: Port Forwarding (Development)

```bash
kubectl port-forward -n argocd svc/argocd-server 8080:443 &
# Access at: https://localhost:8080
# Default credentials: admin / leave-system@dev
```

#### Option 2: Ingress (Production)

```bash
# Get the ingress endpoint
kubectl get ingress -n argocd

# Add DNS record pointing to the ALB endpoint
# Then access at: https://argocd.yourdomain.com
```

#### Change Default ArgoCD Password

```bash
# Access ArgoCD and change password via CLI
argocd account update-password --account admin --new-password <new-password>

# Or update the secret manually
kubectl patch secret -n argocd argocd-admin-password -p '{"data": {"admin.password": "'$(echo -n '<new-password>' | base64 -w0)'"}}'
```

### Deploy Application via ArgoCD

Create an ArgoCD Application manifest:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: leave-system-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/your-repo
    targetRevision: main
    path: helm-chart
    helm:
      values: |
        image:
          tag: latest
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

Apply the application:

```bash
kubectl apply -f app.yaml
```

## AWS Load Balancer Controller

The Load Balancer Controller is automatically configured via IRSA. Verify installation:

```bash
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

## Cluster Autoscaling

The Cluster Autoscaler is automatically configured. Verify:

```bash
kubectl get deployment -n kube-system cluster-autoscaler
kubectl logs -n kube-system -l app=cluster-autoscaler
```

Tag your ASG for autoscaling to work:

```bash
aws autoscaling create-or-update-tags \
  --tags "ResourceId=<asg-name>,ResourceType=auto-scaling-group,Key=k8s.io/cluster-autoscaler/enabled,Value=true,PropagateAtLaunch=false"
```

## Database Setup (MySQL)

For MySQL deployment with EBS volumes:

```bash
# Create EBS volume
aws ec2 create-volume \
  --size 50 \
  --availability-zone ap-southeast-1a \
  --volume-type gp3 \
  --region ap-southeast-1

# Deploy MySQL using Helm or your containerized version
```

## Monitoring and Logging

### CloudWatch Logs

View cluster logs:

```bash
# Get logs from CloudWatch
aws logs describe-log-groups --region ap-southeast-1 | grep eks

# View specific logs
aws logs tail /aws/eks/leave-system-dev/cluster --follow
```

### Kubernetes Metrics

```bash
# Check node metrics
kubectl top nodes

# Check pod metrics
kubectl top pods -A
```

## Network Configuration

### Accessing Services

```bash
# Get all services
kubectl get svc -A

# Access via port-forward
kubectl port-forward -n <namespace> svc/<service-name> <local-port>:<remote-port>

# Access via LoadBalancer (if configured)
kubectl get svc -A | grep LoadBalancer
```

### DNS Configuration

```bash
# CoreDNS is automatically configured
kubectl get pods -n kube-system -l k8s-app=kube-dns
```

## Maintenance and Updates

### Cluster Updates

```bash
# Check for available updates
aws eks describe-cluster --name leave-system-dev --region ap-southeast-1 | grep version

# Update cluster (causes brief API downtime)
aws eks update-cluster-version --name leave-system-dev --kubernetes-version 1.36 --region ap-southeast-1

# Update node group
aws eks update-nodegroup-version --cluster-name leave-system-dev --nodegroup-name leave-system-node-group-dev --kubernetes-version 1.36 --region ap-southeast-1
```

### Backup and Restore

```bash
# Backup etcd (managed by AWS - not required)
# Backup applications using Velero or similar tools

# Install Velero for disaster recovery
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm install velero vmware-tanzu/velero \
  --namespace velero \
  --create-namespace \
  --set configuration.backupStorageLocation.bucket=<s3-bucket> \
  --set configuration.backupStorageLocation.provider=aws
```

## Cleanup and Destruction

### Remove Resources

To remove all resources (WARNING: Destructive):

```bash
# Destroy all Terraform managed resources
terraform destroy

# Confirm the destruction
# This will take approximately 5-10 minutes
```

### Manual Cleanup

If Terraform destroy fails, clean up manually:

```bash
# Delete EKS cluster
aws eks delete-cluster --name leave-system-dev --region ap-southeast-1

# Wait for cluster deletion
aws eks describe-cluster --name leave-system-dev --region ap-southeast-1

# Delete VPC and related resources
aws ec2 describe-vpcs --region ap-southeast-1 --filter "Name=tag:Name,Values=*leave-system*"
```

## Troubleshooting

### Common Issues

#### 1. Nodes Not Ready

```bash
# Check node status
kubectl describe node <node-name>

# Check kubelet logs
aws ec2 get-console-output --instance-id <instance-id>
```

#### 2. ArgoCD Syncfailing

```bash
# Check ArgoCD application status
argocd app get leave-system-app

# View detailed logs
kubectl logs -n argocd deployment/argocd-application-controller
```

#### 3. Load Balancer Not Working

```bash
# Verify ALB controller is running
kubectl get deployment -n kube-system aws-load-balancer-controller

# Check OIDC provider
aws iam list-open-id-connect-providers

# Verify IAM permissions
aws iam get-role-policy --role-name <alb-controller-role> --policy-name <policy-name>
```

### Advanced Debugging

```bash
# Describe EKS cluster events
kubectl describe events -A

# Check pod logs
kubectl logs -n argocd deployment/argocd-server

# Get cluster diagnostics
kubectl cluster-info dump --output-directory=./cluster-dump
```

## Security Considerations

1. **IAM**: Review and restrict IAM permissions
2. **Network Policies**: Implement Kubernetes network policies
3. **RBAC**: Configure role-based access control
4. **Secrets**: Store sensitive data in AWS Secrets Manager
5. **Compliance**: Enable GuardDuty and Inspector

## Performance Tuning

### Node Capacity

```bash
# Adjust desired capacity
aws auto-scaling set-desired-capacity --auto-scaling-group-name <asg-name> --desired-capacity 5
```

### Cluster Resources

```bash
# Check resource usage
kubectl describe nodes
kubectl top nodes
```

## Support

For issues or questions:
1. Check the logs using `kubectl logs`
2. Review Terraform output
3. Check AWS console for resource status
4. Consult Kubernetes and EKS documentation

## ArgoCD as EKS Capability (New Feature)

### What is EKS Capability Integration?

ArgoCD is now managed as a **core EKS capability**, meaning:
- Installed automatically during cluster creation
- Managed by the EKS module
- Single deployment lifecycle
- Integrated with AWS services (ALB, IRSA, CloudWatch)

### Architecture

```
┌─────────────────────────────────────────────┐
│         EKS Cluster (Kubernetes 1.35)       │
├─────────────────────────────────────────────┤
│                                             │
│  ┌────────────────────────────────────┐    │
│  │    ArgoCD (EKS Capability)         │    │
│  │      - Application Controller      │    │
│  │      - Repo Server                 │    │
│  │      - API Server (ALB Ingress)    │    │
│  │      - Redis Cache                 │    │
│  └────────────────────────────────────┘    │
│                                             │
│  ┌────────────────────────────────────┐    │
│  │    Other Workloads                 │    │
│  │      - Your Applications           │    │
│  │      - Services                    │    │
│  └────────────────────────────────────┘    │
│                                             │
└─────────────────────────────────────────────┘
        ↓ AWS ALB Ingress
        ↓ OIDC Provider (IRSA)
        ↓ CloudWatch Logs
     AWS Ecosystem
```

### Enabling/Disabling ArgoCD

Edit `terraform.tfvars`:

```hcl
# Enable ArgoCD as EKS capability
enable_argocd = true

# Configure namespace
argocd_namespace = "argocd"

# Configure Ingress
enable_argocd_ingress = true
argocd_ingress_hostname = "argocd.yourdomain.com"
```

### Accessing ArgoCD

#### From Terminal

```bash
# Port forward to access ArgoCD UI
kubectl port-forward -n argocd svc/argocd-server 8080:443

# Access at https://localhost:8080
# Default credentials: admin / leave-system@dev
```

#### Via ALB Ingress (Production)

```bash
# Get the ALB endpoint
kubectl get ingress -n argocd

# Add CNAME record in DNS
argocd.yourdomain.com -> <ALB-endpoint>

# Access at https://argocd.yourdomain.com
```

### Managing Applications with ArgoCD

Create an Application manifest:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: leave-system-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/3tier-leave-system
    targetRevision: main
    path: helm-chart
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

Deploy:

```bash
kubectl apply -f app.yaml

# Monitor sync
argocd app get leave-system-app
```

### GitHub Integration

To enable automatic GitOps with GitHub:

1. Create a Personal Access Token in GitHub
2. Update `terraform.tfvars`:

```hcl
github_token = "ghp_xxxxxxxxxxxxxxxxxxxx"
github_username = "your-username"
github_repo_url = "https://github.com/org/3tier-leave-system"
```

3. Redeploy:

```bash
terraform plan
terraform apply
```

ArgoCD will now have automatic access to your repository!

### Monitoring ArgoCD

```bash
# Check ArgoCD namespace
kubectl get pods -n argocd

# View logs
kubectl logs -n argocd deployment/argocd-server
kubectl logs -n argocd deployment/argocd-application-controller
kubectl logs -n argocd deployment/argocd-repo-server

# Check Helm release
helm list -n argocd

# Metrics
kubectl top nodes
kubectl top pods -n argocd
```

### Upgrading ArgoCD

To upgrade ArgoCD version:

```hcl
# Update terraform.tfvars
argocd_version = "7.1.0"

# Apply changes
terraform plan
terraform apply
```

### Integrating with Monitoring

ArgoCD metrics are available at:
- Server metrics: `:8083/metrics`
- Repo server metrics: `:8084/metrics`
- Controller metrics: `:8085/metrics`

For Prometheus integration:

```bash
# Create ServiceMonitor
kubectl create servicemonitor argocd-metrics \
  --selector app=argocd-metrics \
  -n argocd
```

## Next Steps

1. Deploy your applications using ArgoCD
2. Set up monitoring with CloudWatch/Prometheus
3. Configure backup and disaster recovery
4. Implement CI/CD pipelines
5. Set up security scanning and compliance checks
