# Deploying With a Domain vs. Without a Domain

This repo can be deployed in **two modes**, controlled by a single flag — `enable_dns` in
the env's tfvars (`Infrastructure/stage/stage.tfvars` or `Infrastructure/prod/prod.tfvars`):

| | **With a domain** (`enable_dns = true`) | **Without a domain** (`enable_dns = false`) |
| --- | --- | --- |
| TLS / HTTPS | Yes (ACM cert) | No — plain HTTP |
| DNS | Route53 + ExternalDNS (auto records) | None — use raw AWS LB hostnames |
| App entry | ALB Ingress at `https://<domain>` | ALB Ingress at `http://<alb-hostname>` |
| ArgoCD | HTTPS Ingress `argocd.<domain>` | HTTP `LoadBalancer` service |
| Grafana | HTTPS Ingress `grafana.<domain>` | HTTP `LoadBalancer` service |
| Extra AWS cost | ACM (free) + Route53 zone (~$0.50/mo) | None beyond the load balancers |
| Prerequisite | Registered domain + Route53 hosted zone | Nothing extra |

> Full step-by-step deployment lives in **`deploy.md`**. This file is the focused
> **"what's different between the two modes"** reference.

---

## Part A — WITH a Domain (`enable_dns = true`)

This is the production path: HTTPS everywhere, real hostnames, auto-managed DNS.

### A.1 Prerequisites (in addition to the usual AWS CLI / Terraform / kubectl / Helm)

1. A **registered domain** (e.g. `example.com`) — registered anywhere (Route53, GoDaddy,
   Namecheap, …).
2. An **existing Route53 public hosted zone** for that domain, and the domain's registrar
   **NS records pointing at that zone**. Terraform looks the zone up; it does **not** create
   or register it.
   - If your domain is registered outside AWS, create a hosted zone in Route53 and copy its
     4 NS records into your registrar's nameserver settings. Wait for propagation.
   - Verify: `aws route53 list-hosted-zones-by-name --dns-name example.com`
3. Decide the app hostname:
   - Use the **apex** (`example.com`) → set `domain = "example.com"`, `hosted_zone_name = "example.com"`.
   - Use a **subdomain** (`stage.example.com`) → set `domain = "stage.example.com"`,
     `hosted_zone_name = "example.com"` (the **parent** zone that actually exists).

> The ACM cert is issued for `domain` **plus** `*.<domain>` (a wildcard), which is what
> covers the `argocd.` and `grafana.` subdomains automatically.

### A.2 Set the tfvars

Edit `Infrastructure/stage/stage.tfvars` (or `prod/prod.tfvars`):

```hcl
enable_dns       = true
domain           = "stage.example.com"   # your real domain / subdomain
hosted_zone_name = "example.com"         # the EXISTING Route53 zone

# still restrict this for real use:
public_access_cidrs = ["<your.office.ip>/32"]
```

### A.3 Apply the infrastructure

```bash
cd Infrastructure/stage          # or Infrastructure/prod
export TF_VAR_grafana_admin_password='choose-a-strong-password'

terraform init
terraform plan  -var-file=stage.tfvars
terraform apply -var-file=stage.tfvars
```

What this does that domainless does **not**:
- Creates an **ACM certificate** for `domain` + `*.<domain>` (DNS-validated).
- Writes the **validation CNAME records** into your hosted zone and **waits until the cert
  is ISSUED** (this is why the zone must already exist and resolve — otherwise apply hangs).
- Installs **ExternalDNS**, scoped to your domain, so Ingress hosts become Route53 records
  automatically.
- Configures the ArgoCD + Grafana Helm releases with **HTTPS ALB Ingresses** on their
  subdomains.

> Takes ~15–20 min (EKS + node group + ACM validation).

### A.4 Point kubectl at the cluster

```bash
aws eks update-kubeconfig --name boutique-stage --region ap-south-1
kubectl get nodes
```

### A.5 Edit the app Ingress for the domain

`gitops/k8s/ingress.yml` ships **domainless** (HTTP-only, no host). For domain mode, edit it
to add HTTPS and your host rule:

```yaml
metadata:
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    # re-add the 443 listener + HTTP->HTTPS redirect:
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    alb.ingress.kubernetes.io/healthcheck-path: /
    alb.ingress.kubernetes.io/group.name: boutique
spec:
  ingressClassName: alb
  rules:
    - host: stage.example.com      # <-- must match the ACM cert (apex or a *.<domain> SAN)
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service: { name: gateway, port: { number: 3001 } }
          - path: /
            pathType: Prefix
            backend:
              service: { name: frontend, port: { number: 3000 } }
```

