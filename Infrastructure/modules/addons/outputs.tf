output "alb_controller_release" {
  description = "Helm release name of the AWS Load Balancer Controller"
  value       = helm_release.aws_load_balancer_controller.name
}

output "external_dns_release" {
  description = "Helm release name of ExternalDNS (null when disabled)"
  value       = one(helm_release.external_dns[*].name)
}

output "gp3_storage_class" {
  description = "Name of the gp3 StorageClass (empty if not created)"
  value       = var.create_gp3_storage_class ? kubernetes_storage_class_v1.gp3[0].metadata[0].name : ""
}
