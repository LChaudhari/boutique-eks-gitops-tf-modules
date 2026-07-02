# Terraform Changes — Demo → Production-Ready

This document records what the EKS Terraform configuration looked like **before** and
what was **changed** to make it production-ready (multi-AZ, private nodes, encrypted,
multi-environment, internet-exposed over HTTPS).

---

## 0. High-level summary

| Area | Before | After |
| --- | --- | --- |
| Layout | Single root in `Infrastructure/` | Per-env roots `Infrastructure/stage/` + `Infrastructure/prod/`, shared `modules/` |
| Networking | All-public subnets, node public IPs, no NAT | 2 public + 2 private subnets across 2 AZs, 1 NAT, private nodes |
| EKS API | Public-only endpoint | Public (CIDR-restricted) + private endpoint |
| Logging | None | Control-plane logs (api/audit/authenticator/controllerManager/scheduler) → CloudWatch |
| Secrets | Default (AWS-owned key) | KMS envelope encryption (CMK + rotation) |
| ECR | MUTABLE tags, no lifecycle | IMMUTABLE (prod) + lifecycle policy |
| State | S3, no locking/encryption | S3 + `encrypt` + `use_lockfile` (per-env keys) |
| Ingress / DNS / TLS | None (local `port-forward` only) | ALB Ingress + ExternalDNS + ACM cert (HTTPS on a domain) |
| Add-ons | EBS CSI only | vpc-cni, coredns, kube-proxy, ebs-csi + ALB controller, ExternalDNS, metrics-server |
| Providers | No `aws` block, unpinned | Explicit `aws` provider, `default_tags`, pinned versions |
| Lambda module | Referenced but missing (broke `init`) | Removed |

---

## 1. Directory structure

**Before**
```
Infrastructure/
  backend.tf  main.tf  variables.tf  terraform.tfvars  outputs.tf
  modules/
    vpc/  eks/  ecr/  argocd/
  # main.tf also referenced ./modules/lambda — which did NOT exist
```

**After**
```
Infrastructure/
  modules/
    vpc/      (reworked)
    eks/      (reworked) + alb_controller_iam_policy.json
    ecr/      (reworked) — variables split into variables.tf
    dns/      (new)
    addons/   (new)
    argocd/   (reworked)
  stage/
    backend.tf  main.tf  variable.tf  output.tf  stage.tfvars
  prod/
    backend.tf  main.tf  variable.tf  output.tf  prod.tfvars
```
The old single-root files (`Infrastructure/main.tf`, `backend.tf`, `variables.tf`,
`terraform.tfvars`, `outputs.tf`) were **removed** — replaced by the two env roots.

---

## 2. State backend (`backend.tf`)

**Before**
```hcl
backend "s3" {
  bucket = "tf-devops-ai-statefile"
  key    = "devops-ai/terraform.tfstate"
  region = "ap-south-1"
}
required_providers { aws = { source = "hashicorp/aws", version = "~> 5.0" } }
```

**After** (per env, e.g. `prod/backend.tf`)
```hcl
required_version = ">= 1.10"
backend "s3" {
  bucket       = "tf-devops-ai-statefile"
  key          = "devops-ai/prod/terraform.tfstate"   # per-env key (stage/prod)
  region       = "ap-south-1"
  encrypt      = true            # NEW: server-side encryption
  use_lockfile = true            # NEW: S3-native state locking (no DynamoDB)
}
required_providers {
  aws        = "~> 5.0"
  kubernetes = "~> 2.30"
  helm       = "~> 3.0"
  tls        = "~> 4.0"
}
```

---

## 3. Providers & tagging (env `main.tf`)

- **Added** an explicit `provider "aws" { region = var.region; default_tags { ... } }`
  block — before, no AWS provider was configured, so the region came only from env vars.
- **Added** `default_tags` (Project / Environment / ManagedBy / Owner) applied to every
  taggable resource.
- `kubernetes` / `helm` providers kept their `exec` (`aws eks get-token`) auth so the
  token can't expire mid-apply (unchanged behaviour, now per-env).

