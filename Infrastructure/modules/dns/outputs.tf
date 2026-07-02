output "zone_id" {
  description = "Route53 hosted zone ID for the domain"
  value       = data.aws_route53_zone.this.zone_id
}

output "domain" {
  description = "Apex/app domain"
  value       = var.domain
}

output "acm_certificate_arn" {
  description = "ARN of the validated ACM certificate"
  value       = aws_acm_certificate_validation.this.certificate_arn
}
