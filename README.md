# Flux Helm WordPress on Kind

A hands-on Flux CD project that deploys Bitnami WordPress and MariaDB into a local Kind cluster, with Cilium as the CNI and a wrapper script that automates the whole bootstrap flow.

## What This Repo Does

This repository is a small GitOps lab.

- Flux watches this Git repository.
- Flux reconciles the `clusters/production` path.
- The infrastructure layer creates the `wordpress` namespace and registers the Bitnami Helm repository.
- The applications layer creates a `HelmRelease` for WordPress.
- The WordPress chart deploys WordPress and MariaDB.
- Runtime credentials are not stored in Git. They are injected at bootstrap time into a Kubernetes Secret and consumed by the HelmRelease.

## Architecture

```text
GitHub Repo
   |
   v
Flux GitRepository (flux-system)
   |
   v
Flux Kustomization: flux-system
   |
   +--> Flux Kustomization: infrastructure
   |      +--> Namespace: wordpress
   |      +--> HelmRepository: bitnami
   |
   +--> Flux Kustomization: applications
          +--> HelmRelease: wordpress
                 +--> Bitnami WordPress
                 +--> Bitnami MariaDB

bootstrap-wrapper.sh
   |
   +--> creates or reuses Kind cluster
   +--> installs Cilium
   +--> installs Flux
   +--> creates runtime Secret: wordpress-runtime-values
   +--> waits for GitRepository, Kustomizations, HelmRelease, pods, and rollouts
   +--> starts port-forward to localhost
```

## Screenshots

### 1. Wrapper prompts for runtime values and begins cluster creation

This shows the script asking for WordPress and MariaDB values, with support for default values and auto-generated passwords.

![Wrapper prompts for runtime values and starts Kind creation](assets/image-1.png)

### 2. Kind cluster is created and Cilium installation begins

At this stage the nodes are still `NotReady`, which is expected before Cilium finishes installing.

![Kind creation and Cilium install](assets/image-2.png)

### 3. Flux controllers are installed into `flux-system`

This is the `flux install` phase where Flux CRDs, RBAC, services, and controllers are created.

![Flux controllers installation](assets/image-3.png)

### 4. Flux source, Kustomizations, and runtime Secret reconciliation

This screenshot shows the Git source becoming ready, the root and infrastructure Kustomizations succeeding, and the runtime Secret being created before the applications reconcile.

![Flux reconciliation and runtime Secret creation](assets/image-4.png)

### 5. WordPress and MariaDB become healthy and port-forward starts

This is the successful end state from the wrapper: the HelmRelease is ready, rollouts are complete, resources are listed, and the script prints the admin URL and credentials before starting port-forward.

![Successful bootstrap and port-forward](assets/image-5.png)

### 6. Retrieve WordPress and MariaDB credentials from the runtime Secret

This shows the exact `kubectl` commands used to recover the values later, including auto-generated passwords.

![Retrieving credentials from the runtime Secret](assets/image-6.png)

### 7. WordPress admin dashboard after login

This is the final result after visiting `/wp-admin` and logging in with the values stored in `wordpress-runtime-values`.

![WordPress admin dashboard](assets/image-7.png)

## Repository Layout

```text
.
├── applications/
│   ├── kustomization.yaml
│   └── wordpress/
│       ├── helmrelease.yaml
│       └── kustomization.yaml
├── assets/
│   ├── image-1.png
│   ├── image-2.png
│   ├── image-3.png
│   ├── image-4.png
│   ├── image-5.png
│   ├── image-6.png
│   └── image-7.png
├── bootstrap-wrapper.sh
├── clusters/
│   └── production/
│       ├── applications.yaml
│       ├── flux-system/
│       │   ├── gotk-components.yaml
│       │   ├── gotk-sync.yaml
│       │   └── kustomization.yaml
│       ├── infrastructure.yaml
│       └── kustomization.yaml
├── infrastructure/
│   ├── kustomization.yaml
│   ├── namespace-wordpress.yaml
│   └── sources/
│       └── helmrepository-bitnami.yaml
├── kind-flux.yaml
└── README.md
```

## Current Deployment Model

### Cluster

- Local Kubernetes via Kind
- Cluster name defaults to `flux-lab`
- Default CNI is disabled in `kind-flux.yaml`
- Cilium is installed by the wrapper

### Flux

- Flux is installed with `flux install`
- No GitHub PAT is required for the repo sync flow in this project
- Flux reads the public repository over HTTPS
- Flux sync starts from `clusters/production`

### Credentials

