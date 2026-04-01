#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly KIND_CONFIG="${KIND_CONFIG:-$SCRIPT_DIR/kind-flux.yaml}"
readonly KUBECONFIG_PATH="${KUBECONFIG_PATH:-$SCRIPT_DIR/kind-flux-kubeconfig.yaml}"
readonly CLUSTER_NAME="${CLUSTER_NAME:-$(awk '/^name:/ {print $2; exit}' "$KIND_CONFIG")}"
readonly CILIUM_VERSION="${CILIUM_VERSION:-1.19.1}"
readonly WORDPRESS_NAMESPACE="${WORDPRESS_NAMESPACE:-wordpress}"
readonly LOCAL_PORT="${LOCAL_PORT:-8080}"
readonly REMOTE_PORT="${REMOTE_PORT:-80}"
readonly WAIT_INTERVAL="${WAIT_INTERVAL:-5}"

if [[ -t 1 ]]; then
  readonly COLOR_RED=$'\033[31m'
  readonly COLOR_GREEN=$'\033[32m'
  readonly COLOR_YELLOW=$'\033[33m'
  readonly COLOR_BLUE=$'\033[34m'
  readonly COLOR_MAGENTA=$'\033[35m'
  readonly COLOR_CYAN=$'\033[36m'
  readonly COLOR_BOLD=$'\033[1m'
  readonly COLOR_RESET=$'\033[0m'
else
  readonly COLOR_RED=''
  readonly COLOR_GREEN=''
  readonly COLOR_YELLOW=''
  readonly COLOR_BLUE=''
  readonly COLOR_MAGENTA=''
  readonly COLOR_CYAN=''
  readonly COLOR_BOLD=''
  readonly COLOR_RESET=''
fi

on_error() {
  local exit_code=$?
  printf '\n%s❌ [error]%s bootstrap failed at line %s with exit code %s\n' \
    "$COLOR_RED" "$COLOR_RESET" "${BASH_LINENO[0]}" "$exit_code" >&2
  exit "$exit_code"
}

trap on_error ERR

log() {
  local level=$1
  shift
  local icon color
  case "$level" in
    step) icon='🔹'; color=$COLOR_CYAN ;;
    info) icon='ℹ️ '; color=$COLOR_BLUE ;;
    wait) icon='⏳'; color=$COLOR_YELLOW ;;
    ok) icon='✅'; color=$COLOR_GREEN ;;
    error) icon='❌'; color=$COLOR_RED ;;
    *) icon='•'; color=$COLOR_RESET ;;
  esac

  printf '%s%s [%s]%s %s\n' "$color" "$icon" "$level" "$COLOR_RESET" "$*"
}

require_cmd() {
  local cmd=$1
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log error "required command not found: $cmd"
    printf '%sPlease install %s and run the script again.%s\n' \
      "$COLOR_BOLD" "$cmd" "$COLOR_RESET" >&2
    exit 1
  fi
}

resource_exists() {
  local namespace=$1
  local kind=$2
  local name=$3

  kubectl -n "$namespace" get "$kind" "$name" >/dev/null 2>&1
}

