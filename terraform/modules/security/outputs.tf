output "eks_cluster_sg_id" {
  description = "EKS Cluster Security Group ID"
  value       = aws_security_group.eks_cluster.id
}

output "eks_nodes_sg_id" {
  description = "EKS Nodes Security Group ID"
  value       = aws_security_group.eks_nodes.id
}

output "eks_cluster_role_arn" {
  description = "EKS Cluster IAM Role ARN"
  value       = aws_iam_role.eks_cluster.arn
}

output "eks_node_role_arn" {
  description = "EKS Node IAM Role ARN"
  value       = aws_iam_role.eks_node.arn
}

output "eks_node_role_name" {
  description = "EKS Node IAM Role Name"
  value       = aws_iam_role.eks_node.name
}

output "eks_node_instance_profile_arn" {
  description = "EKS Node Instance Profile ARN"
  value       = aws_iam_instance_profile.eks_node.arn
}

output "eks_pod_identity_role_arn" {
  description = "EKS Pod Identity IAM Role ARN"
  value       = aws_iam_role.eks_pod_identity.arn
}
