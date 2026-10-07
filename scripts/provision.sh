#!/usr/bin/env bash
# What it does:
#   1. Validates the AWS CLI, your credentials and the nested templates.
#   2. Creates the S3 staging bucket if it does not exist yet.
#   3. Packages templates/main.yaml (uploads the nested templates to S3).
#   4. Creates or updates the CloudShirtInfrastructure root stack.
#   5. Passes the userdata.sh URL to the application stack.
#   6. Prints outputs of the root stack and nested stacks.
#
# Usage:
#   bash scripts/provision.sh [options]

set -euo pipefail
export AWS_PAGER=""

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
TEMPLATE_FILE="${ROOT_DIR}/templates/main.yaml"
PACKAGED_TEMPLATE="${ROOT_DIR}/packaged-main.yaml"
USERDATA_FILE="${ROOT_DIR}/scripts/userdata.sh"


# Defaults (override with CLI flags or environment variables) --------------
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
DEFAULT_REGION="us-east-1"  
STACK_NAME="${STACK_NAME:-CloudShirtInfrastructure}"
STAGING_BUCKET="${STAGING_BUCKET:-}"
KEY_NAME="${KEY_NAME:-vockey}"
DB_USERNAME="${DB_USERNAME:-cloudshirtadmin}"
DB_PASSWORD="${DB_PASSWORD:-ChangeMe123!}"

# Shared repository.
# Can also be overridden using an environment variable.
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-mihaela5/AWS-basics}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"

USERDATA_SCRIPT_URL="${USERDATA_SCRIPT_URL:-https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/${GITHUB_BRANCH}/scripts/userdata.sh}"

DELETE_MODE="false"
ASSUME_YES="false"

info()  { printf '==> %s\n' "$*"; }
error() { printf 'ERROR: %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Usage: bash scripts/provision.sh [options]

Deploys the CloudShirt "AWS Basics" nested CloudFormation stack:
  1. creates the S3 staging bucket (if needed),
  2. packages templates/main.yaml (uploads the nested templates),
  3. creates or updates the root stack, and
  4. prints the outputs of the root and nested stacks.

Options:
  -r, --region REGION      AWS region. Defaults to $AWS_REGION, $AWS_DEFAULT_REGION,
                           your AWS CLI configuration, or eu-central-1.
  -s, --stack-name NAME    Root stack name (default: CloudShirtInfrastructure).
  -b, --bucket NAME        S3 staging bucket (default: cloudshirt-cfn-staging-<account-id>).
  -k, --key-name NAME      EC2 KeyPair name (default: vockey).
  -u, --db-username USER   Database master username (default: cloudshirtadmin).
  -p, --db-password PASS   Database master password (default: ChangeMe123!).
  -d, --delete             Delete the stack and all of its resources.
  -y, --yes                Do not ask for confirmation.
  -h, --help               Show this help and exit.

Examples:
  bash scripts/provision.sh
  bash scripts/provision.sh --region eu-central-1 --key-name vockey
  bash scripts/provision.sh --delete
EOF
}

take_value() {
  [[ -n "${2:-}" ]] || { error "Option $1 requires a value"; exit 1; }
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--region)      take_value "$1" "${2:-}"; REGION="$2";         shift 2 ;;
    -s|--stack-name)  take_value "$1" "${2:-}"; STACK_NAME="$2";     shift 2 ;;
    -b|--bucket)      take_value "$1" "${2:-}"; STAGING_BUCKET="$2"; shift 2 ;;
    -k|--key-name)    take_value "$1" "${2:-}"; KEY_NAME="$2";       shift 2 ;;
    -u|--db-username) take_value "$1" "${2:-}"; DB_USERNAME="$2";    shift 2 ;;
    -p|--db-password) take_value "$1" "${2:-}"; DB_PASSWORD="$2";    shift 2 ;;
    -d|--delete)      DELETE_MODE="true"; shift ;;
    -y|--yes)         ASSUME_YES="true";  shift ;;
    -h|--help)        usage; exit 0 ;;
    *) error "Unknown option: $1"; usage >&2; exit 1 ;;
  esac
done

# Preflight checks
if ! command -v aws >/dev/null 2>&1; then
  error "AWS CLI not found. Install AWS CLI v2 and make sure 'aws' is on your PATH."
  exit 1
fi

if [[ -z "$REGION" ]]; then
  CLI_REGION="$(aws configure get region 2>/dev/null || true)"
  if [[ -n "$CLI_REGION" && "$CLI_REGION" != "None" ]]; then
    REGION="$CLI_REGION"
  else
    REGION="$DEFAULT_REGION"
  fi
fi

info "Checking AWS credentials ..."
if ! ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)"; then
  error "AWS credentials are missing or expired."
  error "Run 'aws configure' or refresh your AWS Academy lab credentials, then try again."
  exit 1
fi

if [[ -z "$STAGING_BUCKET" ]]; then
  STAGING_BUCKET="cloudshirt-cfn-staging-${ACCOUNT_ID}"
fi

# Check required files
[[ -f "$TEMPLATE_FILE" ]] || {
  error "Root template not found: $TEMPLATE_FILE"
  exit 1
}

