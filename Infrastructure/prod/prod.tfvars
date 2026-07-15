region      = "us-west-2"
environment = "prod"
project     = "boutique-microservices"
owner       = "platform-team"

# --- Networking ---
vpc_name = "boutique-prod-vpc"
vpc_cidr = "10.20.0.0/16"

public_subnets = [
  { cidr = "10.20.1.0/24", az = "us-west-2a" },
  { cidr = "10.20.2.0/24", az = "us-west-2b" },
]

private_subnets = [
  { cidr = "10.20.11.0/24", az = "us-west-2a" },
  { cidr = "10.20.12.0/24", az = "us-west-2b" },
]

# --- EKS ---
cluster_name    = "boutique-prod"
cluster_version = "1.34"
node_group_name = "boutique-prod-ng"

instance_types = ["t3.large"]
capacity_type  = "ON_DEMAND"

desired_size = 3
min_size     = 3
max_size     = 6
disk_size    = 50

node_labels = {
  environment = "prod"
}

# IMPORTANT: restrict to your office/VPN egress CIDRs for prod.
public_access_cidrs = ["0.0.0.0/0"]

# --- ECR (immutable + no force delete for prod) ---
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
ecr_image_tag_mutability = "IMMUTABLE"
ecr_force_delete         = false

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
