#!/usr/bin/env bash
# Create or update the CloudShirt Swarm service from the ECR image.
# Run on the Swarm manager:
#   sudo DB_PASSWORD='...' /opt/deploy.sh        # first create
#   sudo IMAGE_TAG=2026-10-24 /opt/deploy.sh     # image rollout

set -euo pipefail

export AWS_PAGER=""

STACK_NAME="${STACK_NAME:-CloudShirtInfrastructure}"
SERVICE_NAME="${SERVICE_NAME:-cloudshirt}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REPLICAS="${REPLICAS:-2}"
PUBLISHED_PORT="${PUBLISHED_PORT:-80}"
TARGET_PORT="${TARGET_PORT:-80}"
DB_USERNAME="${DB_USERNAME:-cloudshirtadmin}"
DB_PASSWORD="${DB_PASSWORD:-}"
DB_PORT="${DB_PORT:-}"

info() { printf '==> %s\n' "$*"; }
error() { printf 'ERROR: %s\n' "$*" >&2; }

# Preflight checks ---------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  error "Docker is not installed. Run this on the Buildserver."
  exit 1
fi

if [ "$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null)" != "active" ]; then
  error "Docker Swarm is not active on this host."
  exit 1
fi

if ! docker node ls >/dev/null 2>&1; then
  error "Run this script on the Swarm manager; 'docker node ls' failed."
  exit 1
fi

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
if [ -z "$REGION" ]; then
  REGION="$(aws configure get region)"
fi
export AWS_DEFAULT_REGION="$REGION"

stack_output() {
  aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" \
    --output text
}

# Resolve the image --------------------------------------------------------
IMAGE="${IMAGE:-$(stack_output EcrRepositoryUri)}"
if [ -z "$IMAGE" ] || [ "$IMAGE" = "None" ]; then
  error "Could not read EcrRepositoryUri from stack '$STACK_NAME' in '$REGION'."
  exit 1
fi

# ECR auth comes from the manager's ecr-login helper; --with-registry-auth
# forwards it to the workers.
if docker service inspect "$SERVICE_NAME" >/dev/null 2>&1; then
  info "Updating service $SERVICE_NAME to ${IMAGE}:${IMAGE_TAG} ..."
  docker service update \
    --image "${IMAGE}:${IMAGE_TAG}" \
    --with-registry-auth \
    --update-order start-first \
    --update-parallelism 1 \
    --update-delay 30s \
    "$SERVICE_NAME"
else
  if [ -z "$DB_PASSWORD" ]; then
    error "DB_PASSWORD is not set. It is required when the service is created:"
    error "  sudo DB_PASSWORD='...' /opt/deploy.sh"
    exit 1
  fi

  DB_ENDPOINT="${DB_ENDPOINT:-$(stack_output DatabaseEndpoint)}"
  if [ -z "$DB_ENDPOINT" ] || [ "$DB_ENDPOINT" = "None" ]; then
    error "Could not read DatabaseEndpoint from stack '$STACK_NAME' in '$REGION'."
    exit 1
  fi

  if [ -z "$DB_PORT" ]; then
    DB_PORT="$(stack_output DatabasePort)"
  fi
  if [ -z "$DB_PORT" ] || [ "$DB_PORT" = "None" ]; then
    DB_PORT="1433"
  fi

  # The image has no RDS CA bundle, so the private RDS connection trusts its certificate.
  CATALOG_CONNECTION="Server=${DB_ENDPOINT},${DB_PORT};Initial Catalog=Microsoft.eShopOnWeb.CatalogDb;User ID=${DB_USERNAME};Password=${DB_PASSWORD};TrustServerCertificate=True;"
  IDENTITY_CONNECTION="Server=${DB_ENDPOINT},${DB_PORT};Initial Catalog=Microsoft.eShopOnWeb.Identity;User ID=${DB_USERNAME};Password=${DB_PASSWORD};TrustServerCertificate=True;"

  # Development is required: Program.cs sends other environments to Azure Key Vault.
  ENV_ARGS=(
    --env "ASPNETCORE_ENVIRONMENT=Development"
    --env "ASPNETCORE_URLS=http://+:${TARGET_PORT}"
    --env "ConnectionStrings__CatalogConnection=${CATALOG_CONNECTION}"
    --env "ConnectionStrings__IdentityConnection=${IDENTITY_CONNECTION}"
  )

  info "Creating service $SERVICE_NAME from ${IMAGE}:${IMAGE_TAG} ..."
  docker service create \
    --name "$SERVICE_NAME" \
    --replicas "$REPLICAS" \
    --constraint 'node.role == worker' \
    --placement-pref 'spread=node.id' \
    --publish "published=${PUBLISHED_PORT},target=${TARGET_PORT},mode=ingress" \
    --restart-condition on-failure \
    --update-order start-first \
    --update-parallelism 1 \
    --update-delay 30s \
    --with-registry-auth \
    "${ENV_ARGS[@]}" \
    "${IMAGE}:${IMAGE_TAG}"
fi

echo
info "Service state:"
docker service ps "$SERVICE_NAME" --no-trunc
echo
info "Published on port ${PUBLISHED_PORT}; the ALB target group health check should now pass."
