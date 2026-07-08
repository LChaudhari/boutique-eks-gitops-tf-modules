# Reusable app deployment — generic Helm chart + ArgoCD ApplicationSet

Deploy **any** microservices app to this EKS cluster by writing **one values
file**. The Kubernetes templates are written once and never change per app.

```
helm/
├── charts/microservice-app/   # the generic chart (templates never change)
│   ├── Chart.yaml
│   ├── values.yaml            # documented defaults = the schema/reference
│   └── templates/             # deployment, service, secret, ingress,
│                              # servicemonitor, database, db-seed-job
├── apps/
│   └── boutique.yaml          # one app instance (DATA ONLY)
├── appset.yaml                # ArgoCD ApplicationSet: 1 App per apps/*.yaml
└── README.md
```

## What the chart renders

From a single values file it produces, all driven by data:

- a **Deployment + Service** for every entry in `services:` (env, secret-env,
  ports, per-service annotations, image from `registry/<name>:<tag>`)
- one **Secret** (`secret.stringData`)
- an **ALB Ingress** (`ingress.rules`, HTTP or HTTPS/host)
- a **ServiceMonitor** in the `monitoring` namespace (scrapes every Service
  labelled `monitored: "true"`)
- **Postgres** (StatefulSet + headless Service) when `database.mode: in-cluster`,
  or **nothing** when `database.mode: external` (you point at RDS instead)
- an optional one-time **DB seed Job** (`database.seed`)
- a **namespace-wide NetworkPolicy** (`networkPolicy.enabled`) — one baseline for
  every pod in the app namespace

## NetworkPolicy — one baseline for every app

`networkPolicy.enabled: true` renders a **single** policy with `podSelector: {}`, so
it applies to every service and the DB in the app's namespace — that's the "common
policy for all apps": each app that uses this chart gets the same baseline. The model
is **default-deny ingress**, then an allow-list:

| Value | Effect |
| --- | --- |
| `allowIntraNamespace` | pods in the namespace can reach each other + the DB |
| `allowMonitoring` / `monitoringNamespace` | Prometheus in the monitoring namespace can scrape metrics |
| `allowIngressCidrs` | VPC CIDR(s) so the ALB (`target-type: ip`) can reach pods |
| `extraIngress` | verbatim extra ingress rules |
| `restrictEgress` | also lock down egress (off by default — egress stays open) |
| `allowDnsEgress` / `allowEgressCidrs` / `extraEgress` | egress allow-list when `restrictEgress` is on |

> **Enforcement prerequisite (EKS):** NetworkPolicy is only enforced when the VPC CNI
> network-policy feature is on. The `eks` module enables it on the `vpc-cni` add-on
> (`configuration_values: enableNetworkPolicy=true`) — **re-run `terraform apply`** for
> an existing cluster. Without a policy-enforcing CNI the object is created but ignored.

`boutique.yaml` enables it with `allowIngressCidrs: [10.0.0.0/8]` (covers both the stage
`10.10.0.0/16` and prod `10.20.0.0/16` VPCs; narrow it to your exact `vpc_cidr` for a
tighter policy). To also restrict egress, set `restrictEgress: true` and list the CIDRs
your services need (AWS Secrets Manager, ECR, RDS, …).

## Onboard a new app (the whole workflow)

1. Copy `apps/boutique.yaml` to `apps/<yourapp>.yaml`.
2. Change the data: `appName`, `global.namespace`, `global.registry`,
   the `services:` list (names/ports/env), `ingress.rules`, `secret.stringData`.
3. Commit & push. The ApplicationSet creates and syncs a new ArgoCD Application
   automatically — no other file changes.

## Try it locally first (no cluster needed)

```bash
# render boutique and eyeball the output
helm template boutique helm/charts/microservice-app \
  -f helm/apps/boutique.yaml --namespace boutique

# lint
helm lint helm/charts/microservice-app -f helm/apps/boutique.yaml
```

## Install (pick one)

**Plain Helm (imperative):**
```bash
helm upgrade --install boutique helm/charts/microservice-app \
  -f helm/apps/boutique.yaml --namespace boutique --create-namespace
```