wait_for_command() {
  local description=$1
  local timeout_seconds=$2
  shift 2

  local start_time=$SECONDS
  local frames=( '⠁' '⠂' '⠄' '⠂' )
  local frame_index=0
  while true; do
    if "$@"; then
      printf '\r\033[K'
      log ok "$description"
      return 0
    fi

    local elapsed=$(( SECONDS - start_time ))
    if (( elapsed >= timeout_seconds )); then
      printf '\r\033[K'
      log error "timed out waiting for: $description"
      return 1
    fi

    printf '\r%s⏳ [wait]%s %s... %s %ss/%ss' \
      "$COLOR_YELLOW" "$COLOR_RESET" "$description" \
      "${frames[$frame_index]}" "$elapsed" "$timeout_seconds"
    frame_index=$(( (frame_index + 1) % ${#frames[@]} ))
    sleep "$WAIT_INTERVAL"
  done
}

wait_for_condition() {
  local namespace=$1
  local kind=$2
  local name=$3
  local timeout_seconds=$4

  wait_for_command "$kind/$name exists in namespace $namespace" "$timeout_seconds" \
    resource_exists "$namespace" "$kind" "$name"

  printf '\n'
  log step "waiting for $kind/$name to become Ready..."
  kubectl -n "$namespace" wait --for=condition=Ready "$kind/$name" --timeout="${timeout_seconds}s"
  log ok "$kind/$name is Ready"
}

cluster_exists() {
  kind get clusters | grep -Fxq "$CLUSTER_NAME"
}

cluster_api_ready() {
  kubectl cluster-info >/dev/null 2>&1
}

port_available() {
  if command -v ss >/dev/null 2>&1; then
    ! ss -ltn "( sport = :$LOCAL_PORT )" | grep -q ":$LOCAL_PORT"
    return
  fi

  return 0
}

print_context_summary() {
  cat <<EOF

${COLOR_GREEN}✅ [ok]${COLOR_RESET} bootstrap completed
${COLOR_BLUE}ℹ️  [info]${COLOR_RESET} cluster name: $CLUSTER_NAME
${COLOR_BLUE}ℹ️  [info]${COLOR_RESET} kubeconfig: $KUBECONFIG_PATH
${COLOR_BLUE}ℹ️  [info]${COLOR_RESET} WordPress URL: http://localhost:$LOCAL_PORT
${COLOR_BLUE}ℹ️  [info]${COLOR_RESET} WordPress admin: http://localhost:$LOCAL_PORT/wp-admin
${COLOR_BLUE}ℹ️  [info]${COLOR_RESET} default username: admin
${COLOR_BLUE}ℹ️  [info]${COLOR_RESET} default password: admin

EOF
}

main() {
  require_cmd awk
  require_cmd docker
  require_cmd flux
  require_cmd helm
  require_cmd kind
  require_cmd kubectl

  if [[ ! -f "$KIND_CONFIG" ]]; then
    log error "kind config not found: $KIND_CONFIG"
    exit 1
  fi

  export KUBECONFIG="$KUBECONFIG_PATH"

  log step "using kind config: $KIND_CONFIG"
  log step "using kubeconfig: $KUBECONFIG_PATH"
  log step "target cluster name: $CLUSTER_NAME"

  if cluster_exists; then
    log info "kind cluster '$CLUSTER_NAME' already exists, skipping creation"
    if [[ ! -f "$KUBECONFIG_PATH" ]]; then
      log step "exporting kubeconfig for existing kind cluster"
      kind export kubeconfig --name "$CLUSTER_NAME" --kubeconfig "$KUBECONFIG_PATH"
    fi
  else
    log step "creating kind cluster"
    kind create cluster --config "$KIND_CONFIG" --kubeconfig "$KUBECONFIG_PATH"
  fi

  wait_for_command "Kubernetes API reachable" 60 cluster_api_ready

  log step "current node status before Cilium"
  kubectl get nodes

  log step "installing or upgrading Cilium"
  helm repo add cilium https://helm.cilium.io/ --force-update
  helm repo update
  helm upgrade --install cilium cilium/cilium \
    --version "$CILIUM_VERSION" \
    --namespace kube-system \
    --create-namespace \
    --set image.pullPolicy=IfNotPresent \
    --set ipam.mode=kubernetes

  log step "waiting for Cilium daemonset rollout"
  kubectl -n kube-system rollout status ds/cilium --timeout=300s

  log step "waiting for Cilium operator rollout"
  kubectl -n kube-system rollout status deploy/cilium-operator --timeout=300s

  log step "waiting for all nodes to become Ready"
  kubectl wait --for=condition=Ready nodes --all --timeout=300s
  kubectl get nodes

  log step "installing Flux controllers"
  flux install

  log step "applying Flux sync manifests from this repository"
  kubectl apply -k "$SCRIPT_DIR/clusters/production/flux-system"

  log step "reconciling Git source"
  flux reconcile source git flux-system
  wait_for_condition flux-system gitrepository flux-system 180

  log step "reconciling root Flux Kustomization"
  flux reconcile kustomization flux-system
  wait_for_condition flux-system kustomization flux-system 300

  wait_for_condition flux-system kustomization infrastructure 300
  wait_for_condition flux-system kustomization applications 300
  wait_for_condition "$WORDPRESS_NAMESPACE" helmrelease wordpress 600

  log step "waiting for MariaDB statefulset rollout"
  kubectl -n "$WORDPRESS_NAMESPACE" rollout status statefulset/wordpress-mariadb --timeout=600s

  log step "waiting for WordPress deployment rollout"
  kubectl -n "$WORDPRESS_NAMESPACE" rollout status deployment/wordpress --timeout=600s

  log step "current WordPress resources"
  kubectl -n "$WORDPRESS_NAMESPACE" get all

  if ! port_available; then
    log error "local port $LOCAL_PORT is already in use"
    exit 1
  fi

  print_context_summary
  log step "starting port-forward, keep this process running while you use WordPress"
  exec kubectl port-forward -n "$WORDPRESS_NAMESPACE" svc/wordpress "$LOCAL_PORT:$REMOTE_PORT"
}

main "$@"
