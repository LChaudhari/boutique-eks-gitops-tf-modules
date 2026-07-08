variable "domain" {
  description = "Apex domain; Grafana is exposed at grafana.<domain> when TLS is enabled"
  type        = string
}

variable "expose_via_ingress" {
  description = "Expose Grafana publicly (HTTPS Ingress when enable_tls, else a public HTTP LoadBalancer service). When false, it stays ClusterIP (port-forward)."
  type        = bool
  default     = true
}

variable "enable_tls" {
  description = "Serve Grafana over HTTPS via ALB Ingress + ACM (requires a domain). When false, expose it domainless over plain HTTP via a LoadBalancer service."
  type        = bool
  default     = true
}

variable "monitoring_chart_version" {
  description = "Helm chart version for kube-prometheus-stack"
  type        = string
  default     = "56.21.0"
}

variable "storage_class" {
  description = "StorageClass for Prometheus/Grafana persistent volumes"
  type        = string
  default     = "gp3"
}

variable "prometheus_retention" {
  description = "Prometheus metric retention window"
  type        = string
  default     = "15d"
}

variable "prometheus_storage_size" {
  description = "Prometheus PVC size"
  type        = string
  default     = "20Gi"
}

variable "grafana_storage_size" {
  description = "Grafana PVC size"
  type        = string
  default     = "10Gi"
}

variable "grafana_admin_password" {
  description = "Grafana admin password (store in a secret manager for real prod)"
  type        = string
  sensitive   = true
}
