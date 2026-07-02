output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.eks.name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = aws_eks_cluster.eks.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 cluster CA certificate"
  value       = aws_eks_cluster.eks.certificate_authority[0].data
}

output "cluster_version" {
  description = "Kubernetes version of the cluster"
  value       = aws_eks_cluster.eks.version
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider for IRSA"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "OIDC issuer URL (host only, no scheme)"
  value       = local.oidc_issuer
}

output "node_group_name" {
  description = "Managed node group name"
  value       = aws_eks_node_group.node_group.node_group_name
}

output "node_group_arn" {
  description = "Managed node group ARN"
  value       = aws_eks_node_group.node_group.arn
}

output "fluent_bit_irsa_role_arn" {
  description = "IRSA role ARN for Fluent Bit"
  value       = aws_iam_role.fluent_bit_irsa.arn
}

output "alb_controller_role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller"
  value       = aws_iam_role.alb_controller_irsa.arn
}

output "external_dns_role_arn" {
  description = "IRSA role ARN for ExternalDNS"
  value       = aws_iam_role.external_dns_irsa.arn
}

output "secrets_kms_key_arn" {
  description = "KMS key ARN used for EKS secrets encryption"
  value       = aws_kms_key.eks_secrets.arn
}
