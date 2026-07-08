locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = var.owner
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = local.common_tags
  }
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
module "vpc" {
  source = "../modules/vpc"

  vpc_name        = var.vpc_name
  cidr_block      = var.vpc_cidr
  cluster_name    = var.cluster_name
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets
  tags            = local.common_tags
}

# ---------------------------------------------------------------------------
# DNS + TLS certificate (existing Route53 zone; ACM cert + validation records)
# ---------------------------------------------------------------------------
module "dns" {
  source = "../modules/dns"
  count  = var.enable_dns ? 1 : 0

  domain           = var.domain
  hosted_zone_name = var.hosted_zone_name
  tags             = local.common_tags
}

# ---------------------------------------------------------------------------
# EKS cluster, nodes, IRSA, managed add-ons
# ---------------------------------------------------------------------------
module "eks" {
  source = "../modules/eks"

  cluster_name        = var.cluster_name
  cluster_version     = var.cluster_version
  node_group_name     = var.node_group_name
  private_subnet_ids  = module.vpc.private_subnet_ids
  public_subnet_ids   = module.vpc.public_subnet_ids
  instance_types      = var.instance_types
  capacity_type       = var.capacity_type
  desired_size        = var.desired_size
  min_size            = var.min_size
  max_size            = var.max_size
  disk_size           = var.disk_size
  node_labels         = var.node_labels
  public_access_cidrs = var.public_access_cidrs
  tags                = local.common_tags

  depends_on = [module.vpc]
}

# ---------------------------------------------------------------------------
# ECR repositories
# ---------------------------------------------------------------------------
module "ecr" {
  source = "../modules/ecr"

  repositories         = var.repositories
  image_tag_mutability = var.ecr_image_tag_mutability
  force_delete         = var.ecr_force_delete
  tags                 = local.common_tags
}

# ---------------------------------------------------------------------------
# Kubernetes / Helm providers (exec auth so the token can't expire mid-apply)
# ---------------------------------------------------------------------------
provider "kubernetes" {
  alias                  = "eks"
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
  }
}

provider "helm" {
  alias = "eks"

  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
    }
  }
}

# ---------------------------------------------------------------------------
# Platform add-ons: ALB controller, ExternalDNS, metrics-server, gp3 SC
# ---------------------------------------------------------------------------
module "addons" {
  source = "../modules/addons"

  providers = {
    kubernetes = kubernetes.eks
    helm       = helm.eks
  }

  cluster_name              = module.eks.cluster_name
  region                    = var.region
  vpc_id                    = module.vpc.vpc_id
  alb_controller_role_arn   = module.eks.alb_controller_role_arn
  external_dns_role_arn     = module.eks.external_dns_role_arn
  domain                    = var.domain
  enable_external_dns       = var.enable_dns
  enable_external_secrets   = var.enable_external_secrets
  external_secrets_role_arn = module.eks.external_secrets_role_arn
  cluster_secret_store_name = var.cluster_secret_store_name

  depends_on = [module.eks]
}

# ---------------------------------------------------------------------------
# ArgoCD (GitOps), exposed via ALB Ingress / LoadBalancer
# ---------------------------------------------------------------------------
module "argocd" {
  source = "../modules/argocd"

  providers = {
    kubernetes = kubernetes.eks
    helm       = helm.eks
  }

  domain             = var.domain
  expose_via_ingress = var.expose_admin_uis
  enable_tls         = var.enable_dns

  depends_on = [module.addons]
}

# ---------------------------------------------------------------------------
# Monitoring: kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
# ---------------------------------------------------------------------------
module "monitoring" {
  source = "../modules/monitoring"

  providers = {
    kubernetes = kubernetes.eks
    helm       = helm.eks
  }

  domain                 = var.domain
  expose_via_ingress     = var.expose_admin_uis
  enable_tls             = var.enable_dns
  grafana_admin_password = var.grafana_admin_password

  depends_on = [module.addons]
}
