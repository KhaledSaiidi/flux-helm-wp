# Flux Helm Wordpress setup

A hands-on project to learn **Flux CD** on GKE: GitOps-style deployment of WordPress using Kustomization, HelmReleases, and OCI Helm charts.

---

## What You'll Learn

- **Flux** – GitOps with GitRepository, Kustomization, and HelmRelease
- **OCI Helm** – Using Bitnami OCI charts
- **Kustomize** – Organizing clusters, infrastructure, and applications
- **WordPress on Kubernetes** – Bitnami WordPress + MariaDB on GKE

---

## Architecture

**WordPress uses MariaDB**
```
┌─────────────────────────────────────────────────────────────────────┐
│  GKE Cluster                                                        │
│                                                                     │
│   GitHub Repo                                                       │  
│         │                                                           │
│         ▼                                                           │
│   ┌─────────────┐     ┌──────────────────┐     ┌───────────────┐    │
│   │   Flux      │────▶│  Kustomization   │────▶│ HelmReleases  │    │
│   │ GitRepository     │  infrastructure  │     │ wordpress     │    │
│   └─────────────┘     │  applications    │     │ (Bitnami)     │    │
│         │             └──────────────────┘     └───────┬───────┘    │
│         │                        │                      │           │
│         │                        │                      ▼           │
│         │                        │             ┌─────────────────┐  │
│         │                        │             │  WordPress      │  │
│         │                        │             │  + MariaDB      │  │
│         │                        │             │  (Bitnami)      │  │
│         │                        │             └─────────────────┘  │
└─────────┼───────────────────────────────────────────────────────────┘
          │
          ▼
    GitHub Repo
```

---

## Repository Layout

```
.
├── clusters/
│   └── production/
│       ├── kustomization.yaml
│       ├── infrastructure.yaml
│       ├── applications.yaml
│       └── flux-system/
├── infrastructure/
│   ├── namespace-wordpress.yaml
│   └── sources/
├── applications/
│   └── wordpress/
│       ├── kustomization.yaml
│       └── helmrelease.yaml
└── README.md
```

---

## Getting Started

### Prerequisites

- **GKE cluster** – Create one or use an existing sandbox
- **gcloud** – `gcloud container clusters get-credentials ...`
- **kubectl** – `kubectl get nodes`
- **flux CLI** – [Install Flux](https://fluxcd.io/flux/installation/)
- **GitHub token** – For `flux bootstrap` (repo access)

---

### Step 1: Clone and Connect to Your Cluster

```bash
# Clone this repo
git clone https://github.com/gma1k/flux-helm-wp.git
cd flux-helm-wp

# Connect to your GKE cluster
gcloud container clusters get-credentials YOUR_CLUSTER --region YOUR_REGION
kubectl get nodes
```

---

### Step 2: Bootstrap Flux

This installs Flux and points it at this repository.

```bash
flux bootstrap github \
  --owner=GitUser \
  --repository=flux-helm-wp \
  --branch=main \
  --path=clusters/production \
  --personal
```

When prompted, authenticate with GitHub (browser or token).

---

### Step 3: Watch Flux Deploy

```bash
# See Kustomizations reconcile
flux get kustomizations -A

# See HelmReleases (WordPress + MariaDB)
flux get helmreleases -A

# Watch pods in the wordpress namespace
kubectl get pods -n wordpress -w
```

Wait until WordPress and MariaDB pods are `Running` and `1/1` Ready (usually 2–3 minutes).

---

### Step 4: Access WordPress

**Option A – LoadBalancer (if exposed by the chart):**

```bash
kubectl get svc -n wordpress
# Use EXTERNAL-IP in browser, e.g. http://<EXTERNAL-IP>
```

**Option B – Port-forward (recommended for local access):**

```bash
kubectl port-forward -n wordpress svc/wordpress 8080:80
# Open http://localhost:8080
```

**Default credentials** (see `applications/wordpress/helmrelease.yaml`):

- Username: `admin`
- Password: `admin`
- Email: `admin@example.com`

---

### 1. Change a Value and Watch GitOps Update

Edit `applications/wordpress/helmrelease.yaml`, e.g.:

```yaml
wordpressPassword: my-new-password
```

Then:

```bash
git add -A
git commit -m "Update WordPress password"
git push origin main

# Trigger Flux to reconcile
flux reconcile source git flux-system
flux reconcile kustomization applications
```

### 2. Explore Flux Resources

```bash
# See what Flux is managing
flux get kustomizations
flux get helmreleases -A

# Inspect the Helm release
helm list -n wordpress
```

### 3. Suspend and Resume Reconciliation

```bash
# Pause automatic updates
flux suspend kustomization applications

# Resume
flux resume kustomization applications
```

### 4. Change WordPress Chart Version

In `applications/wordpress/helmrelease.yaml`:

```yaml
chart:
  spec:
    chart: wordpress
    version: "27.0.0"  # Try a different version
```

Push to Git and reconcile as in step 1.

---

## What Gets Deployed

| Component | Namespace | Description                                  |
|-----------|-----------|----------------------------------------------|
| WordPress | wordpress | Bitnami WordPress chart                      |
| MariaDB   | wordpress | Bitnami MariaDB – WordPress database         |

---

## Customization

| What to change          | File                                          |
|-------------------------|-----------------------------------------------|
| WordPress/MariaDB creds | `applications/wordpress/helmrelease.yaml`     |
| Storage size            | `applications/wordpress/helmrelease.yaml` → `persistence.size` |
| Chart version           | `applications/wordpress/helmrelease.yaml` → `chart.spec.version` |

For production, move passwords into Kubernetes Secrets and reference them via `existingSecret` in the Helm values.

---

## Troubleshooting

```bash
# Flux reconciliation
flux reconcile source git flux-system
flux reconcile kustomization infrastructure
flux reconcile kustomization applications

# Status
flux get kustomizations -A
flux get helmreleases -A

# Pods and logs
kubectl get pods -n wordpress
kubectl logs -n wordpress -l app.kubernetes.io/name=wordpress -f
```

---

## License

MIT