- WordPress and MariaDB credentials are not hardcoded in Git anymore
- `applications/wordpress/helmrelease.yaml` reads them from a Kubernetes Secret using `valuesFrom`
- The wrapper creates that Secret as `wordpress-runtime-values`
- If you leave passwords blank during bootstrap, the wrapper auto-generates them

## Prerequisites

Install these tools before running anything:

- `docker`
- `kind`
- `kubectl`
- `helm`
- `flux`
- `awk`
- `tr`

The wrapper checks the required CLIs at startup and exits with a clear error if one is missing.

## Recommended Quick Start

The recommended path is the wrapper script.

```bash
git clone https://github.com/KhaledSaiidi/flux-helm-wp.git
cd flux-helm-wp
chmod +x bootstrap-wrapper.sh
./bootstrap-wrapper.sh
```

What the wrapper does:

1. Prompts for WordPress and MariaDB runtime values.
2. Creates the Kind cluster from `kind-flux.yaml`, or reuses it if it already exists.
3. Exports or uses the kubeconfig file.
4. Installs or upgrades Cilium.
5. Waits for all nodes to become `Ready`.
6. Installs Flux controllers.
7. Applies `clusters/production/flux-system`.
8. Reconciles the Git source and Flux Kustomizations.
9. Creates the runtime Secret in the `wordpress` namespace.
10. Reconciles the applications layer.
11. Waits for the HelmRelease, MariaDB, and WordPress to become healthy.
12. Prints the final access information.
13. Starts `kubectl port-forward` in the foreground.

## Interactive Inputs

During bootstrap, the wrapper prompts for:

- WordPress admin username
- WordPress admin email
- WordPress admin password
- MariaDB database name
- MariaDB username
- MariaDB password

Behavior:

- Press `Enter` to accept the defaults shown in brackets.
- Leave either password blank to auto-generate a strong random password.
- These values are stored in-cluster as a Kubernetes Secret, not in Git.

## Exportable Environment Variables

The wrapper supports these environment variables:

| Variable | Default | Purpose |
|---|---|---|
| `KIND_CONFIG` | `./kind-flux.yaml` | Path to the Kind cluster config file |
| `KUBECONFIG_PATH` | `./kind-flux-kubeconfig.yaml` | Path where the wrapper stores or uses the kubeconfig |
| `CLUSTER_NAME` | parsed from `kind-flux.yaml` | Name of the Kind cluster |
| `CILIUM_VERSION` | `1.19.1` | Cilium chart version to install |
| `WORDPRESS_NAMESPACE` | `wordpress` | Namespace where WordPress is deployed |
| `LOCAL_PORT` | `8080` | Local port used for port-forward |
| `REMOTE_PORT` | `80` | Service port forwarded from the WordPress service |
| `WAIT_INTERVAL` | `5` | Poll interval in seconds for wait loops |
| `WORDPRESS_SECRET_NAME` | `wordpress-runtime-values` | Name of the runtime Secret created by the wrapper |

Examples:

```bash
LOCAL_PORT=9090 ./bootstrap-wrapper.sh
```

```bash
KUBECONFIG_PATH=$PWD/my-kind-kubeconfig.yaml ./bootstrap-wrapper.sh
```

```bash
CILIUM_VERSION=1.19.2 ./bootstrap-wrapper.sh
```

## Manual Flow

If you want to run the steps manually instead of the wrapper, this is the flow the repo currently expects.

### 1. Create the Kind cluster

```bash
kind create cluster \
  --config kind-flux.yaml \
  --kubeconfig kind-flux-kubeconfig.yaml
```

### 2. Export kubeconfig

```bash
export KUBECONFIG=$PWD/kind-flux-kubeconfig.yaml
kubectl get nodes
```

At this point, nodes will usually be `NotReady` because `disableDefaultCNI: true` is set.

### 3. Install Cilium

```bash
helm repo add cilium https://helm.cilium.io/
helm repo update
helm upgrade --install cilium cilium/cilium \
  --version 1.19.1 \
  --namespace kube-system \
  --create-namespace \
  --set image.pullPolicy=IfNotPresent \
  --set ipam.mode=kubernetes
```

Wait for Cilium and nodes:

```bash
kubectl -n kube-system rollout status ds/cilium --timeout=300s
kubectl -n kube-system rollout status deploy/cilium-operator --timeout=300s
kubectl wait --for=condition=Ready nodes --all --timeout=300s
kubectl get nodes
```

### 4. Install Flux

```bash
flux install
kubectl apply -k clusters/production/flux-system
```

### 5. Wait for the source and Kustomizations

```bash
flux reconcile source git flux-system
flux reconcile kustomization flux-system

flux get sources git -A
flux get kustomizations -A
```