---

## 4. VPC module (`modules/vpc`)

**Before**
- Created an `aws_vpc`, but then attached the IGW / subnets / route table to an
  **existing** `var.vpc_id` / `var.igw_id` (imported IDs) — inconsistent / buggy.
- All subnets public (`map_public_ip_on_launch = true`), tagged only for `elb`.
- No NAT gateway, single route table.

**After**
- Self-consistent: everything attaches to the VPC the module creates.
- **2 public + 2 private** subnets (input as `public_subnets` / `private_subnets`
  lists of `{cidr, az}`), spread across 2 AZs.
- Public subnets tagged `kubernetes.io/role/elb=1`; private subnets tagged
  `kubernetes.io/role/internal-elb=1`; both tagged `kubernetes.io/cluster/<name>=shared`.
- **1 EIP + 1 NAT gateway** (in the first public subnet) for private egress.
- **Two route tables**: public → IGW, private → NAT.
- Inputs `vpc_id` / `igw_id` **removed**; added input validations (valid CIDR, ≥2 subnets).
- Outputs: `vpc_id`, `public_subnet_ids`, `private_subnet_ids`.

---

## 5. EKS module (`modules/eks`)

**Before**
- Cluster v1.34, `endpoint_public_access = true`, `endpoint_private_access = false`,
  no `public_access_cidrs`.
- No control-plane logging, no secrets encryption.
- Single node group in the **same (public)** subnets.
- IRSA for EBS CSI + Fluent Bit; Fluent Bit policy used `Resource = "arn:aws:logs:*:*:*"`.
- An inline node-role policy also granted broad CloudWatch Logs access.
- Managed add-ons: only `aws-ebs-csi-driver`.

**After**
- **Private endpoint enabled** (`endpoint_private_access = true`) and public endpoint
  **restricted** via `public_access_cidrs`.
- **Control-plane logging** (`enabled_cluster_log_types` = all 5) + a dedicated
  `aws_cloudwatch_log_group` with retention.
- **Secrets envelope encryption** via a new `aws_kms_key` (rotation enabled) + alias,
  wired into `encryption_config`.
- Cluster ENIs span private+public subnets; the **node group runs in private subnets only**,
  with `node_labels` and `update_config`.
- Fluent Bit IAM scoped down to `arn:aws:logs:<region>:<account>:log-group:*`; the broad
  inline node-role logs policy was dropped (log shipping goes through Fluent Bit IRSA).
- **Managed add-ons added**: `vpc-cni`, `kube-proxy`, `coredns` (waits for nodes),
  plus the existing `aws-ebs-csi-driver`.
- **New IRSA roles**: AWS Load Balancer Controller (policy from upstream
  `alb_controller_iam_policy.json`) and ExternalDNS (Route53-scoped).
- ARNs made partition-aware (`local.partition`).
- New outputs: `oidc_provider_arn/url`, `alb_controller_role_arn`,
  `external_dns_role_arn`, `cluster_version`, `secrets_kms_key_arn`.

---

## 6. ECR module (`modules/ecr`)

**Before**
- `image_tag_mutability = "MUTABLE"`, `force_delete = true`, `scan_on_push = true`.
- No lifecycle policy. All variables inline in `main.tf`.

**After**
- `image_tag_mutability` (default **IMMUTABLE**) and `force_delete` (default **false**)
  are now variables — prod uses IMMUTABLE + no force-delete, stage uses MUTABLE.
- Added `aws_ecr_lifecycle_policy`: expire untagged images > 14 days, keep last 20 images
  (any tag — works with raw git-SHA tags).
- Variables moved into their own `variables.tf` (consistent with other modules).

---

## 7. DNS module (`modules/dns`) — NEW

- `data "aws_route53_zone"` looks up the **existing** hosted zone (`hosted_zone_name`,
  defaults to `domain`; use the parent zone when `domain` is a subdomain).
- `aws_acm_certificate` (DNS-validated) for `domain` + `*.<domain>` (wildcard covers the
  `argocd.` / `grafana.` subdomains).
