region      = "us-west-2"
environment = "stage"
project     = "boutique-microservices"
owner       = "platform-team"

# --- Networking ---
vpc_name = "boutique-stage-vpc"
vpc_cidr = "10.10.0.0/16"

public_subnets = [
  { cidr = "10.10.1.0/24", az = "us-west-2a" },
  { cidr = "10.10.2.0/24", az = "us-west-2b" },
]

private_subnets = [
  { cidr = "10.10.11.0/24", az = "us-west-2a" },
  { cidr = "10.10.12.0/24", az = "us-west-2b" },
]

# --- EKS ---
cluster_name    = "boutique-stage"
cluster_version = "1.36"
node_group_name = "boutique-stage-ng"

instance_types = ["t3.large"]
capacity_type  = "ON_DEMAND"

desired_size = 1
min_size     = 1
max_size     = 2
disk_size    = 20

node_labels = {
  environment = "stage"
}

# Open for stage; tighten to office/VPN CIDRs for real use.
public_access_cidrs = ["0.0.0.0/0"]

# --- ECR (mutable tags are convenient in stage) ---
repositories = [
  "frontend",
  "gateway",
  "auth",
  "order-service",
  "orders",
  "product-service",
  "user-service",
  # devboard app
  "devboard-backend",
  "devboard-frontend",
]
ecr_image_tag_mutability = "MUTABLE"
ecr_force_delete         = true

# --- DNS / domain ---
# Domainless deploy: no ACM/Route53/ExternalDNS, and app/ArgoCD/Grafana are
# exposed over plain HTTP load balancers (AWS-generated hostnames, no TLS).
# To use a real domain later: set enable_dns = true and fill in domain +
# hosted_zone_name (an existing Route53 zone).
enable_dns       = false
domain           = ""
hosted_zone_name = ""

# --- Admin UIs ---
expose_admin_uis = true
# grafana_admin_password supplied via TF_VAR_grafana_admin_password (do not commit secrets)
