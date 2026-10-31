#!/usr/bin/env bash
# Delete the CloudShirt Kubernetes objects, then destroy the GCP stack.
# Usage: bash scripts/teardown-gcp.sh

set -euo pipefail

NAMESPACE="${NAMESPACE:-cloudshirt}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "${SCRIPT_DIR}/../terraform/gcp" && pwd)"

info() { printf '==> %s\n' "$*"; }
error() { printf 'ERROR: %s\n' "$*" >&2; }

tf_output() {
  [ -f "${TF_DIR}/terraform.tfstate" ] || return 1
  local value
  value="$(cd "$TF_DIR" && terraform output -raw "$1" 2>/dev/null)" || return 1
  [ -n "$value" ] || return 1
  printf '%s' "$value"
}

for tool in gcloud kubectl terraform; do
  command -v "$tool" >/dev/null 2>&1 || { error "$tool is not installed."; exit 1; }
done

PROJECT="${GCP_PROJECT_ID:-$(tf_output gcp_project_id || gcloud config get-value project 2>/dev/null || true)}"
ZONE="${GCP_ZONE:-$(tf_output gke_cluster_location || echo europe-west4-a)}"
CLUSTER="${GKE_CLUSTER_NAME:-$(tf_output gke_cluster_name || echo cloudshirt-gke)}"

if [ -z "$PROJECT" ] || [ "$PROJECT" = "(unset)" ]; then
  error "Set GCP_PROJECT_ID or select a project with 'gcloud config set project'."
  exit 1
fi

# Delete the namespace while the cluster is alive: the cloud controller then
# removes the LoadBalancer forwarding rule and the SQL persistent disk.
if gcloud container clusters describe "$CLUSTER" --location "$ZONE" --project "$PROJECT" >/dev/null 2>&1; then
  info "Configuring kubectl for ${CLUSTER} (${ZONE})"
  gcloud container clusters get-credentials "$CLUSTER" --location "$ZONE" --project "$PROJECT" >/dev/null

  if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    info "Deleting namespace ${NAMESPACE}"
    kubectl delete namespace "$NAMESPACE" --ignore-not-found=true --timeout=300s
  else
    info "Namespace ${NAMESPACE} not found; skipping."
  fi
else
  info "Cluster ${CLUSTER} not found; skipping the namespace step."
fi

info "Destroying the GCP Terraform stack"
(cd "$TF_DIR" && terraform destroy -input=false -auto-approve -no-color)

info "Teardown complete."
