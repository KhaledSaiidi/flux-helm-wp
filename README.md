# Flux Helm WordPress Setup

A hands-on project to learn **Flux CD** on a local **Kind** cluster: GitOps-style deployment of WordPress using Kustomizations, HelmReleases, and OCI Helm charts.

---

## Hands-on

- **Flux** – GitOps with GitRepository, Kustomization, and HelmRelease
- **OCI Helm** – Using Bitnami OCI charts
- **Kustomize** – Organizing clusters, infrastructure, and applications
- **WordPress on Kubernetes** – Bitnami WordPress + MariaDB on Kind

---

## Architecture

**WordPress uses MariaDB**
```
┌─────────────────────────────────────────────────────────────────────┐
│  Kind Cluster: flux-lab                                             │
│                                                                     │
│  Flux controllers in flux-system                                    │
│    │                                                                │
│    ▼                                                                │
│  GitRepository: flux-system                                         │
│    │                                                                │
│    ▼                                                                │
│  Kustomization: flux-system                                         │
│    │                                                                │
│    ├────▶ Kustomization: infrastructure                             │
│    │         ├────▶ Namespace: wordpress                            │
│    │         └────▶ HelmRepository: bitnami                         │
│    │                                                                │
│    └────▶ Kustomization: applications                               │
│              └────▶ HelmRelease: wordpress                          │
│                        └────▶ Bitnami WordPress + MariaDB           │
│                                                                     │
│  Cilium provides cluster networking                                 │
└─────────────────────────────────────────────────────────────────────┘
                 ▲
                 │
                 └──── GitHub repo: KhaledSaiidi/flux-helm-wp
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

- **Docker** – required by Kind
- **kind** – to create the local Kubernetes cluster
- **kubectl** – `kubectl get nodes`
- **helm** – used to install Cilium
- **flux CLI** – [Install Flux](https://fluxcd.io/flux/installation/)
- **GitHub token** – For `flux bootstrap` (repo access)
- **GitHub repository** – push this repo to `https://github.com/KhaledSaiidi/flux-helm-wp`

---

### Step 1: Clone the Repo

```bash
git clone https://github.com/KhaledSaiidi/flux-helm-wp.git
cd flux-helm-wp
```

This repo already points Flux at:

```yaml
url: https://github.com/KhaledSaiidi/flux-helm-wp.git
```

in `clusters/production/flux-system/gotk-sync.yaml`.

---

### Step 2: Create a Kind Cluster

You said you want to use this config:

```bash
kind create cluster \
  --config kind-flux.yaml \
  --kubeconfig kind-flux-kubeconfig.yaml
```

---

`kind-flux.yaml` in this repo creates a cluster named `flux-lab` with `disableDefaultCNI: true`:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: flux-lab
networking:
  disableDefaultCNI: true
nodes:
  - role: control-plane
  - role: worker
  - role: worker
```

After cluster creation, use that kubeconfig for all commands in this guide:

```bash
export KUBECONFIG=$PWD/kind-flux-kubeconfig.yaml
kubectl get nodes
```

At this point, `kubectl get nodes` will usually show `NotReady`. That is expected because the default Kind CNI is disabled and you have not installed Cilium yet.

---

### Step 3: Install Cilium

Before Flux or WordPress can run correctly, the cluster needs networking.

Install Cilium with Helm:

```bash
helm repo add cilium https://helm.cilium.io/
helm repo update
helm install cilium cilium/cilium \
  --version 1.19.1 \
  --namespace kube-system \
  --set image.pullPolicy=IfNotPresent \
  --set ipam.mode=kubernetes
```

Then wait for Cilium to become healthy:

```bash
kubectl -n kube-system rollout status ds/cilium
kubectl -n kube-system rollout status deploy/cilium-operator
kubectl get nodes
```

Once Cilium is up, the nodes should become `Ready`.

---

### Step 4: Install Flux and Apply the Sync Manifests

For this public repository, install Flux first and then apply the sync manifests from this repo:

```bash
flux install

kubectl apply -k clusters/production/flux-system
```

What this does:

- `flux install` installs the Flux controllers into the `flux-system` namespace
- `kubectl apply -k clusters/production/flux-system` creates the `GitRepository` and Flux `Kustomization` objects from this repo
- the `GitRepository` points Flux at `https://github.com/KhaledSaiidi/flux-helm-wp.git`
- the `flux-system` Kustomization starts reconciling `./clusters/production`
- that in turn applies the `infrastructure` and `applications` layers from Git

If you see warnings about `last-applied-configuration`, that is expected when `flux install` creates resources first and `kubectl apply` manages them afterward.

---

### Step 5: Watch Flux Deploy

```bash
# See git source reconcile
flux get sources git -A

# See Kustomizations reconcile
flux get kustomizations -A

# See HelmReleases (WordPress + MariaDB)
flux get helmreleases -A

# Watch pods in the wordpress namespace
kubectl get pods -n wordpress -w
```

Wait until WordPress and MariaDB pods are `Running` and `1/1` Ready (usually 2–3 minutes).

What is happening in the cluster:

1. Flux syncs `clusters/production`.
2. Flux applies `infrastructure/namespace-wordpress.yaml`.
3. Flux applies `infrastructure/sources/helmrepository-bitnami.yaml`.
4. Flux applies `applications/wordpress/helmrelease.yaml`.
5. The Helm controller installs the Bitnami `wordpress` chart.
6. That chart creates the WordPress and MariaDB workloads in the `wordpress` namespace.

---

### Step 6: Access WordPress

On Kind, port-forwarding is the simplest option:

```bash
kubectl port-forward -n wordpress svc/wordpress 8080:80
```

Open `http://localhost:8080`.

Default credentials from `applications/wordpress/helmrelease.yaml`:

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

# Optional: trigger Flux immediately instead of waiting for the poll interval
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
# Verify the active kubeconfig points at your Kind cluster
kubectl config current-context

# Nodes may stay NotReady until Cilium is installed
kubectl get nodes

# Cilium health
kubectl -n kube-system get pods
kubectl -n kube-system rollout status ds/cilium
kubectl -n kube-system rollout status deploy/cilium-operator

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

If Flux does not start syncing after Step 4, verify all of the following:

- `KUBECONFIG` is set to `kind-flux-kubeconfig.yaml`
- the repository `KhaledSaiidi/flux-helm-wp` exists on GitHub
- your current branch is pushed to GitHub
- `flux get sources git -A` shows the `flux-system` source becoming ready

If WordPress pods stay pending or crash, check Cilium first. With `disableDefaultCNI: true`, application networking depends entirely on Cilium being installed and healthy.

---

## License

MIT
