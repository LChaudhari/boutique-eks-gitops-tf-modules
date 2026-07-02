output "argocd_namespace" {
  description = "Namespace ArgoCD is installed in"
  value       = kubernetes_namespace_v1.argocd.metadata[0].name
}

output "monitoring_namespace" {
  description = "Namespace the monitoring stack is installed in"
  value       = kubernetes_namespace_v1.monitoring.metadata[0].name
}

output "argocd_url" {
  description = "Public ArgoCD URL, or how to find it in domainless mode"
  value = (
    local.admin_ingress_enabled ? "https://argocd.${var.domain}" :
    local.admin_service_type == "LoadBalancer" ? "http://<get it: kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'>" :
    null
  )
}

output "grafana_url" {
  description = "Public Grafana URL, or how to find it in domainless mode"
  value = (
    local.admin_ingress_enabled ? "https://grafana.${var.domain}" :
    local.admin_service_type == "LoadBalancer" ? "http://<get it: kubectl get svc kube-prometheus-stack-grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'>" :
    null
  )
}
