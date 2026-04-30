# Terraform Configuration for Leave Management System

This Terraform configuration sets up a complete EKS cluster in AWS with ArgoCD integrated as a native EKS capability.

## 🎯 Architecture Overview

The infrastructure includes:
- **VPC**: VPC with public and private subnets across 3 availability zones
- **NAT Gateways**: For outbound internet access from private subnets
- **EKS Cluster**: Kubernetes 1.35 cluster with managed node groups
- **Security Groups & IAM**: Proper network segmentation and IRSA (IAM Roles for Service Accounts)
- **ArgoCD**: Built-in as EKS capability for GitOps continuous deployment
- **OIDC Provider**: For Kubernetes Service Account authentication to AWS services (IRSA)

## Directory Structure

```
terraform/
├── modules/
│   ├── vpc/              # VPC, Subnets, NAT, IGW
│   ├── security/         # Security Groups, IAM Roles
│   └── eks/              # EKS Cluster, Node Groups, OIDC, ArgoCD (as capability)
├── main.tf              # Main configuration using modules
├── variables.tf         # Input variables
├── outputs.tf           # Output values
├── provider.tf          # Provider configuration
├── terraform.tfvars     # Default values
└── README.md           # This file
```

## Key Features

✨ **ArgoCD as EKS Capability**: ArgoCD is installed directly as part of the EKS cluster infrastructure, not as a separate component. This provides:
- Simplified management (one cluster lifecycle)
- Better integration with AWS services (IRSA, ALB)
- Unified deployment and monitoring
- Native support for Kubernetes resources

⚙️ **Fully Modularized**: Each component (VPC, Security, EKS) is independent and reusable

🔐 **Security Best Practices**: IRSA, proper IAM roles, security groups, and network policies

🚀 **Auto-Scaling**: Cluster Autoscaler integrated for dynamic workload scaling

📊 **Monitoring Ready**: Metrics server and Prometheus-compatible endpoints

## Prerequisites

1. **AWS Account**: With appropriate permissions
2. **Terraform**: >= 1.0
3. **AWS CLI**: Configured with credentials
4. **kubectl**: To interact with the cluster
5. **Helm**: (Optional) For managing Helm charts

## Deployment Steps

### 1. Initialize Terraform

```bash
cd terraform
terraform init
```

### 2. Review the Plan

```bash
terraform plan -out=tfplan
```

### 3. Apply Configuration

```bash
terraform apply tfplan
```

### 4. Configure kubectl

After deployment, configure your kubectl to access the cluster:

```bash
aws eks update-kubeconfig --region ap-southeast-1 --name leave-system-dev
```

### 5. Verify Cluster

```bash
kubectl get nodes
kubectl get namespaces
```

## Configuration

### Main Variables (terraform.tfvars)

Edit `terraform.tfvars` to customize:

```hcl
aws_region          = "ap-southeast-1"      # AWS Region
project_name        = "leave-system"        # Project name
environment         = "dev"                 # Environment
kubernetes_version  = "1.35"                # K8s version
instance_type       = "t3.medium"           # Node instance type
desired_capacity    = 3                     # Initial node count
enable_argocd       = true                  # Enable ArgoCD
```

### ArgoCD Configuration

To enable GitHub integration with ArgoCD:

```hcl
github_token      = "your_github_token"
github_username   = "your_username"
github_repo_url   = "https://github.com/org/repo"
```

## Outputs

After deployment, Terraform outputs important information:

```bash
terraform output

# Example output:
eks_cluster_id = "leave-system-dev"
eks_cluster_endpoint = "https://xxx.eks.ap-southeast-1.amazonaws.com"
argocd_namespace = "argocd"
configure_kubectl = "aws eks update-kubeconfig --region ap-southeast-1 --name leave-system-dev"
```

## Accessing ArgoCD

### Port Forwarding

```bash
kubectl port-forward -n argocd svc/argocd-server 8080:443
```

Then access at: `https://localhost:8080`

### Via Ingress

If ingress is enabled, update your DNS to point to the ALB:

```bash
kubectl get ingress -n argocd
```

### Default Credentials

- **Username**: `admin`
- **Password**: `leave-system@dev` (format: `{project_name}@{environment}`)

Change the password after first login!

## Module Details

### VPC Module

Creates:
- VPC with configurable CIDR
- Public subnets (for ALB, NAT)
- Private subnets (for worker nodes)
- Internet Gateway
- NAT Gateways
- Route tables

### Security Module

Creates:
- EKS Cluster Security Group
- EKS Node Security Group
- IAM Role for EKS Cluster
- IAM Role for EKS Node
- IAM roles for pod-level permissions (IRSA)

### EKS Module

Creates:
- EKS Cluster
- Managed Node Group
- OIDC Provider (for IRSA)
- IAM roles for AWS Load Balancer Controller
- IAM roles for Cluster Autoscaler

### ArgoCD Module

Deploys:
- ArgoCD Helm chart
- ArgoCD namespace
- Repository credentials (if GitHub token provided)
- Service and optional Ingress

## Advanced Features

### Remote State Management

To store state in S3 with locking:

```hcl
# Uncomment in provider.tf and customize:
backend "s3" {
  bucket         = "your-state-bucket"
  key            = "eks/terraform.tfstate"
  region         = "ap-southeast-1"
  encrypt        = true
  dynamodb_table = "terraform-locks"
}
```

### Cluster Autoscaling

The EKS module automatically configures:
- Cluster Autoscaler IAM role and policies
- Node groups with auto-scaling configuration

### ArgoCD GitOps Integration

Deploy applications using ArgoCD Applications:

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
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## Cleanup

To destroy all infrastructure:

```bash
terraform destroy
```

**Warning**: This will delete the EKS cluster, VPC, and all associated resources.

## Troubleshooting

### OIDC Provider Issues

If IRSA fails, verify the OIDC provider:

```bash
aws iam list-open-id-connect-providers
```

### Node Group Issues

Check node group status:

```bash
aws eks describe-nodegroup --cluster-name leave-system-dev --nodegroup-name leave-system-node-group-dev
```

### ArgoCD Issues

Check ArgoCD logs:

```bash
kubectl logs -n argocd deployment/argocd-server
kubectl logs -n argocd deployment/argocd-application-controller
```

## Best Practices

1. **State Management**: Use S3 backend with locking
2. **Secrets**: Never commit sensitive data; use AWS Secrets Manager or environment variables
3. **Tagging**: Maintain consistent tagging for cost allocation
4. **Monitoring**: Enable CloudWatch logs for EKS cluster
5. **RBAC**: Implement proper RBAC policies
6. **Network Policies**: Enable Kubernetes network policies for security

## Support & Documentation

- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

## License

This Terraform configuration is part of the Leave Management System project.
