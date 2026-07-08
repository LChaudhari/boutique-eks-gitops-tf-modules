output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "ecr_repository_urls" {
  description = "Map of ECR repo name -> URL"
  value       = module.ecr.repository_urls
}

output "app_url" {
  description = "Public application URL (domainless mode returns how to find the ALB hostname)"
  value       = var.enable_dns ? "https://${var.domain}" : "http://<get it: kubectl get ingress boutique -n boutique -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'>"
}

output "argocd_url" {
  description = "ArgoCD URL"
  value       = module.argocd.argocd_url
}

output "grafana_url" {
  description = "Grafana URL"
  value       = module.monitoring.grafana_url
}

output "route53_zone_id" {
  description = "Route53 hosted zone ID (null in domainless mode)"
  value       = one(module.dns[*].zone_id)
}

output "acm_certificate_arn" {
  description = "Validated ACM certificate ARN (null in domainless mode)"
  value       = one(module.dns[*].acm_certificate_arn)
}
