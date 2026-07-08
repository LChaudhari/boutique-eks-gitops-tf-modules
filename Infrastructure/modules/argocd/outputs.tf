output "argocd_namespace" {
  description = "Namespace ArgoCD is installed in"
  value       = kubernetes_namespace_v1.argocd.metadata[0].name
}

output "argocd_url" {
  description = "Public ArgoCD URL, or how to find it in domainless mode"
  value = (
    local.admin_ingress_enabled ? "https://argocd.${var.domain}" :
    local.admin_service_type == "LoadBalancer" ? "http://<get it: kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'>" :
    null
  )
}
