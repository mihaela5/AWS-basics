#!/usr/bin/env bash
# Deploy CloudShirt to the GKE cluster provisioned by terraform/gcp.
# Usage: SA_PASSWORD='...' bash scripts/deploy-k8s.sh [--delete]

set -euo pipefail

NAMESPACE="${NAMESPACE:-cloudshirt}"
REPOSITORY="${ARTIFACT_REPOSITORY:-cloudshirt-images}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-600s}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_DIR="$(cd "${SCRIPT_DIR}/../kubernetes" && pwd)"
TF_DIR="$(cd "${SCRIPT_DIR}/../terraform/gcp" && pwd)"

info() { printf '==> %s\n' "$*"; }
error() { printf 'ERROR: %s\n' "$*" >&2; }

tf_output() {
  command -v terraform >/dev/null 2>&1 || return 1
  [ -f "${TF_DIR}/terraform.tfstate" ] || return 1
  (cd "$TF_DIR" && terraform output -raw "$1" 2>/dev/null)
}

for tool in gcloud kubectl; do
  command -v "$tool" >/dev/null 2>&1 || { error "$tool is not installed."; exit 1; }
done

PROJECT="${GCP_PROJECT_ID:-$(tf_output gcp_project_id || gcloud config get-value project 2>/dev/null || true)}"
if [ -z "$PROJECT" ] || [ "$PROJECT" = "(unset)" ]; then
  error "Set GCP_PROJECT_ID or select a project with 'gcloud config set project'."
  exit 1
fi

REGION="${GCP_REGION:-$(tf_output gcp_region || echo europe-west4)}"
ZONE="${GCP_ZONE:-$(tf_output gke_cluster_location || echo europe-west4-a)}"
CLUSTER="${GKE_CLUSTER_NAME:-$(tf_output gke_cluster_name || echo cloudshirt-gke)}"
REGISTRY="${ARTIFACT_REGISTRY:-$(tf_output artifact_registry_url || echo "${REGION}-docker.pkg.dev/${PROJECT}/${REPOSITORY}")}"

WEB_IMAGE="${WEB_IMAGE:-${REGISTRY}/cloudshirt:${IMAGE_TAG}}"
API_IMAGE="${API_IMAGE:-${REGISTRY}/cloudshirt-api:${IMAGE_TAG}}"
SQL_IMAGE="${SQL_IMAGE:-${REGISTRY}/sqlserver:2022-latest}"

info "Configuring kubectl for ${CLUSTER} (${ZONE})"
gcloud container clusters get-credentials "$CLUSTER" --location "$ZONE" --project "$PROJECT" >/dev/null

if [ "${1:-}" = "--delete" ]; then
  info "Deleting namespace ${NAMESPACE}"
  kubectl delete namespace "$NAMESPACE" --ignore-not-found=true
  exit 0
fi

if [ "$IMAGE_TAG" = "latest" ]; then
  info "Using the latest tag; pass IMAGE_TAG=<build-tag> for reproducible rollouts."
fi

info "Images: ${WEB_IMAGE} ${API_IMAGE} ${SQL_IMAGE}"

apply_manifest() {
  sed -e "s|__WEB_IMAGE__|${WEB_IMAGE}|g" \
      -e "s|__API_IMAGE__|${API_IMAGE}|g" \
      -e "s|__SQL_IMAGE__|${SQL_IMAGE}|g" "$1" | kubectl apply -f -
}

info "Applying namespace and configuration"
apply_manifest "${MANIFEST_DIR}/00-namespace.yaml"
apply_manifest "${MANIFEST_DIR}/10-config.yaml"

if kubectl -n "$NAMESPACE" get secret cloudshirt-db >/dev/null 2>&1; then
  if [ -n "${SA_PASSWORD:-}" ]; then
    EXISTING_PASSWORD="$(kubectl -n "$NAMESPACE" get secret cloudshirt-db -o jsonpath='{.data.SA_PASSWORD}' | base64 -d)"
    if [ "$EXISTING_PASSWORD" != "$SA_PASSWORD" ]; then
      error "The cloudshirt-db secret already exists with a different SA_PASSWORD."
      error "Unset SA_PASSWORD to reuse it, or delete the secret and the SQL volume to change it."
      exit 1
    fi
  fi
  info "Reusing the existing database secret"
else
  if [ -z "${SA_PASSWORD:-}" ]; then
    error "Set SA_PASSWORD (at least 8 characters, 3 of: upper, lower, digit, symbol)."
    exit 1
  fi
  if [ "${#SA_PASSWORD}" -lt 8 ]; then
    error "SA_PASSWORD must be at least 8 characters."
    exit 1
  fi
  case "$SA_PASSWORD" in
    *";"*) error "SA_PASSWORD must not contain ';' because it is embedded in a connection string."; exit 1 ;;
  esac
  if kubectl -n "$NAMESPACE" get pvc data-cloudshirt-sql-0 >/dev/null 2>&1; then
    info "Existing SQL volume found; SA_PASSWORD must match the password stored in it."
  fi
  info "Creating the database secret"
  kubectl -n "$NAMESPACE" create secret generic cloudshirt-db \
    --from-literal=SA_PASSWORD="$SA_PASSWORD" \
    --from-literal=CatalogConnection="Server=cloudshirt-sql,1433;Initial Catalog=Microsoft.eShopOnWeb.CatalogDb;User Id=sa;Password=${SA_PASSWORD};TrustServerCertificate=True" \
    --from-literal=IdentityConnection="Server=cloudshirt-sql,1433;Initial Catalog=Microsoft.eShopOnWeb.Identity;User Id=sa;Password=${SA_PASSWORD};TrustServerCertificate=True" \
    --dry-run=client -o yaml | kubectl -n "$NAMESPACE" apply -f -
fi

info "Deploying SQL Server"
apply_manifest "${MANIFEST_DIR}/20-sqlserver.yaml"
kubectl -n "$NAMESPACE" rollout status statefulset/cloudshirt-sql --timeout="$ROLLOUT_TIMEOUT"

info "Deploying the public API"
apply_manifest "${MANIFEST_DIR}/30-publicapi.yaml"
kubectl -n "$NAMESPACE" rollout status deployment/cloudshirt-api --timeout="$ROLLOUT_TIMEOUT"

info "Deploying the website with five replicas"
apply_manifest "${MANIFEST_DIR}/40-web.yaml"
kubectl -n "$NAMESPACE" rollout status deployment/cloudshirt-web --timeout="$ROLLOUT_TIMEOUT"

info "Waiting for the external IP"
IP=""
for _ in $(seq 1 60); do
  IP="$(kubectl -n "$NAMESPACE" get service cloudshirt-web -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  [ -n "$IP" ] && break
  sleep 5
done

kubectl -n "$NAMESPACE" get pods -o wide
kubectl -n "$NAMESPACE" get service cloudshirt-web

if [ -z "$IP" ]; then
  error "The Service has no external IP yet. Check 'kubectl -n ${NAMESPACE} describe service cloudshirt-web'."
  exit 1
fi

if command -v curl >/dev/null 2>&1; then
  if curl -fsS --max-time 15 "http://${IP}/" >/dev/null; then
    info "CloudShirt is available at http://${IP}/"
  else
    error "The external IP is ${IP}, but the home page did not respond."
    exit 1
  fi
else
  info "CloudShirt is available at http://${IP}/"
fi
