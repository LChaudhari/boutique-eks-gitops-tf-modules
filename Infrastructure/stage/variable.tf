variable "region" {
  description = "AWS region"
  type        = string
}

variable "environment" {
  description = "Environment name (stage)"
  type        = string
}

variable "project" {
  description = "Project name (used in tags)"
  type        = string
}

variable "owner" {
  description = "Owner tag value"
  type        = string
}

# --- Networking ---
variable "vpc_name" {
  description = "VPC name"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "public_subnets" {
  description = "Public subnets (cidr + az)"
  type = list(object({
    cidr = string
    az   = string
  }))
}

variable "private_subnets" {
  description = "Private subnets (cidr + az)"
  type = list(object({
    cidr = string
    az   = string
  }))
}

# --- EKS ---
variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
}

variable "node_group_name" {
  description = "Node group name"
  type        = string
}

variable "instance_types" {
  description = "Worker node instance types"
  type        = list(string)
}

variable "capacity_type" {
  description = "ON_DEMAND or SPOT"
  type        = string
}

variable "desired_size" {
  description = "Desired node count"
  type        = number
}

variable "min_size" {
  description = "Minimum node count"
  type        = number
}

variable "max_size" {
  description = "Maximum node count"
  type        = number

  validation {
    condition     = var.max_size >= var.min_size && var.desired_size >= var.min_size && var.desired_size <= var.max_size
    error_message = "Require min_size <= desired_size <= max_size."
  }
}

variable "disk_size" {
  description = "Node disk size (GiB)"
  type        = number
}

variable "node_labels" {
  description = "Labels applied to the node group"
  type        = map(string)
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint"
  type        = list(string)
}

# --- ECR ---
variable "repositories" {
  description = "ECR repository names"
  type        = list(string)
}

variable "ecr_image_tag_mutability" {
  description = "IMMUTABLE or MUTABLE"
  type        = string
}

variable "ecr_force_delete" {
  description = "Force-delete ECR repos that still contain images"
  type        = bool
}

# --- DNS / domain ---
variable "enable_dns" {
  description = "Use a real domain: create the ACM cert + Route53 records, run ExternalDNS, and serve app/ArgoCD/Grafana over HTTPS. Set false to deploy domainless (public HTTP load balancers, no TLS)."
  type        = bool
  default     = true
}

variable "domain" {
  description = "Domain the app is served at (also the ACM cert subject). Unused when enable_dns = false."
  type        = string
  default     = ""
}

variable "hosted_zone_name" {
  description = "Existing Route53 zone to write records into (parent zone if domain is a subdomain). Unused when enable_dns = false."
  type        = string
  default     = ""
}

# --- Platform add-ons / monitoring ---
variable "expose_admin_uis" {
  description = "Expose ArgoCD and Grafana via ALB Ingress subdomains"
  type        = bool
}

variable "grafana_admin_password" {
  description = "Grafana admin password (supply via TF_VAR_grafana_admin_password, not committed to tfvars)"
  type        = string
  sensitive   = true
}
