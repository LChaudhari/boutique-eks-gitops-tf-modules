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

# --- External Secrets Operator ---
variable "enable_external_secrets" {
  description = "Install External Secrets Operator + a ClusterSecretStore for AWS Secrets Manager"
  type        = bool
  default     = true
}

variable "external_secrets_role_arn" {
  description = "IRSA role ARN for External Secrets Operator (from the eks module)"
  type        = string
  default     = ""
}

variable "external_secrets_namespace" {
  description = "Namespace to install ESO into"
  type        = string
  default     = "external-secrets"
}

variable "external_secrets_service_account" {
  description = "ESO ServiceAccount name (annotated with the IRSA role)"
  type        = string
  default     = "external-secrets"
}

variable "external_secrets_chart_version" {
  description = "Helm chart version for external-secrets"
  type        = string
  default     = "0.10.5"
}

variable "cluster_secret_store_name" {
  description = "Name of the ClusterSecretStore (referenced by app values' secretStoreRef.name)"
  type        = string
  default     = "aws-secretsmanager"
}
