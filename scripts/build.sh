 -euo pipefail

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

# ECR login 
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

docker compose build

# Tag and push every image defined in docker-compose.yml.
for IMAGE in $(docker compose config --images); do
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
