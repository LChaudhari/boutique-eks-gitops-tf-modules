variable "domain" {
  description = "Apex domain; ArgoCD is exposed at argocd.<domain> when TLS is enabled"
  type        = string
}

variable "expose_via_ingress" {
  description = "Expose ArgoCD publicly (HTTPS Ingress when enable_tls, else a public HTTP LoadBalancer service). When false, it stays ClusterIP (port-forward)."
  type        = bool
  default     = true
}

variable "enable_tls" {
  description = "Serve ArgoCD over HTTPS via ALB Ingress + ACM (requires a domain). When false, expose it domainless over plain HTTP via a LoadBalancer service."
  type        = bool
  default     = true
}

variable "argocd_chart_version" {
  description = "Helm chart version for argo-cd"
  type        = string
  default     = "6.7.0"
}
