# Terraform Quick Reference

## Quick Start Commands

```bash
# Initialize Terraform
terraform init

# Format code
terraform fmt -recursive

# Validate configuration
terraform validate

# Plan deployment
terraform plan -out=tfplan

# Apply configuration
terraform apply tfplan

# Destroy resources
terraform destroy

# View outputs
terraform output

# Get specific output value
terraform output -raw configure_kubectl
```

## Common Customizations

### Change Environment

Edit `terraform.tfvars`:

```hcl
environment = "prod"
```

### Change Node Count

```hcl
desired_capacity = 5
max_capacity     = 15
```

### Change Instance Type

```hcl
instance_type = "t3.large"  # For production
instance_type = "t3.micro"  # For testing (cost savings)
```

### Disable ArgoCD

```hcl
enable_argocd = false
```

### Change Kubernetes Version

```hcl
kubernetes_version = "1.36"
```

### Change AWS Region

```hcl
aws_region = "ap-southeast-1"  # Singapore (closest to Thailand)
```

## SSH into Nodes

```bash
# Get node instance IDs
aws ec2 describe-instances \
  --filters "Name=tag:aws:eks:cluster-name,Values=leave-system-dev" \
  --query 'Reservations[].Instances[].InstanceId' \
  --region ap-southeast-1

# SSH into node (requires Systems Manager Session)
aws ssm start-session --target <instance-id> --region ap-southeast-1
```

## Cluster Access

```bash
# Get cluster info
kubectl cluster-info

# Get nodes
kubectl get nodes -o wide

# Get all resources
kubectl get all -A

# Get pod logs
kubectl logs -n argocd -l app.kubernetes.io/name=argo-cd
```

## ArgoCD Quick Access

```bash
# Get ArgoCD admin password
kubectl get secret -n argocd argocd-admin-password -o jsonpath='{.data.password}' | base64 -d

# Port forward to ArgoCD
kubectl port-forward -n argocd svc/argocd-server 8080:443

# Login to ArgoCD CLI
argocd login <server> --username admin --password <password>

# List applications
argocd app list

# Get application status
argocd app get <app-name>
```

## State Management

```bash
# Show current state
terraform show

# Show state resources
terraform state list

# Show specific resource
terraform state show module.eks.aws_eks_cluster.main

# Refresh state
terraform refresh

# Plan destroy
terraform plan -destroy
```

## Useful AWS Commands

```bash
# List EKS clusters
aws eks list-clusters --region ap-southeast-1

# Describe cluster
aws eks describe-cluster --name leave-system-dev --region ap-southeast-1

# Get cluster auth token
aws eks get-token --cluster-name leave-system-dev --region ap-southeast-1

# List node groups
aws eks list-nodegroups --cluster-name leave-system-dev --region ap-southeast-1

# Describe node group
aws eks describe-nodegroup \
  --cluster-name leave-system-dev \
  --nodegroup-name leave-system-node-group-dev \
  --region ap-southeast-1

# List VPCs
aws ec2 describe-vpcs --region ap-southeast-1

# List security groups
aws ec2 describe-security-groups --region ap-southeast-1
```

## Debugging

```bash
# Get events
kubectl get events -A --sort-by='.lastTimestamp'

# Describe node
kubectl describe node <node-name>

# Describe pod
kubectl describe pod -n <namespace> <pod-name>

# Get pod logs
kubectl logs -n <namespace> <pod-name>

# Get previous logs (if crashed)
kubectl logs -n <namespace> <pod-name> --previous

# Port forward for debugging
kubectl port-forward -n <namespace> <pod-name> 8000:8000
```

## Terraform Variables via CLI

```bash
# Pass variable via CLI
terraform plan -var="environment=prod" -var="desired_capacity=5"

# Pass variable file
terraform plan -var-file="prod.tfvars"

# Pass environment variable
export TF_VAR_environment="prod"
terraform plan
```

## Common Issues

### Issue: State Lock

```bash
# Force unlock (use with caution!)
terraform force-unlock <LOCK_ID>
```

### Issue: Module Not Found

```bash
# Reinitialize modules
terraform init -upgrade

# Or
rm -rf .terraform && terraform init
```

### Issue: Resource Not Destroyed

```bash
# View resource
terraform state show 'module.eks.aws_eks_cluster.main'

# Remove from state only (dangerous!)
terraform state rm 'module.eks.aws_eks_cluster.main'
```

## Performance Tips

- Use `terraform plan -out=tfplan` to review before applying
- Run `terraform fmt -recursive` to maintain consistency
- Use modules to organize code
- Update provider versions periodically: `terraform init -upgrade`

## Security Best Practices

1. Never commit `.tfstate` files to git
2. Use `terraform.tfvars` for sensitive values
3. Use AWS Secrets Manager for credentials
4. Enable S3 backend encryption
5. Review IAM policies regularly

## Getting Help

```bash
# Terraform help
terraform -help

# Provider documentation
terraform -help variable

# Show version
terraform version

# Show required providers
terraform providers
```

## Workspace Management

```bash
# Create workspace
terraform workspace new prod

# List workspaces
terraform workspace list

# Select workspace
terraform workspace select prod

# Delete workspace
terraform workspace delete prod
```

## Module Management

```bash
# Get modules
terraform get

# Initialize only
terraform init -backend=false

# Upgrade providers
terraform init -upgrade
```

## Outputs Export

```bash
# Get outputs as JSON
terraform output -json

# Specific output
terraform output eks_cluster_id

# Raw output (without quotes)
terraform output -raw configure_kubectl
```
