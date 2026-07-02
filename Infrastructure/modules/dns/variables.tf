variable "domain" {
  description = "Domain the cert is issued for and the app is served at (e.g. example.com or stage.example.com)"
  type        = string
}

variable "hosted_zone_name" {
  description = "Existing Route53 hosted zone to write records into (defaults to domain). Set to the parent zone when domain is a subdomain."
  type        = string
  default     = ""
}

variable "subject_alternative_names" {
  description = "Extra SANs for the ACM cert (defaults to the wildcard *.<domain>)"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Common tags applied to the certificate"
  type        = map(string)
  default     = {}
}