[[ -f "$USERDATA_FILE" ]] || {
  error "UserData script not found: $USERDATA_FILE"
  exit 1
}


# Safety net: nested stack templates referenced from main.yaml must exist and
# must not be empty placeholders, or the deployment will always fail.
check_nested_templates() {
  local url file missing=() empty=()
  while IFS= read -r url; do
    file="${ROOT_DIR}/templates/${url#./}"
    if [[ ! -f "$file" ]]; then
      missing+=("$url")
    elif [[ ! -s "$file" ]]; then
      empty+=("$url")
    fi
  done < <({ grep -oE '\./[A-Za-z0-9._-]+\.ya?ml' "$TEMPLATE_FILE" || true; } | sort -u)

  if ((${#missing[@]} > 0)); then
    error "Nested templates referenced by main.yaml are missing:"
    printf '        %s\n' "${missing[@]}" >&2
    exit 1
  fi

  if ((${#empty[@]} > 0)); then
    error "These nested templates are empty placeholders, so CloudFormation cannot deploy them:"
    printf '        %s\n' "${empty[@]}" >&2
    error "Fill in the templates (or remove their stacks from templates/main.yaml) and run again."
    exit 1
  fi
}

# Delete mode
if [[ "$DELETE_MODE" == "true" ]]; then
  if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" >/dev/null 2>&1; then
    info "Stack '$STACK_NAME' does not exist in region '$REGION'. Nothing to delete."
    exit 0
  fi

  if [[ "$ASSUME_YES" != "true" ]]; then
    printf 'Delete stack "%s" and ALL of its resources in %s? [y/N] ' "$STACK_NAME" "$REGION"
    read -r REPLY || REPLY=""
    if [[ ! "${REPLY:-}" =~ ^[Yy]$ ]]; then
      echo "Aborted."
      exit 0
    fi
  fi

  info "Deleting stack '$STACK_NAME' ..."
  aws cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION"

  info "Waiting for deletion to complete (this can take a few minutes) ..."
  aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region "$REGION"

  info "Stack deleted."
  echo
  echo "Note: the staging bucket s3://$STAGING_BUCKET (nested templates) was kept."
  echo "      Remove it manually if you no longer need it:"
  echo "        aws s3 rb s3://$STAGING_BUCKET/ --force --region $REGION"
  exit 0
fi

# Deploy mode
[[ -f "$TEMPLATE_FILE" ]] || { error "Root template not found: $TEMPLATE_FILE"; exit 1; }
check_nested_templates

# Deployment information
info "Account : $ACCOUNT_ID"
info "Region  : $REGION"
info "Stack   : $STACK_NAME"
info "Bucket  : s3://$STAGING_BUCKET"
info "UserData: $USERDATA_SCRIPT_URL"
echo

# Ensure staging bucket exists
info "Ensuring staging bucket exists ..."
if aws s3api head-bucket --bucket "$STAGING_BUCKET" 2>/dev/null; then
  info "Staging bucket already exists."
else
  aws s3 mb "s3://$STAGING_BUCKET" --region "$REGION"
  info "Created staging bucket."
fi

info "Packaging nested templates (uploads to s3://$STAGING_BUCKET) ..."
aws cloudformation package \
  --template-file "$TEMPLATE_FILE" \
  --s3-bucket "$STAGING_BUCKET" \
  --region "$REGION" \
  --output-template-file "$PACKAGED_TEMPLATE"

if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" >/dev/null 2>&1; then
  info "Stack exists - applying an update (this can take 10+ minutes) ..."
else
  info "Creating stack (this can take 10+ minutes; the RDS instance is the slow part) ..."
fi

aws cloudformation deploy \
  --template-file "$PACKAGED_TEMPLATE" \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
  --no-fail-on-empty-changeset \
  --parameter-overrides \
      "KeyName=${KEY_NAME}" \
      "DBUsername=${DB_USERNAME}" \
      "DBPassword=${DB_PASSWORD}" \
      "UserDataScriptUrl=${USERDATA_SCRIPT_URL}"

# Report root stack outputs
echo
info "Deployment complete."
echo
printf 'Root stack outputs (%s):\n' "$STACK_NAME"
aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" \
  --query 'Stacks[0].Outputs' --output table

echo
echo "Nested stack outputs:"
CHILD_ARNS="$(aws cloudformation list-stack-resources \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query "StackResourceSummaries[?ResourceType=='AWS::CloudFormation::Stack'].PhysicalResourceId" \
    --output text)"

if [[ -z "$CHILD_ARNS" || "$CHILD_ARNS" == "None" ]]; then
  echo "  (no nested stacks found)"
else
  for CHILD_ARN in $CHILD_ARNS; do
    CHILD_NAME="$(aws cloudformation describe-stacks --stack-name "$CHILD_ARN" --region "$REGION" \
      --query 'Stacks[0].StackName' --output text)"
    echo
    echo "--- ${CHILD_NAME} ---"
    aws cloudformation describe-stacks --stack-name "$CHILD_ARN" --region "$REGION" \
      --query 'Stacks[0].Outputs' --output table
  done
fi

echo
info "Done. Tear everything down with:  bash \"${SCRIPT_DIR}/provision.sh\" --delete"