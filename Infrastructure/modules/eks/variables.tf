variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane"
  type        = string
  default     = "1.36"
}

variable "private_subnet_ids" {
  description = "Private subnet IDs where worker nodes run"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs (attached to the control plane for ENIs / public LBs)"
  type        = list(string)
}

variable "node_group_name" {
  description = "EKS managed node group name"
  type        = string
}

variable "instance_types" {
  description = "EC2 instance types for worker nodes"
  type        = list(string)

  validation {
    condition     = length(var.instance_types) > 0
    error_message = "Provide at least one instance type."
  }
}

variable "capacity_type" {
  description = "Capacity type for nodes (ON_DEMAND or SPOT)"
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.capacity_type)
    error_message = "capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "desired_size" {
  description = "Desired number of worker nodes"
  type        = number
}

variable "min_size" {
  description = "Minimum number of worker nodes"
  type        = number
}

variable "max_size" {
  description = "Maximum number of worker nodes"
  type        = number
}

variable "disk_size" {
  description = "Disk size (GiB) for worker nodes"
  type        = number
  default     = 20
}

variable "node_labels" {
  description = "Kubernetes labels applied to the node group"
  type        = map(string)
  default     = {}
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint"
  type        = list(string)
}

variable "cluster_log_types" {
  description = "Control plane log types to ship to CloudWatch"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "log_retention_days" {
  description = "Retention (days) for the cluster CloudWatch log group"
  type        = number
  default     = 7
}

variable "external_secrets_namespace" {
  description = "Namespace ESO runs in (used in the IRSA trust condition)"
  type        = string
  default     = "external-secrets"
}

variable "external_secrets_service_account" {
  description = "ESO ServiceAccount name (used in the IRSA trust condition)"
  type        = string
  default     = "external-secrets"
}

variable "secrets_manager_path_prefix" {
  description = "Secrets Manager id prefix ESO may read (scopes the IRSA policy; a trailing '*' is appended). Empty string = any secret in this account/region, so any app can have its own path. Set e.g. \"boutique/\" to restrict."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Common tags applied to module resources"
  type        = map(string)
  default     = {}
}
