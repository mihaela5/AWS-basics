#!/usr/bin/env bash
# Export the CloudShirt "Orders" table from RDS (SQL Server) to S3.
#
#   1. Connects to the RDS database.
#   2. Exports dbo.Orders to a CSV with a UTC timestamp in the file name.
#   3. Uploads the CSV to S3 using the AWS CLI.
#   4. Verifies the object exists in S3.
#
# RDS is private (only the web servers may reach port 1433), so run this
# ON A WEB SERVER EC2 INSTANCE. The instance needs an IAM instance profile
# (AWS Academy: LabInstanceProfile) so the AWS CLI can talk to S3/RDS/CloudFormation.
#
# Usage:   bash scripts/export_orders.sh
# Safe to run repeatedly: every run writes a new, uniquely named file.
#
# Optional overrides (environment variables):
#   DB_ENDPOINT, DB_PORT, DB_NAME, DB_USERNAME, DB_PASSWORD,
#   S3_BUCKET, S3_PREFIX, AWS_REGION, STACK_NAME, DB_INSTANCE_ID

set -euo pipefail
export AWS_PAGER=""

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
STACK_NAME="${STACK_NAME:-CloudShirtInfrastructure}"
DB_INSTANCE_ID="${DB_INSTANCE_ID:-cloudshirt-db}"
DB_ENDPOINT="${DB_ENDPOINT:-}"
DB_PORT="${DB_PORT:-1433}"
DB_NAME="${DB_NAME:-Microsoft.eShopOnWeb.CatalogDb}"
DB_USERNAME="${DB_USERNAME:-cloudshirtadmin}"
DB_PASSWORD="${DB_PASSWORD:-ChangeMe123!}"
S3_BUCKET="${S3_BUCKET:-}"
S3_PREFIX="${S3_PREFIX:-exports/orders}"

info()  { printf '==> %s\n' "$*"; }
error() { printf 'ERROR: %s\n' "$*" >&2; }

# --- Prerequisites ---------------------------------------------------------
if [[ "$(uname -s)" != "Linux" ]]; then
  error "Run this script on a CloudShirt web server (EC2), not on your laptop."
  error "The RDS database is private and cannot be reached from outside the VPC."
  exit 1
fi

command -v aws >/dev/null 2>&1 || { error "AWS CLI not found."; exit 1; }

if ! aws sts get-caller-identity >/dev/null 2>&1; then
  error "No AWS credentials. On EC2, attach an instance profile (e.g. LabInstanceProfile)."
  exit 1
fi

if ! python3 -c "import pymssql" >/dev/null 2>&1; then
  info "Installing Python SQL Server driver (pymssql) ..."
  command -v pip3 >/dev/null 2>&1 || sudo dnf install -y python3-pip
  sudo pip3 install --quiet pymssql
fi

# --- Discover endpoint and bucket if not provided --------------------------
if [[ -z "$DB_ENDPOINT" ]]; then
  info "Looking up RDS endpoint for '$DB_INSTANCE_ID' ..."
  DB_ENDPOINT="$(aws rds describe-db-instances \
    --db-instance-identifier "$DB_INSTANCE_ID" --region "$REGION" \
    --query 'DBInstances[0].Endpoint.Address' --output text)"
fi

if [[ -z "$S3_BUCKET" ]]; then
  info "Looking up S3 bucket from stack '${STACK_NAME}' ..."
  STORAGE_STACK="$(aws cloudformation list-stack-resources \
    --stack-name "$STACK_NAME" --region "$REGION" \
    --query "StackResourceSummaries[?LogicalResourceId=='StorageStack'].PhysicalResourceId" \
    --output text)"
  if [[ -z "$STORAGE_STACK" || "$STORAGE_STACK" == "None" ]]; then
    error "Could not find the StorageStack inside '${STACK_NAME}'. Set S3_BUCKET manually."
    exit 1
  fi
  S3_BUCKET="$(aws cloudformation list-stack-resources \
    --stack-name "$STORAGE_STACK" --region "$REGION" \
    --query "StackResourceSummaries[?ResourceType=='AWS::S3::Bucket'].PhysicalResourceId" \
    --output text)"
fi

if [[ -z "$DB_ENDPOINT" || "$DB_ENDPOINT" == "None" ]]; then error "Could not determine DB endpoint."; exit 1; fi
if [[ -z "$S3_BUCKET"   || "$S3_BUCKET"   == "None" ]]; then error "Could not determine S3 bucket.";   exit 1; fi

# --- Export ----------------------------------------------------------------
TIMESTAMP="$(date -u +%Y%m%d_%H%M%S)"
FILE_NAME="orders_${TIMESTAMP}.csv"
S3_KEY="${S3_PREFIX}/${FILE_NAME}"
TMP_DIR="$(mktemp -d)"
OUT_FILE="${TMP_DIR}/${FILE_NAME}"
trap 'rm -rf "$TMP_DIR"' EXIT

info "Database : ${DB_ENDPOINT}:${DB_PORT} / ${DB_NAME}"
info "Exporting dbo.Orders to ${FILE_NAME} ..."

export DB_ENDPOINT DB_PORT DB_NAME DB_USERNAME DB_PASSWORD
ROWS="$(python3 - "$OUT_FILE" <<'PY'
import csv, os, sys
import pymssql

out_file = sys.argv[1]
conn = pymssql.connect(
    server=os.environ["DB_ENDPOINT"],
    port=os.environ["DB_PORT"],
    user=os.environ["DB_USERNAME"],
    password=os.environ["DB_PASSWORD"],
    database=os.environ["DB_NAME"],
    login_timeout=15,
)
cur = conn.cursor()
cur.execute("SELECT * FROM dbo.Orders ORDER BY Id")
columns = [c[0] for c in cur.description]

count = 0
with open(out_file, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(columns)
    for row in cur:
        writer.writerow(row)
        count += 1
conn.close()
print(count)
PY
)"
info "Exported ${ROWS} order row(s)."

# --- Upload ----------------------------------------------------------------
info "Uploading to s3://${S3_BUCKET}/${S3_KEY} ..."
aws s3 cp "$OUT_FILE" "s3://${S3_BUCKET}/${S3_KEY}" --region "$REGION"

# --- Verify ----------------------------------------------------------------
info "Verifying upload ..."
SIZE="$(aws s3api head-object --bucket "$S3_BUCKET" --key "$S3_KEY" \
  --region "$REGION" --query ContentLength --output text)"
info "Verified: s3://${S3_BUCKET}/${S3_KEY} (${SIZE} bytes)"
echo
aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/" --region "$REGION"
