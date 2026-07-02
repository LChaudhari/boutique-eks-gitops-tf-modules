terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    helm = {
      source = "hashicorp/helm"
    }
  }
}

# ---------------------------------------------------------------------------
# AWS Load Balancer Controller — provisions ALBs from Ingress objects.
# ---------------------------------------------------------------------------
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.alb_controller_chart_version

  values = [
    yamlencode({
      clusterName = var.cluster_name
      region      = var.region
      vpcId       = var.vpc_id

      serviceAccount = {
        create = true
        name   = "aws-load-balancer-controller"
        annotations = {
          "eks.amazonaws.com/role-arn" = var.alb_controller_role_arn
        }
      }
    })
  ]
}

# ---------------------------------------------------------------------------
# ExternalDNS — keeps Route53 records in sync with Ingress hosts.
# ---------------------------------------------------------------------------
resource "helm_release" "external_dns" {
  count = var.enable_external_dns ? 1 : 0

  name       = "external-dns"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = var.external_dns_chart_version

  values = [
    yamlencode({
      provider      = "aws"
      policy        = "upsert-only"
      registry      = "txt"
      txtOwnerId    = var.cluster_name
      domainFilters = [var.domain]
      sources       = ["service", "ingress"]

      serviceAccount = {
        create = true
        name   = "external-dns"
        annotations = {
          "eks.amazonaws.com/role-arn" = var.external_dns_role_arn
        }
      }
    })
  ]
}

# ---------------------------------------------------------------------------
# metrics-server — powers `kubectl top` and the Horizontal Pod Autoscaler.
# ---------------------------------------------------------------------------
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.metrics_server_chart_version
}

# ---------------------------------------------------------------------------
# Encrypted gp3 StorageClass for Prometheus/Grafana/Postgres PVCs.
# Not marked default to avoid clashing with the EKS-provided gp2 default.
# ---------------------------------------------------------------------------
resource "kubernetes_storage_class_v1" "gp3" {
  count = var.create_gp3_storage_class ? 1 : 0

  metadata {
    name = "gp3"
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
  }
}
