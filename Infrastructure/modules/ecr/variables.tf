variable "repositories" {
  description = "ECR repository names to create (one per service)"
  type        = list(string)
}

variable "image_tag_mutability" {
  description = "IMMUTABLE (recommended for prod) or MUTABLE"
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["IMMUTABLE", "MUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be IMMUTABLE or MUTABLE."
  }
}

variable "force_delete" {
  description = "Delete the repo even if it still contains images (use false for prod)"
  type        = bool
  default     = false
}

variable "scan_on_push" {
  description = "Run image vulnerability scan on push"
  type        = bool
  default     = true
}

variable "keep_last_images" {
  description = "Number of most-recent images to retain"
  type        = number
  default     = 10
}

variable "untagged_expiry_days" {
  description = "Expire untagged images older than this many days"
  type        = number
  default     = 14
}

variable "tags" {
  description = "Common tags applied to repositories"
  type        = map(string)
  default     = {}
}
