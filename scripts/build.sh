#!/bin/bash
set -euo pipefail

export HOME=/root
LOG_FILE=/var/log/nightly-build.log
REPO_DIR=/opt/CloudShirt

exec >> "$LOG_FILE" 2>&1

# Prevent two builds from overlapping 
exec 9>/var/lock/nightly-build.lock
flock -n 9 || { echo "Another build is already running, exiting."; exit 1; }

trap 'echo "=== Build FAILED at $(date -Is) (line $LINENO) ==="' ERR
echo "=== Build started $(date -Is) ==="

REGION="$(aws configure get region)"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"
DATE_TAG="$(date +%Y-%m-%d)"


git config --global --add safe.directory "$REPO_DIR"

cd "$REPO_DIR"
git pull --ff-only

# ECR auth comes from the ecr-login credential helper; docker login cannot store through it.

# Compose needs SA_PASSWORD to parse the local SQL service; the cloud build uses RDS.
export SA_PASSWORD="${SA_PASSWORD:-CloudShirtComposeOnly123!}"

docker compose build

# Push only images built by this repository, not pulled base images.
for IMAGE in $(docker compose config --images); do
  case "$IMAGE" in
    */*)
      echo "Skipping $IMAGE (external registry image)"
      continue
      ;;
  esac

  if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "Skipping $IMAGE (not built locally)"
    continue
  fi

  NAME="$(basename "$IMAGE")"   # strip any registry/path prefix
  NAME="${NAME%%:*}"            # strip any tag
  TARGET="$REGISTRY/$NAME"

  docker tag "$IMAGE" "$TARGET:$DATE_TAG"
  docker tag "$IMAGE" "$TARGET:latest"

  docker push "$TARGET:$DATE_TAG"
  docker push "$TARGET:latest"
  echo "Pushed $TARGET:$DATE_TAG and :latest"
done

# Reclaim disk space from old layers
docker image prune -f

echo "=== Build finished $(date -Is) ==="
