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

locals {
  # HTTPS Ingress path: only when we're exposing publicly AND have TLS (a domain).
  admin_ingress_enabled = var.expose_via_ingress && var.enable_tls
  # Domainless public path: expose over a plain-HTTP LoadBalancer service instead.
  # Otherwise stay ClusterIP (reachable via port-forward only).
  admin_service_type = (var.expose_via_ingress && !var.enable_tls) ? "LoadBalancer" : "ClusterIP"

  # Internet-facing NLB annotations for the domainless LoadBalancer service.
  # The AWS LB Controller defaults type=LoadBalancer NLBs to INTERNAL (private,
  # unreachable from a browser), so we must set the scheme explicitly. Rendered
  # ONLY when admin_service_type == "LoadBalancer"; empty ({}) in domain mode
  # where Grafana is ClusterIP behind an ALB Ingress.
  admin_lb_annotations = local.admin_service_type == "LoadBalancer" ? {
    "service.beta.kubernetes.io/aws-load-balancer-type"   = "external"
    "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
    # Optionally lock this public admin UI to your IP (plain HTTP, no TLS):
    # "service.beta.kubernetes.io/aws-load-balancer-source-ranges" = "<your.ip>/32"
  } : {}

  # Shared ALB Ingress annotations. The Load Balancer Controller auto-discovers
  # the ACM cert by matching the Ingress host against the wildcard SAN, so no
  # certificate-arn is hard-coded here.
  alb_annotations = {
    "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
    "alb.ingress.kubernetes.io/target-type"      = "ip"
    "alb.ingress.kubernetes.io/listen-ports"     = "[{\"HTTP\":80},{\"HTTPS\":443}]"
    "alb.ingress.kubernetes.io/ssl-redirect"     = "443"
    "alb.ingress.kubernetes.io/healthcheck-path" = "/"
  }
}

resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

# ---------------------------------------------------------------------------
# kube-prometheus-stack with persistence, retention, limits, Grafana Ingress.
# ---------------------------------------------------------------------------
resource "helm_release" "monitoring" {
  name       = "kube-prometheus-stack"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.monitoring_chart_version

  timeout          = 600
  create_namespace = false

  values = [
    yamlencode({
      grafana = {
        adminPassword = var.grafana_admin_password
        service       = { type = local.admin_service_type, annotations = local.admin_lb_annotations }

        # Auto-load dashboard ConfigMaps (label grafana_dashboard: "1") from ANY
        # namespace. Needed because Kustomize applies the app dashboard
        # ConfigMap into the app namespace, not "monitoring".
        sidecar = {
          dashboards = {
            enabled         = true
            searchNamespace = "ALL"
            label           = "grafana_dashboard"
          }
        }
        persistence = {
          enabled          = true
          storageClassName = var.storage_class
          size             = var.grafana_storage_size
        }
        resources = {
          requests = { cpu = "100m", memory = "128Mi" }
          limits   = { cpu = "500m", memory = "512Mi" }
        }
        ingress = {
          enabled          = local.admin_ingress_enabled
          ingressClassName = "alb"
          hosts            = ["grafana.${var.domain}"]
          path             = "/"
          pathType         = "Prefix"
          annotations      = local.alb_annotations
        }
      }

      prometheus = {
        service = { type = "ClusterIP" }
        prometheusSpec = {
          retention = var.prometheus_retention
          resources = {
            requests = { cpu = "250m", memory = "512Mi" }
            limits   = { cpu = "1000m", memory = "2Gi" }
          }
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = var.storage_class
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = { storage = var.prometheus_storage_size }
                }
              }
            }
          }
        }
      }

      alertmanager = {
        service = { type = "ClusterIP" }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace_v1.monitoring,
  ]
}