### 6. Create runtime credentials Secret

Create the Secret in the `wordpress` namespace before reconciling the applications layer:

```bash
kubectl create namespace wordpress --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic wordpress-runtime-values \
  -n wordpress \
  --from-literal=wordpressUsername=admin \
  --from-literal=wordpressPassword=admin \
  --from-literal=wordpressEmail=admin@example.com \
  --from-literal=mariadbDatabase=wordpress \
  --from-literal=mariadbUsername=wordpress \
  --from-literal=mariadbPassword=wordpress \
  --dry-run=client -o yaml \
  | kubectl label --local -f - reconcile.fluxcd.io/watch=Enabled -o yaml \
  | kubectl apply -f -
```

### 7. Reconcile applications

```bash
flux reconcile kustomization applications
flux get helmreleases -A
kubectl get pods -n wordpress -w
```

### 8. Access WordPress

```bash
kubectl port-forward -n wordpress svc/wordpress 8080:80
```

Then open:

- Site: `http://localhost:8080`
- Admin: `http://localhost:8080/wp-admin`

## Runtime Secret and Credentials

The runtime Secret is:

```text
wordpress-runtime-values
```

The wrapper stores:

- `wordpressUsername`
- `wordpressPassword`
- `wordpressEmail`
- `mariadbDatabase`
- `mariadbUsername`
- `mariadbPassword`

Retrieve the current values with:

```bash
kubectl -n wordpress get secret wordpress-runtime-values -o jsonpath='{.data.wordpressUsername}' | base64 -d && echo
kubectl -n wordpress get secret wordpress-runtime-values -o jsonpath='{.data.wordpressPassword}' | base64 -d && echo
kubectl -n wordpress get secret wordpress-runtime-values -o jsonpath='{.data.mariadbUsername}' | base64 -d && echo
kubectl -n wordpress get secret wordpress-runtime-values -o jsonpath='{.data.mariadbPassword}' | base64 -d && echo
kubectl -n wordpress get secret wordpress-runtime-values -o jsonpath='{.data.mariadbDatabase}' | base64 -d && echo
```

This is especially useful if you chose auto-generated passwords.

## How the HelmRelease Uses the Secret

`applications/wordpress/helmrelease.yaml` now uses `valuesFrom` so that the chart reads credentials from the Secret instead of storing them inline in Git.

This keeps the repository cleaner and avoids committing admin and database passwords into a public repo.

## Common Day 2 Commands

### Check Git source and Flux status

```bash
flux get sources git -A
flux get kustomizations -A
flux get helmreleases -A
```

### Force reconciliation

```bash
flux reconcile source git flux-system
flux reconcile kustomization infrastructure
flux reconcile kustomization applications
```

### Inspect WordPress resources

```bash
kubectl get all -n wordpress
kubectl get secret -n wordpress wordpress-runtime-values
kubectl logs -n wordpress deploy/wordpress
```

### Access WordPress

```bash
kubectl port-forward -n wordpress svc/wordpress 8080:80
```

### Log in to WordPress admin

Open:

```text
http://localhost:8080/wp-admin
```

Then use the username and password stored in `wordpress-runtime-values`.

## Troubleshooting

### The wrapper says a command is missing

Install the missing CLI and run the script again.

### Nodes stay `NotReady`

Check Cilium first:

```bash
kubectl -n kube-system get pods
kubectl -n kube-system rollout status ds/cilium --timeout=300s
kubectl -n kube-system rollout status deploy/cilium-operator --timeout=300s
kubectl get nodes
```

### Flux source is not ready

```bash
flux get sources git -A
kubectl -n flux-system describe gitrepository flux-system
kubectl -n flux-system logs deploy/source-controller --tail=100
```

### Applications are not reconciling

Make sure the runtime Secret exists:

```bash
kubectl -n wordpress get secret wordpress-runtime-values
flux get kustomizations -A
flux get helmreleases -A
```

### WordPress is up but you cannot access it

Make sure the wrapper is still running, or start port-forward manually:

```bash
kubectl port-forward -n wordpress svc/wordpress 8080:80
```

Then open `http://localhost:8080`.

### You forgot the generated password

Recover it from the runtime Secret:

```bash
kubectl -n wordpress get secret wordpress-runtime-values -o jsonpath='{.data.wordpressPassword}' | base64 -d && echo
```

## Notes

- This repo is for learning and local experimentation.
- The current secret flow is much better than hardcoding passwords in Git, but it is still a local bootstrap pattern, not full production secret management.
- For a stronger production approach, look at SOPS, External Secrets Operator, or another real secret backend.

## License

MIT