> The ALB controller **auto-discovers** the ACM cert by matching the `host:` to a cert SAN —
> you do **not** hard-code the certificate ARN.

### A.6 Build & push images (CI), then deploy

1. Add the GitHub Actions secrets (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
   `AWS_ACCOUNT_ID`) and push to `main` so `ci.yml` builds and pushes all 7 images to ECR.
2. Rebuild the **frontend** with the public API URL so the browser SPA calls the real host:
   `REACT_APP_API_URL=https://stage.example.com/api` (set as a CI build arg / env).
3. Deploy:

   ```bash
   kubectl apply -k gitops/
   ```

### A.7 Seed the database

```bash
kubectl get pods -n boutique -l app=postgres        # wait for READY 1/1
kubectl apply -f gitops/k8s/database/restore-job.yml
kubectl delete pod -n boutique --field-selector=status.phase!=Running
```

### A.8 Access everything (HTTPS, auto-DNS)

ExternalDNS creates the records; give it a couple of minutes, then:

- **App:**     `https://stage.example.com`
- **API:**     `https://stage.example.com/api`
- **ArgoCD:**  `https://argocd.stage.example.com`
- **Grafana:** `https://grafana.stage.example.com`

```bash
kubectl get ingress -A        # each should show an ALB ADDRESS
```

ArgoCD admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

Grafana: user `admin`, password = your `TF_VAR_grafana_admin_password`.

### A.9 Terraform outputs (domain mode)

```bash
terraform output app_url            # https://<domain>
terraform output argocd_url         # https://argocd.<domain>
terraform output grafana_url        # https://grafana.<domain>
terraform output acm_certificate_arn
terraform output route53_zone_id
```

---

## Part B — WITHOUT a Domain (`enable_dns = false`) — the shipped default

Same flow, minus DNS/TLS. Nothing to register.

### B.1 tfvars

```hcl
enable_dns       = false
domain           = ""
hosted_zone_name = ""
```

### B.2 Apply + connect

```bash
cd Infrastructure/stage
export TF_VAR_grafana_admin_password='choose-a-strong-password'
terraform init && terraform apply -var-file=stage.tfvars
aws eks update-kubeconfig --name boutique-stage --region ap-south-1
```

Skips the `dns` module (no ACM/Route53) and ExternalDNS. ArgoCD + Grafana come up as
**HTTP `LoadBalancer` services**.

### B.3 App Ingress — no edit needed

`gitops/k8s/ingress.yml` already ships host-less + HTTP-only, so the ALB answers on its own
AWS hostname. Just `kubectl apply -k gitops/` (after images are pushed via CI).

### B.4 Find your public URLs (HTTP)

```bash
kubectl get ingress boutique -n boutique                       # app ALB hostname
kubectl get svc argocd-server -n argocd                        # ArgoCD LB hostname
kubectl get svc kube-prometheus-stack-grafana -n monitoring    # Grafana LB hostname
```

- **App:**     `http://<alb-hostname>`
- **ArgoCD:**  `http://<argocd-lb-hostname>`
- **Grafana:** `http://<grafana-lb-hostname>`

### B.5 Frontend API URL (two-pass)

You can't know the ALB hostname until the Ingress exists. Deploy first, read the hostname,
then rebuild the frontend via CI with `REACT_APP_API_URL=http://<alb-hostname>/api` and
redeploy. Until then the app shell loads but its API calls fail.

---

## Switching from domainless → domain later

1. Register the domain + create/verify the Route53 hosted zone (A.1).
2. Set `enable_dns = true` + `domain` + `hosted_zone_name` in the tfvars.
3. `terraform apply -var-file=<env>.tfvars` (adds ACM + ExternalDNS; ArgoCD/Grafana move to
   HTTPS Ingress — Terraform reconciles this automatically).
4. Edit `gitops/k8s/ingress.yml` to add the `host:` rule + 443 listener (A.5) and
   `kubectl apply -k gitops/`.
5. Rebuild the frontend with the `https://<domain>/api` API URL.
6. Delete the old domainless `LoadBalancer` services if they linger:
   `kubectl delete svc argocd-server -n argocd` (Helm/Terraform recreate them as ClusterIP
   behind the Ingress on the next apply).

---

## Teardown (either mode)

```bash
kubectl delete -k gitops/                     # remove app + its ALB first
kubectl delete svc argocd-server -n argocd    # remove any LB services (domainless)
cd Infrastructure/stage
terraform destroy -var-file=stage.tfvars
```

> `terraform destroy` does **not** delete load balancers that Kubernetes created — delete the
> Ingresses/Services first, or clean up the leftover ELBs/ALBs manually. **[domain mode]**
> also remove any ExternalDNS-created Route53 records.