**ArgoCD ApplicationSet (GitOps — recommended):**
```bash
# edit repoURL in appset.yaml to your repo, then:
kubectl apply -f helm/appset.yaml -n argocd
```

## Domainless vs domain (HTTPS) — a values-only switch

The chart is mode-agnostic; the app's Ingress mode is pure data in its values
file. `boutique.yaml` ships in **domainless** mode (plain HTTP on the ALB's own
AWS hostname). To move an app to **domain / HTTPS** mode, edit only the `ingress`
block — no template changes:

| | Domainless (default) | Domain / HTTPS |
| --- | --- | --- |
| `ingress.host` | `""` | `shop.example.com` (must match an ACM cert SAN) |
| `listen-ports` annotation | `'[{"HTTP":80}]'` | `'[{"HTTP":80},{"HTTPS":443}]'` |
| `ssl-redirect` annotation | absent | `'443'` |

In `boutique.yaml` these three lines are pre-written with comment/uncomment
markers — flip the comments to switch, and set `host:`. Then rebuild the
frontend image with `REACT_APP_API_URL=https://<host>/api`.

> Scope: this only controls the **app's** Ingress. The `argocd.`/`grafana.`
> HTTPS exposure is handled by **Terraform** (`enable_dns` in the tfvars), not
> this chart. Full domain mode = `enable_dns = true` *and* `ingress.host` set here.

## Moving the DB to AWS RDS later

In the app's values file:

```yaml
database:
  mode: external
  host: myapp.abc123.us-west-2.rds.amazonaws.com
```

The chart stops rendering the in-cluster StatefulSet — no template edits. Then
repoint the `*_DB_URL` values (and `database.passwordSecret`) at the RDS host.

## Secrets from AWS Secrets Manager (instead of plaintext in git)

`secret.stringData` renders a Kubernetes Secret **from values committed to git** —
fine for a demo, not for real credentials. The chart reads Kubernetes Secrets
(`database.passwordSecret`/`passwordKey`, and each service's
`envFromSecret[].secretName`); it does **not** read AWS Secrets Manager directly.

The chart has **native ESO support**: enable the `externalSecret` block and it
renders an `ExternalSecret` that syncs AWS Secrets Manager into a K8s Secret for
you — no hand-written CRD.

The cluster prerequisites are **provisioned by Terraform** (the `addons` module
installs External Secrets Operator + a `ClusterSecretStore` named
`aws-secretsmanager`, backed by an IRSA role from the `eks` module with
`secretsmanager:GetSecretValue`). Toggle with `enable_external_secrets` and
`cluster_secret_store_name` in the env tfvars.

1. Create the AWS SM secret (e.g. `boutique/app-secrets`, `devboard/app-secrets`)
   holding the keys as JSON. (The IRSA policy allows any secret in the
   account/region by default; set `secrets_manager_path_prefix` in the eks module
   to restrict it to a prefix.)
2. In the app values file:
   ```yaml
   secret:
     enabled: false               # stop generating the plaintext git Secret
   externalSecret:
     enabled: true
     secretStoreRef:
       name: aws-secretsmanager    # your (Cluster)SecretStore
       kind: ClusterSecretStore
     target:
       name: boutique-secrets      # defaults to the chart Secret name anyway
     dataFrom:
       - extract:
           key: boutique/app-secrets   # one AWS SM secret holding all keys
   ```

Because `target.name` defaults to the chart Secret name (`boutique-secrets`),
the Deployments and DB read it **without any other change** — same
`passwordSecret` / `envFromSecret` references keep working.

> The chart fails fast if both `secret.enabled` and `externalSecret` target the
> same Secret name, so you can't accidentally run plaintext and ESO at once.

> For an **RDS password specifically**, the DB reads `database.passwordSecret` /
> `database.passwordKey` (the field is `passwordSecret`, **not** `secretName`) —
> point it at the same ESO-synced Secret.

## Relationship to the existing `gitops/` folder

`gitops/` is the original hand-written Kustomize setup for boutique only. This
`helm/` folder is the reusable replacement. Run **one or the other** for a given
app, not both. The boutique image tag / registry is `global.registry` +
`global.imageTag` here (CI bumps `imageTag`), replacing the `ecr-config` literal
and per-file `sed` the Kustomize flow used.
