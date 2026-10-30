#!/bin/bash
set -euo pipefail

: "${GCP_PROJECT:?GCP_PROJECT is required}"
: "${GCP_REGION:?GCP_REGION is required}"
: "${AR_REPO:?AR_REPO is required}"
: "${REPO_URL:?REPO_URL is required}"
: "${REPO_REF:?REPO_REF is required}"

WORK_DIR="${WORK_DIR:-$HOME/.cache/cloudshirt-src}"
REGISTRY="$GCP_REGION-docker.pkg.dev/$GCP_PROJECT/$AR_REPO"

# Clone the application repository if it does not exist
if [ ! -d "$WORK_DIR/.git" ]; then
    git clone "$REPO_URL" "$WORK_DIR"
fi

# Check out the requested version
cd "$WORK_DIR"
git remote set-url origin "$REPO_URL" 2>/dev/null || git remote add origin "$REPO_URL"
git fetch origin "$REPO_REF" --tags
git checkout --force FETCH_HEAD

# Use the exact commit as the image version
TAG="$(git rev-parse --short=7 HEAD)"

echo "Building CloudShirt images for linux/amd64"
echo "Source commit: $TAG"
echo "Registry: $REGISTRY"

# Use an OAuth access token for Docker; this works with an active gcloud account
# or Application Default Credentials and avoids the gcloud credential helper.
TOKEN="$(gcloud auth print-access-token 2>/dev/null || gcloud auth application-default print-access-token)"
printf '%s' "$TOKEN" | docker login -u oauth2accesstoken --password-stdin "https://$GCP_REGION-docker.pkg.dev"

# Build and push the website image
docker buildx build \
    --platform linux/amd64 \
    --file src/Web/Dockerfile \
    --tag "$REGISTRY/cloudshirt:$TAG" \
    --tag "$REGISTRY/cloudshirt:latest" \
    --push \
    .

# Build and push the public API image
docker buildx build \
    --platform linux/amd64 \
    --file src/PublicApi/Dockerfile \
    --tag "$REGISTRY/cloudshirt-api:$TAG" \
    --tag "$REGISTRY/cloudshirt-api:latest" \
    --push \
    .

echo "Successfully built and pushed both CloudShirt images."
echo "Version: $TAG"
