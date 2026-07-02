variable "vpc_name" {
  description = "Name tag for the VPC and prefix for its resources"
  type        = string
}

variable "cidr_block" {
  description = "CIDR block for the VPC"
  type        = string

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "cidr_block must be a valid IPv4 CIDR (e.g. 10.20.0.0/16)."
  }
}

variable "cluster_name" {
  description = "EKS cluster name, used for subnet discovery tags"
  type        = string
}

variable "public_subnets" {
  description = "Public subnets (one per AZ) for load balancers and the NAT gateway"
  type = list(object({
    cidr = string
    az   = string
  }))

  validation {
    condition     = length(var.public_subnets) >= 2
    error_message = "Provide at least two public subnets across two AZs for high availability."
  }
}

variable "private_subnets" {
  description = "Private subnets (one per AZ) where worker nodes run"
  type = list(object({
    cidr = string
    az   = string
  }))

  validation {
    condition     = length(var.private_subnets) >= 2
    error_message = "Provide at least two private subnets across two AZs for high availability."
  }
}

variable "tags" {
  description = "Common tags applied to all VPC resources"
  type        = map(string)
  default     = {}
}