- `aws_route53_record` validation records + `aws_acm_certificate_validation` (apply waits
  until the cert is ISSUED).
- Outputs: `zone_id`, `domain`, `acm_certificate_arn`.
- The ALB controller auto-discovers the cert by host, so the ARN is **not** hard-coded
  into any Ingress manifest.

---

## 8. Add-ons module (`modules/addons`) — NEW

Helm releases installed onto the cluster:
- **aws-load-balancer-controller** — turns `Ingress` objects into ALBs (SA annotated
  with the IRSA role; clusterName/region/vpcId set).
- **external-dns** — syncs Route53 records from Ingress hosts (`policy=upsert-only`,
  `domainFilters=[domain]`, `txtOwnerId=<cluster>`).
- **metrics-server** — `kubectl top` + HPA.
- **gp3 `StorageClass`** (encrypted, `WaitForFirstConsumer`) — not marked default to avoid
  clashing with the EKS gp2 default; monitoring references it explicitly.

---

## 9. ArgoCD + monitoring module (`modules/argocd`)

**Before**
- ArgoCD + kube-prometheus-stack via Helm, all `ClusterIP`.
- ArgoCD `server.insecure = true` (plain HTTP, reached only by `port-forward`).
- No persistence, no resource limits, no retention tuning.

**After**
- **ArgoCD** exposed at `argocd.<domain>` via ALB Ingress (HTTP→HTTPS redirect, ACM cert
  auto-discovered). `server.insecure` now only affects the in-VPC ALB→pod hop; the
  user-facing endpoint is HTTPS.
- **Grafana** exposed at `grafana.<domain>` via ALB Ingress; **gp3 persistence** (10Gi),
  resource limits, admin password via a `sensitive` variable.
- **Prometheus**: 15d retention, **gp3 persistent volume** (20Gi), resource requests/limits.
- `expose_via_ingress` toggle (default true) to fall back to `port-forward` if needed.
- Chart versions, storage class, sizes, retention all variabilized.
- Outputs: namespaces + `argocd_url` / `grafana_url`.

> Bug fixed during validation: the ingress blocks originally used a conditional
> (`expose ? {full} : {enabled=false}`) which Terraform rejected ("inconsistent
> conditional result types"). Replaced with a single object that toggles `enabled`.

---

## 10. GitOps (`gitops/`)

- **New** `gitops/k8s/ingress.yml` — internet-facing ALB Ingress: `/api` → `gateway:3001`,
  `/` → `frontend:3000`, 80→443 redirect, ACM cert auto-discovered by host. Added to
  `kustomization.yml`.

---

## 11. Removed

- The `module "lambda"` block (and `./modules/lambda` reference) — the module directory
  never existed and broke `terraform init`. Related lambda/bedrock variables dropped.
- Empty placeholder dirs `modules/external-dns` and `modules/alb-controller` (those
  concerns live in `modules/addons` + `modules/eks`).

---

## 12. Still your responsibility (outside this Terraform)

1. **State bucket hardening** (one-time): enable versioning + SSE + block-public-access on
   `tf-devops-ai-statefile`.
2. **Domain**: the Route53 hosted zone must already exist; set real values for `domain` /
   `hosted_zone_name` in the tfvars (placeholders are `example.com`).
3. **`public_access_cidrs`**: tighten from `0.0.0.0/0` to your office/VPN CIDRs for prod.
4. **`grafana_admin_password`**: supply via `TF_VAR_grafana_admin_password` (not committed).
5. **Frontend image** bakes `REACT_APP_API_URL=http://gateway:3001/api` (cluster-internal);
   for browser access it should be `https://<domain>/api` — rebuild the image via CI.
6. **ECR account id** in the manifests (`018442532737...`) is environment-specific.

---

## 13. How to deploy (per env)

```bash
cd Infrastructure/stage          # or prod
export TF_VAR_grafana_admin_password='...'
terraform init
terraform plan  -var-file=stage.tfvars
terraform apply -var-file=stage.tfvars
```
