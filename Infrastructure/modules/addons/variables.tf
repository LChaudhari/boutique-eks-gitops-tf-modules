variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "region" {
  description = "AWS region (passed to the load balancer controller)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID the cluster runs in"
  type        = string
}

variable "alb_controller_role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller"
  type        = string
}

variable "external_dns_role_arn" {
  description = "IRSA role ARN for ExternalDNS"
  type        = string
}

variable "enable_external_dns" {
  description = "Install ExternalDNS. Requires a real domain/hosted zone; disable for domainless deploys."
  type        = bool
  default     = true
}

variable "domain" {
  description = "Domain ExternalDNS is allowed to manage records for"
  type        = string
}

variable "alb_controller_chart_version" {
  description = "Helm chart version for aws-load-balancer-controller"
  type        = string
  default     = "1.7.2"
}

variable "external_dns_chart_version" {
  description = "Helm chart version for external-dns"
  type        = string
  default     = "1.14.5"
}

variable "metrics_server_chart_version" {
  description = "Helm chart version for metrics-server"
  type        = string
  default     = "3.12.1"
}

variable "create_gp3_storage_class" {
  description = "Create an encrypted gp3 StorageClass for stateful workloads"
  type        = bool
  default     = true
}
