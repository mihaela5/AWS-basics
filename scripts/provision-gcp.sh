#!/usr/bin/env bash
# Provision the CloudShirt GCP stack, mirror the SQL image and deploy with Ansible.
# Run from Git Bash on Windows (Ansible is invoked through WSL) or from WSL/Linux.
# Usage: bash scripts/provision-gcp.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform/gcp"
ANSIBLE_DIR="${ROOT_DIR}/ansible"
SA_PASSWORD_FILE="${SA_PASSWORD_FILE:-${HOME}/.cloudshirt-sa-password}"

info() { printf '==> %s\n' "$*"; }
error() { printf 'ERROR: %s\n' "$*" >&2; }

for tool in terraform gcloud docker git; do
  command -v "$tool" >/dev/null 2>&1 || { error "$tool is not installed."; exit 1; }
done

# Terraform runs the image build with bash. On Windows that must be Git Bash;
# WSL's bash does not inherit the provisioner environment.
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    export TF_VAR_bash_executable="${TF_VAR_bash_executable:-$(cygpath -m "$(command -v bash)")}"
    ;;
esac

tf_output() {
  [ -f "${TF_DIR}/terraform.tfstate" ] || return 1
  local value
  value="$(cd "$TF_DIR" && terraform output -raw "$1" 2>/dev/null)" || return 1
  [ -n "$value" ] || return 1
  printf '%s' "$value"
}

info "Applying the GCP Terraform stack"
(cd "$TF_DIR" && terraform init -input=false -no-color)
(cd "$TF_DIR" && terraform apply -input=false -auto-approve -no-color)

PROJECT="$(tf_output gcp_project_id || true)"
REGION="$(tf_output gcp_region || true)"
REGISTRY="$(tf_output artifact_registry_url || true)"
PROJECT="${PROJECT:-${GCP_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}}"
REGION="${REGION:-${GCP_REGION:-europe-west4}}"
REGISTRY="${REGISTRY:-${ARTIFACT_REGISTRY:-${REGION}-docker.pkg.dev/${PROJECT}/cloudshirt-images}}"

if [ -z "$PROJECT" ] || [ "$PROJECT" = "(unset)" ]; then
  error "Set GCP_PROJECT_ID or select a project with 'gcloud config set project'."
  exit 1
fi

if gcloud artifacts docker tags list "${REGISTRY}/sqlserver" --format='value(tag)' 2>/dev/null | grep -qx '2022-latest'; then
  info "SQL Server image already in Artifact Registry"
else
  info "Mirroring the SQL Server image (one-time, large)"
  TOKEN="$(gcloud auth print-access-token 2>/dev/null || gcloud auth application-default print-access-token)"
  printf '%s' "$TOKEN" | docker login -u oauth2accesstoken --password-stdin "https://${REGION}-docker.pkg.dev" >/dev/null
  docker pull mcr.microsoft.com/mssql/server:2022-latest
  docker tag mcr.microsoft.com/mssql/server:2022-latest "${REGISTRY}/sqlserver:2022-latest"
  docker push "${REGISTRY}/sqlserver:2022-latest"
fi

umask 077
if [ -n "${SA_PASSWORD:-}" ]; then
  printf '%s\n' "$SA_PASSWORD" > "$SA_PASSWORD_FILE"
  info "Using SA_PASSWORD from the environment"
elif [ -f "$SA_PASSWORD_FILE" ]; then
  SA_PASSWORD="$(cat "$SA_PASSWORD_FILE")"
  info "Using the existing SA password from ${SA_PASSWORD_FILE}"
else
  SA_PASSWORD="Aa1#$(head -c 24 /dev/urandom | base64 | tr -d '\n=')"
  printf '%s\n' "$SA_PASSWORD" > "$SA_PASSWORD_FILE"
  info "Generated a new SA password in ${SA_PASSWORD_FILE}"
fi
chmod 600 "$SA_PASSWORD_FILE"
export SA_PASSWORD
export GCP_PROJECT_ID="$PROJECT"
export ANSIBLE_ROLES_PATH="${ANSIBLE_DIR}/roles"
export ANSIBLE_INVENTORY="${ANSIBLE_DIR}/inventory"

if [ -z "${CLOUDSDK_CONFIG:-}" ] && [ -d "${APPDATA:-}/gcloud" ]; then
  export CLOUDSDK_CONFIG="${APPDATA}/gcloud"
fi
if [ -z "${CLOUDSDK_CONFIG:-}" ]; then
  for candidate in /mnt/c/Users/*/AppData/Roaming/gcloud; do
    [ -d "$candidate" ] && export CLOUDSDK_CONFIG="$candidate" && break
  done
fi

info "Deploying the application with Ansible"
if command -v ansible-playbook >/dev/null 2>&1; then
  (cd "$ANSIBLE_DIR" && ansible-playbook playbooks/site.yml)
elif command -v wsl.exe >/dev/null 2>&1; then
  ansible_wsl="$(wsl.exe wslpath -a "$(cygpath -m "$ANSIBLE_DIR")" | tr -d '\r')"
  case "${CLOUDSDK_CONFIG:-}" in
    [A-Za-z]:*|/[a-z]/*) CLOUDSDK_CONFIG="$(wsl.exe wslpath -a "$(cygpath -m "$CLOUDSDK_CONFIG")" | tr -d '\r')" ;;
  esac
  export ANSIBLE_ROLES_PATH="${ansible_wsl}/roles"
  export ANSIBLE_INVENTORY="${ansible_wsl}/inventory"
  export WSLENV="GCP_PROJECT_ID:SA_PASSWORD:CLOUDSDK_CONFIG:ANSIBLE_ROLES_PATH:ANSIBLE_INVENTORY"
  wsl.exe bash -lc "cd '${ansible_wsl}' && ansible-playbook playbooks/site.yml"
else
  error "ansible-playbook was not found and WSL is not available."
  exit 1
fi

info "Provisioning complete."
