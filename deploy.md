# Deploying the Boutique App on AWS EKS

A step-by-step guide to deploy this microservices application on Amazon EKS with
CI/CD (GitHub Actions), GitOps (ArgoCD), and monitoring (Prometheus + Grafana).

Follow the steps in order. Each section says **what** you are doing and **why**.

> **Two deployment modes — pick one with the `enable_dns` flag in the tfvars:**
>
> - **Domainless (default in this repo, `enable_dns = false`)** — no domain needed. Skips
>   ACM/Route53/ExternalDNS; the app, ArgoCD, and Grafana are reached over **plain HTTP**
>   on AWS-generated load-balancer hostnames. No TLS. Fastest way to a working cluster.
> - **With a domain (`enable_dns = true`)** — the full HTTPS setup: ACM cert + Route53 +
>   ExternalDNS serve the app and the `argocd.`/`grafana.` subdomains over TLS.
>
> Steps below note where the two modes differ. Sub-steps marked **[domain mode]** apply
> only when `enable_dns = true`; **[domainless]** applies only when `enable_dns = false`.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [What We Changed (and Why)](#2-what-we-changed-and-why)
3. [Provision the Infrastructure (Terraform)](#3-provision-the-infrastructure-terraform)
4. [Connect to the Cluster](#4-connect-to-the-cluster)
5. [Build & Push Images (CI/CD)](#5-build--push-images-cicd)
   - [Secrets (AWS Secrets Manager)](#secrets-aws-secrets-manager)
6. [Deploy the App Manifests](#6-deploy-the-app-manifests)
7. [Set Up ArgoCD (GitOps)](#7-set-up-argocd-gitops)
8. [Seed the Database](#8-seed-the-database)
9. [Test the Application](#9-test-the-application)
10. [Monitoring (Prometheus & Grafana)](#10-monitoring-prometheus--grafana)
11. [Troubleshooting](#11-troubleshooting)
12. [AIOps Assistant (Kira)](#12-aiops-assistant-kira)

---

## 1. Prerequisites

Install and configure these before you start:

| Tool       | Check it works            |
| ---------- | ------------------------- |
| AWS CLI    | `aws sts get-caller-identity` |
| Terraform  | `terraform version` (**≥ 1.10** — required for S3-native state locking) |
| kubectl    | `kubectl version --client`|
| Helm       | `helm version`            |
| Git        | `git --version`           |

You also need:

- An AWS account with permission to create VPC, EKS, ECR, KMS, ACM, Route53, and IAM resources.
- A GitHub account (to host this repo and run the CI pipeline).
- The AWS region used in this guide: **`ap-south-1`** (change it everywhere if you use another).
- **[domain mode only]** A **registered domain with an existing Route53 hosted zone** —
  Terraform issues the ACM certificate into it, and ExternalDNS creates the app records
  there. **Not needed for domainless** (`enable_dns = false`), which is the default here.
- A **one-time hardening of the state bucket** `tf-devops-ai-statefile`: enable versioning,
  default SSE, and block-public-access.
- A Grafana admin password exported as an env var before you apply:
  `export TF_VAR_grafana_admin_password='choose-a-strong-password'`.

> **Layout note:** the Terraform is now split into per-environment roots —
> `Infrastructure/stage/` and `Infrastructure/prod/` — that share the modules in
> `Infrastructure/modules/`. See `Infrastructure/changes.md` for the full before/after.

---

## 2. What We Changed (and Why)

This repo was tuned so the deployment actually works end-to-end. Key changes:

**Kubernetes manifests (`gitops/`)**

1. Replaced the `<AWS_ACCOUNT_ID>` placeholder in all 7 Deployment images with the
   real account ID + region (so Kubernetes can pull from your ECR).
2. Fixed `order-service` Service port `3002 → 3004` — it pointed at the wrong port,
   which broke gateway → order-service (cart/checkout) traffic.
3. Added a named `http` port and a `monitored: "true"` label to all 6 backend Services.
4. Widened the `ServiceMonitor` selector from `app: gateway` to `monitored: "true"`
   so Prometheus scrapes **all** backend services, not just the gateway.

**Terraform (`Infrastructure/`) — reworked for production**

5. Split into per-env roots (`stage/`, `prod/`) over shared `modules/`; state is now
   encrypted with per-env keys and S3-native locking (`use_lockfile`).
6. Networking: 2 public + 2 private subnets across 2 AZs, 1 NAT gateway; **worker nodes
   run in private subnets**.
7. EKS hardened: private + CIDR-restricted public API endpoint, control-plane logging,
   KMS secrets encryption, managed add-ons (vpc-cni/coredns/kube-proxy/ebs-csi).
8. Internet access: AWS Load Balancer Controller + ExternalDNS + an ACM cert serve the
   app and the `argocd`/`grafana` subdomains over HTTPS.

> The full before/after for every module is in **`Infrastructure/changes.md`**.

---

## 3. Provision the Infrastructure (Terraform)

**What:** Create the VPC (public + private subnets, NAT), EKS cluster, node group, ECR
repos, ACM cert, and install the add-ons + ArgoCD + monitoring via Helm.
**Why:** This is the foundation everything else runs on.

First, open the env's tfvars (`stage/stage.tfvars` or `prod/prod.tfvars`) and restrict
`public_access_cidrs` to your office/VPN ranges. Then choose your mode:

- **[domainless]** Leave `enable_dns = false` (the shipped default). No `domain` /
  `hosted_zone_name` needed — leave them as `""`.
- **[domain mode]** Set `enable_dns = true` and fill in real `domain` / `hosted_zone_name`
  (an existing Route53 zone).

```bash
cd Infrastructure/stage          # or Infrastructure/prod
export TF_VAR_grafana_admin_password='choose-a-strong-password'

terraform init                          # providers + S3 backend (per-env state key)
terraform plan  -var-file=stage.tfvars  # review what will be created
terraform apply -var-file=stage.tfvars  # type "yes" to confirm
```

> **Domainless** skips the ACM/Route53/ExternalDNS resources, so `apply` is also a bit
> faster (no waiting on certificate validation).

> This takes ~15–20 minutes (EKS, node group, and ACM validation are slow).

---

## 4. Connect to the Cluster

**What:** Point `kubectl`/`helm` at your new cluster.
**Why:** Terraform uses its own credentials; your local tools need their own kubeconfig.

```bash
# cluster name matches the env: boutique-stage or boutique-prod
aws eks update-kubeconfig --name boutique-stage --region ap-south-1
```

Verify the cluster is up:

```bash
kubectl get nodes          # expect 2 nodes (stage) / 3 (prod), STATUS Ready
kubectl get pods -A        # core pods Running (incl. aws-load-balancer-controller, external-dns)
kubectl get pods -n argocd # ArgoCD pods Running
```

---

## 5. Build & Push Images (CI/CD)

**What:** Let GitHub Actions build each service image and push it to ECR.
**Why:** Kubernetes pulls these images from ECR — they must exist first.

1. In your GitHub repo: **Settings → Secrets and variables → Actions** and add the
   secrets your `ci.yml` expects (AWS credentials, account ID, region).
2. Push to the branch that triggers the pipeline:

   ```bash
   git add .
   git commit -m "trigger CI"
   git push
   ```

3. Watch the run under the repo's **Actions** tab until all images are pushed to ECR.

---

## Secrets (AWS Secrets Manager)

**What:** Store the app's credentials in AWS Secrets Manager and let External
Secrets Operator (ESO) sync them into the cluster as the `boutique-secrets` Secret.
**Why:** Keeps real credentials out of Git. Terraform already installed ESO and a
`ClusterSecretStore` named `aws-secretsmanager` (the `addons` module, toggled by
`enable_external_secrets`); this step just creates the secret it reads.

> **Which secret path are you on?** The Helm app values
> (`helm/apps/boutique.yaml`) default to the AWS SM path — `secret.enabled: false`
> plus an `externalSecret` block. If instead you use the plaintext
> `secret.stringData` path (fine for a throwaway demo, not real credentials),
> skip this section.

1. **Create one JSON secret** whose keys match what the services expect. The IRSA
   policy allows any secret in the account/region by default, so each app can own
   its own path (`boutique/…`, `devboard/…`); set `secrets_manager_path_prefix` in
   the eks module to restrict it. Use the **region you deployed to** — the store
   reads AWS SM in that region (the prod tfvars use `us-west-2`):

   ```bash
   aws secretsmanager create-secret \
     --name boutique/app-secrets \
     --region us-west-2 \
     --secret-string '{
       "POSTGRES_DB": "postgres",
       "POSTGRES_USER": "postgres",
       "POSTGRES_PASSWORD": "choose-a-strong-password",
       "AUTH_DB_URL": "postgresql://postgres:<pw>@boutique-postgres:5432/auth_db",
       "PRODUCTS_DB_URL": "postgresql://postgres:<pw>@boutique-postgres:5432/products_db",
       "ORDERS_DB_URL": "postgresql://postgres:<pw>@boutique-postgres:5432/orders_db",
       "USERS_DB_URL": "postgresql://postgres:<pw>@boutique-postgres:5432/users_db"
     }'
   ```

   The key names above are exactly what `helm/apps/boutique.yaml` references
   (`envFromSecret[].key`, `passwordKey`). `dataFrom.extract` pulls **all** of them
   into `boutique-secrets`, so you don't map them one by one.

2. **Verify** the store is healthy and ESO created the Secret (after the app syncs):

   ```bash
   kubectl get clustersecretstore aws-secretsmanager   # STATUS should be Valid
   kubectl get externalsecret -n boutique              # READY should be True
   kubectl get secret boutique-secrets -n boutique     # created by ESO, not Git
   ```

> **Rotation:** update the value in AWS Secrets Manager; ESO re-syncs within its
> `refreshInterval` (1h) — no redeploy. Roll the pods if they cache the old value.

> **Troubleshooting:** `SecretSyncedError` / store not `Valid` usually means IRSA
> isn't wired — check the ESO pod logs (`kubectl logs -n external-secrets
> deploy/external-secrets`), that the SA carries the role annotation, and that the
> secret id sits under the `boutique/` prefix the policy allows.

---

## 6. Deploy the App Manifests

**What:** Apply all Kubernetes resources at once with Kustomize.
**Why:** One command creates the namespace, secrets, database, and every service.

> **⚠️ First, set your ECR registry.** All app images are pulled from your ECR, whose
> host is `<account-id>.dkr.ecr.<region>.amazonaws.com`. This is defined in **one place** —
> the `ecr-config` literal in `gitops/kustomization.yml`. Before applying, edit that single
> line so the account ID and region match the account/region you ran Terraform in (the ECR
> repos are created there). Kustomize rewrites all 7 Deployment images from this value:
>
> ```yaml
> # gitops/kustomization.yml
> configMapGenerator:
>   - name: ecr-config
>     literals:
>       - registry=018442532737.dkr.ecr.us-west-2.amazonaws.com   # <-- your account + region
> ```
>
> Verify the rewrite before applying (images should show your account/region, Postgres unchanged):
>
> ```bash
> kubectl kustomize gitops/ | grep 'image:'
> ```

```bash
kubectl apply -k gitops/
```

This applies ~12 resources: namespace, secret, Postgres (StatefulSet + Service),
6 backend Deployments, the frontend, the ServiceMonitor, the Grafana dashboard,
and the generated DB-dump ConfigMap.

Check the pods:

```bash
kubectl get pods -n boutique
```

> Some pods may show errors at first (old image tag, or the database isn't seeded yet).
> ArgoCD (next step) keeps them in sync, and the DB restore (step 8) fixes the rest.

> **Before public access works, note the frontend/ingress wiring — it differs by mode:**
>
> `gitops/k8s/ingress.yml` holds **both modes in one file** — the domainless block is
> active by default; the domain block sits next to it, commented. Switch between them with
> the marked comment/uncomment edits (details per mode below).
>
> **[domainless]**
> 1. No edit needed — the file ships host-less and HTTP-only, so the ALB answers on its own
>    AWS hostname. Get it after deploy with `kubectl get ingress boutique -n boutique`.
> 2. The frontend image bakes `REACT_APP_API_URL=http://gateway:3001/api` (cluster-internal,
>    unreachable from a browser). You won't know the ALB hostname until the ingress is up, so
>    this is a two-pass process: deploy first, read the ALB hostname, then rebuild/push the
>    frontend via CI with `REACT_APP_API_URL=http://<alb-hostname>/api` and redeploy. The app
>    shell loads before that; its API calls just won't work until the rebuild.
>
> **[domain mode]** (needs `enable_dns = true` so the ACM cert exists)
> 1. In `gitops/k8s/ingress.yml`, make the **3 marked comment/uncomment edits**:
>    - comment the `[DOMAINLESS]` `listen-ports` line;
>    - uncomment the `[DOMAIN]` `listen-ports` + `ssl-redirect` lines;
>    - uncomment the `host:` line and set your real domain (must match an ACM cert SAN —
>      the apex `<domain>` or a single-level `*.<domain>`).
>
>    Reverse those 3 edits to return to domainless.
> 2. Rebuild/push the frontend image with `REACT_APP_API_URL=https://<your-domain>/api` via
>    CI so the SPA calls the public ALB over HTTPS.

---

## 7. Set Up ArgoCD (GitOps)

**What:** Connect ArgoCD to your Git repo so it deploys and self-heals from Git.
**Why:** After this, changes pushed to Git roll out automatically — no manual `kubectl`.

### 7.1 Open the ArgoCD UI

**[domainless]** ArgoCD is exposed over **plain HTTP** via a `LoadBalancer` service. Give it
a minute or two after apply for the load balancer to provision, then get its hostname:

```bash
kubectl get svc argocd-server -n argocd    # copy the EXTERNAL-IP (an AWS LB hostname)
```

Open `http://<that-hostname>` in your browser.

**[domain mode]** ArgoCD is exposed over HTTPS at **`https://argocd.<your-domain>`** — an
internet-facing ALB (created by the Load Balancer Controller) terminates TLS with the ACM
cert, and ExternalDNS creates the DNS record automatically. Give it a couple of minutes for
the ALB to provision and DNS to propagate, then verify:

```bash
kubectl get ingress -A        # the argocd ingress should show an ALB ADDRESS
```

> **Offline fallback** (either mode, if the load balancer isn't ready yet): `kubectl
> port-forward svc/argocd-server -n argocd 8080:80` and open `http://localhost:8080`.

### 7.2 Get the admin password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

Log in:

- **User:** `admin`
- **Password:** _(output of the command above)_

### 7.3 Connect your Git repo

In the UI: **Settings → Repositories → Connect repo using HTTPS**

- Project: `default` (or your project name)
- Repository URL: your repo's HTTPS URL
- Username: your GitHub username
- Password: a **GitHub PAT** (Personal Access Token) with `repo` read scope

### 7.4 Register the application

```bash
kubectl apply -f gitops/argo-cd.yml -n argocd
```

Then open the ArgoCD UI and **Sync** to apply the latest changes.

> **Auto-sync (optional):** to make ArgoCD deploy and self-heal automatically, set
> `syncPolicy.automated` (with `prune` + `selfHeal`) in `gitops/argo-cd.yml` and
> re-apply the command above.

---

## 8. Seed the Database

**What:** Run a Job that loads the database dump into Postgres.
**Why:** Backend services (except Postgres and frontend) crash until their databases exist.

> **Apply this only AFTER the Postgres pod is `1/1` Ready:**

```bash
kubectl get pods -n boutique -l app=postgres   # wait for READY 1/1
kubectl apply -f gitops/k8s/database/restore-job.yml
kubectl get pods -n boutique
```

If the restore Job ran too early, delete the **Job** (not just the pods) and re-apply:

```bash
kubectl delete job boutique-db-restore -n boutique
kubectl apply -f gitops/k8s/database/restore-job.yml
```

Once the restore completes, delete any crashed backend pods so they restart against
the seeded database:

```bash
kubectl delete pod -n boutique --field-selector=status.phase!=Running
kubectl get pods -n boutique   # all should become Running / Ready
```

---

## 9. Test the Application

**What:** Reach the app over its public load balancer (or port-forward as a fallback).
**Why:** The app Ingress publishes an internet-facing ALB; `/` goes to the frontend and
`/api` to the gateway.

**[domainless]** Get the ALB hostname and open it over HTTP:

```bash
kubectl get ingress boutique -n boutique   # copy the ADDRESS (an AWS ALB hostname)
```

- App:      `http://<alb-hostname>`
- API:      `http://<alb-hostname>/api`

> The frontend shell loads, but its API calls fail until you rebuild the frontend image with
> `REACT_APP_API_URL=http://<alb-hostname>/api` (see the note in step 6) — the default bakes
> the cluster-internal `http://gateway:3001/api`, which a browser can't reach.

**[domain mode]** Once the ALB + DNS are ready:

- App:      <https://your-domain>
- API:      <https://your-domain/api>

> In domain mode, make sure `gitops/k8s/ingress.yml` has your real domain in a `host:` rule
> and the frontend image's `REACT_APP_API_URL` points at `https://<your-domain>/api`.

Offline fallback (ClusterIP via port-forward, one per terminal):

```bash
kubectl port-forward svc/gateway  -n boutique 3001:3001
kubectl port-forward svc/frontend -n boutique 3000:3000
# then http://localhost:3000 and http://localhost:3001
```

To prove ArgoCD self-heals, delete a deployment and watch it come back:

```bash
kubectl get deployments -n boutique
kubectl delete deployment <name> -n boutique
# ArgoCD recreates it (auto if syncPolicy.automated is set, else Sync in the UI)
kubectl get pods -n boutique
```

---

## 10. Monitoring (Prometheus & Grafana)

**What:** Open the dashboards that show app and cluster metrics.
**Why:** Confirm metrics are flowing and watch service health.

**[domainless]** Grafana is exposed over **plain HTTP** via a `LoadBalancer` service. Get
its hostname and open it over HTTP:

```bash
kubectl get svc kube-prometheus-stack-grafana -n monitoring   # copy the EXTERNAL-IP
```

Open `http://<that-hostname>`.

**[domain mode]** Grafana is exposed over HTTPS at **`https://grafana.<your-domain>`** (ALB
Ingress + ACM, DNS via ExternalDNS).

Grafana login:

- **User:** `admin`
- **Password:** the value you set in `TF_VAR_grafana_admin_password` before `apply`.

Prometheus stays internal — reach it via port-forward when needed:

```bash
kubectl get pods -n monitoring
kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090
# then http://localhost:9090
```

In Grafana → **Dashboards**, a pre-built dashboard for the services is already loaded.

---

## 11. Troubleshooting

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| `terraform apply` fails with a 401 / "asked for credentials" | EKS token expired mid-apply | Already mitigated via `exec` auth. Re-run `terraform apply -var-file=<env>.tfvars`. |
| Helm: `cannot re-use a name that is still in use` | Release exists but not in TF state | `terraform import 'module.argocd.helm_release.<name>' <namespace>/<release>` |
| Helm: `another operation ... in progress` | Stuck/`pending` release | `helm uninstall <release> -n <ns>` → `terraform state rm ...` → `terraform apply` |
| Ingress has no `ADDRESS` | ALB not provisioned | Check `kubectl -n kube-system logs deploy/aws-load-balancer-controller`; confirm the SA has the IRSA role annotation and subnets are tagged for ELB. |
| **[domainless]** ArgoCD/Grafana `svc` EXTERNAL-IP stuck `<pending>` | LoadBalancer still provisioning, or public subnets not tagged | Wait 1–2 min; then check the public subnets carry `kubernetes.io/role/elb=1` and the cluster has public subnets to place the LB in. |
| **[domainless]** ArgoCD/Grafana LB hostname has an EXTERNAL-IP but won't load in a browser (times out); `port-forward` works | The AWS LB Controller defaults a bare `type: LoadBalancer` NLB to **internal** (private IPs) | The `argocd` and `monitoring` modules each set `scheme: internet-facing` via `admin_lb_annotations` (ArgoCD in `modules/argocd`, Grafana in `modules/monitoring`); re-run `terraform apply -var-file=<env>.tfvars`. Scheme is immutable, so the NLB is recreated with a **new** hostname — re-read it with `kubectl get svc argocd-server -n argocd` / `... kube-prometheus-stack-grafana -n monitoring`. Confirm with `nslookup <hostname>` (private `10.x` = still internal). |
| Domain doesn't resolve to the ALB | ExternalDNS not creating records | Check `kubectl -n kube-system logs deploy/external-dns`; verify `domainFilters` matches your domain and the hosted zone exists. |
| HTTPS cert error / no padlock | ACM cert not ISSUED or host mismatch | The cert must be `ISSUED` and cover the Ingress host (apex + `*.<domain>`). Check ACM in `ap-south-1`. |
| Backend pods crash-looping | Database not seeded | Run the restore Job (step 8), then delete the crashed pods. |
| `kubectl`/`helm` → `localhost:8080 connection refused` | No kubeconfig for the cluster | `aws eks update-kubeconfig --name boutique-stage --region ap-south-1` (or `boutique-prod`) |

---

## Teardown

**1. Destroy the infrastructure (EKS, VPC, ECR, KMS, ACM, IAM) for the env:**

```bash
cd Infrastructure/stage          # or Infrastructure/prod
terraform destroy -var-file=stage.tfvars
```

> Any ALBs (from Ingresses) or classic/NLB load balancers (from `LoadBalancer` services)
> left behind may need manual cleanup if `kubectl delete -k gitops/` and
> `kubectl delete svc argocd-server -n argocd` weren't run first — `terraform destroy` won't
> remove load balancers that Kubernetes created. **[domain mode]** also clean up any
> ExternalDNS-created Route53 records.

**2. Remove the kubeconfig entries that `aws eks update-kubeconfig` added:**

```bash
kubectl config get-contexts                 # find the cluster's context name
kubectl config delete-context <name>        # the context (binds cluster + user)
kubectl config delete-cluster <name>        # the API server endpoint + CA
kubectl config delete-user <name>           # the auth/exec credentials
```

> All three usually share the same ARN-style name, so it's the same name used three times.

