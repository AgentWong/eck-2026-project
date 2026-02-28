# Getting Started

## Prerequisites

- **Rancher Desktop** with K3s enabled (10GB RAM, 8 vCPUs recommended)
- `~/.rd/bin` on PATH (provides `kubectl`, `helm`, `docker`)
- Additional tools: `terraform`, `terragrunt`, `git`, `gh`, `trivy`, `argocd`, `istioctl`, `aws`

Run the prerequisite check script to verify everything is installed:

```bash
./scripts/setup-local.sh
```

## Accessing Services

### Quick Access (All Services)

Forward all services at once:

```bash
./scripts/port-forward.sh all
```

Or forward individually: `./scripts/port-forward.sh argocd|kibana|keycloak|es`

Press `Ctrl+C` to stop all port-forwards.

---

### Components with Web UIs

#### ArgoCD — GitOps Dashboard

**Local access (port-forward)**

| | |
|---|---|
| **URL** | https://localhost:8080 |
| **Port-forward** | `kubectl port-forward svc/argocd-server -n argocd 8080:443` |
| **Username** | `admin` |
| **Password** | See command below |

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

**AWS access (direct URL)**

| | |
|---|---|
| **URL** | https://argocd.hermanwong.io |
| **DNS** | Route53 A record → ALB (managed by External DNS) |

**Login options (AWS):**

1. **Keycloak SSO (recommended):** Click "Log in via Keycloak" on the login page. Authenticate as `admin` / `admin` in the `eck-2026` realm for full admin access, or `viewer` / `viewer` for read-only access.

2. **Local admin account:** Use the `admin` username with the password from:
   ```bash
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
   ```

> **Note:** The Keycloak SSO `admin` user maps to ArgoCD `role:admin` (full access). The `viewer` user maps to `role:readonly`. Role mappings are defined in `argocd-rbac-cm`.

**What you'll see:** The ArgoCD dashboard showing all Application resources, their sync status, and health. Uses a cert-manager TLS certificate — your browser will show a security warning; click through to proceed.

---

#### Kibana — Elasticsearch Dashboard

| | |
|---|---|
| **URL** | https://localhost:5601 |
| **Port-forward** | `kubectl port-forward svc/kibana-kb-http -n elastic 5601:5601` |

**Login options:**

1. **Keycloak SSO (recommended):** Click "Log in with Keycloak" on the login page. You'll be redirected to Keycloak to authenticate, then back to Kibana.

   | User | Password | Kibana Role |
   |------|----------|-------------|
   | `admin` | `admin` | superuser (full access) |
   | `viewer` | `viewer` | kibana_admin + viewer (read-only) |

2. **Basic auth (fallback):** Click "Log in with username/password" and use the `elastic` superuser:

   ```bash
   kubectl -n elastic get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' | base64 -d
   ```

**What you'll see:** The Kibana UI for exploring Elasticsearch data, building dashboards, and running queries via Dev Tools. Uses a self-signed TLS certificate — your browser will show a security warning; click through to proceed.

---

#### Keycloak — Identity Provider Admin Console

| | |
|---|---|
| **URL** | https://localhost:8443 |
| **Port-forward** | `kubectl port-forward svc/keycloak-service -n keycloak 8443:8443` |
| **Username** | `temp-admin` |
| **Password** | See command below |

```bash
kubectl -n keycloak get secret keycloak-initial-admin -o jsonpath='{.data.password}' | base64 -d
```

**What you'll see:** The Keycloak admin console — a full web UI for managing realms, clients, users, and SSO configuration. Uses a cert-manager TLS certificate — your browser will show a security warning; click through to proceed.

The `eck-2026` realm is pre-configured with:

| Item | Details |
|------|---------|
| OIDC Clients | `argocd` (ArgoCD SSO), `kibana` (Kibana SSO) |
| Test Users | `admin` / `admin` (admin + user roles → ArgoCD admin, Elasticsearch superuser) |
| | `viewer` / `viewer` (user role only → ArgoCD read-only, Elasticsearch kibana_admin + viewer) |

To view the realm config: select **eck-2026** from the realm dropdown in the top-left of the Keycloak console.

---

#### Kiali — Istio Service Mesh Dashboard

| | |
|---|---|
| **URL** | https://localhost:20001 |
| **Port-forward** | `kubectl port-forward svc/kiali -n istio-system 20001:20001` |
| **Auth** | Anonymous (no login required) |

**What you'll see:** The Kiali dashboard showing the Istio service mesh topology, traffic graphs between services in the `elastic` namespace, and health indicators. Backed by a lightweight Prometheus instance that scrapes Istio envoy sidecar metrics.

Sidecar injection is enabled on the `elastic` namespace — Elasticsearch, Kibana, and Fleet Server pods run `istio-proxy` as a native sidecar (init container). The Elastic Agent DaemonSet is excluded because it uses `hostNetwork`.

Verify Istio with:

```bash
istioctl analyze
kubectl get pods -n istio-system
```

---

### API-Only Components (No Web UI)

#### Elasticsearch REST API

| | |
|---|---|
| **URL** | https://localhost:9200 |
| **Port-forward** | `kubectl port-forward svc/elasticsearch-es-http -n elastic 9200:9200` |

Access via `curl` (requires `-k` for self-signed TLS):

```bash
PASSWORD=$(kubectl -n elastic get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' | base64 -d)
curl -k -u "elastic:$PASSWORD" https://localhost:9200
curl -k -u "elastic:$PASSWORD" https://localhost:9200/_cluster/health?pretty
```

No web UI — use **Kibana Dev Tools** (Management → Dev Tools) for interactive queries.

---

## Verification Quick Checks

```bash
# All pods healthy
kubectl get pods -A

# Elasticsearch cluster health
kubectl get elasticsearch -n elastic

# Kibana health
kubectl get kibana -n elastic

# Keycloak running
kubectl get keycloak -n keycloak

# cert-manager issuers and certificates
kubectl get clusterissuer
kubectl get certificate -A

# Helm releases
helm list -A

# Network policies
kubectl get networkpolicies -A

# Istio analysis
istioctl analyze

# Resource usage
kubectl top nodes
```
