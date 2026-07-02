# Existing hosted zone (the domain is already registered/delegated to Route53).
data "aws_route53_zone" "this" {
  name         = var.hosted_zone_name != "" ? var.hosted_zone_name : var.domain
  private_zone = false
}

locals {
  # Default SANs: the wildcard so argocd.<domain> / grafana.<domain> are covered.
  sans = length(var.subject_alternative_names) > 0 ? var.subject_alternative_names : ["*.${var.domain}"]
}

# Public ACM certificate (DNS validated). The AWS Load Balancer Controller
# auto-discovers this cert by host, so Ingress manifests don't hard-code the ARN.
resource "aws_acm_certificate" "this" {
  domain_name               = var.domain
  subject_alternative_names = local.sans
  validation_method         = "DNS"

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# One Route53 record per distinct validation option.
resource "aws_route53_record" "validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = data.aws_route53_zone.this.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

# Waits until the certificate is validated and issued.
resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]
}
