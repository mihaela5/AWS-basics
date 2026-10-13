# AWS-basics-
Cloud automation concepts - Assignment 1 - AWS basics

## 1. Prerequisites

Before deploying the templates, ensure the following are configured:

* **AWS CLI v2** installed and configured (`aws configure`) with administrative credentials for your target AWS account.
* Access to a terminal with Bash or Zsh.

---

## 2. Prepare the S3 Artifact Bucket

CloudFormation nested stacks require child templates to be accessible via Amazon S3. Create a unique staging bucket in your deployment region:

```bash
# Set your deployment variables
export AWS_REGION="us-east-1"
export STAGING_BUCKET="cloudshirt-cfn-staging-$(aws sts get-caller-identity --query Account --output text)"

# Create the staging bucket
aws s3 mb s3://$STAGING_BUCKET --region $AWS_REGION
```

## 3. Package and deploy

```bash
aws cloudformation package \
  --template-file templates/main.yaml \
  --s3-bucket $STAGING_BUCKET \
  --output-template-file packaged-main.yaml

aws cloudformation deploy \
  --template-file packaged-main.yaml \
  --stack-name CloudShirtInfrastructure \
  --region $AWS_REGION \
  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
  --parameter-overrides \
      KeyName="vockey" \
      DBUsername="cloudshirtadmin" \
      DBPassword="ChangeMe123!"
```

## 4. One-command deploy (provision script)

The manual steps above are automated in `scripts/provision.sh` (Bash) and `scripts/provision.ps1` (Windows PowerShell):

```bash
# Bash (Git Bash / WSL / macOS / Linux)
bash scripts/provision.sh

# Overrides / teardown
bash scripts/provision.sh --region eu-central-1 --key-name vockey
bash scripts/provision.sh --delete
```

The script validates the AWS CLI and credentials, creates the staging bucket if needed, packages the nested templates, deploys (or updates) the `CloudShirtInfrastructure` stack, and prints the outputs of the root stack and all nested stacks. Region resolution: `--region` / `-Region` → `AWS_REGION` → `AWS_DEFAULT_REGION` → AWS CLI configuration → `eu-central-1` (matching the availability-zone defaults in `templates/01-networking.yaml`).

---

## 5. Serverless order insights API

`templates/07-serverless.yaml` provisions a Lambda function behind an API Gateway REST API. It reads the order exports that `scripts/export.sh` writes under the `exports/orders/` prefix of the S3 bucket and returns summaries to the caller. It is deployed as part of the root stack, so it needs no separate step.

Read the invoke URL and the bucket name from the root stack outputs:

```bash
export API="$(aws cloudformation describe-stacks \
  --stack-name CloudShirtInfrastructure \
  --region $AWS_REGION \
  --query "Stacks[0].Outputs[?OutputKey=='OrderInsightsApiEndpoint'].OutputValue" \
  --output text)"

export EXPORT_BUCKET="$(aws cloudformation describe-stacks \
  --stack-name CloudShirtInfrastructure \
  --region $AWS_REGION \
  --query "Stacks[0].Outputs[?OutputKey=='OrderExportBucketName'].OutputValue" \
  --output text)"
```

The API serves four read-only routes:

* `GET /health` — service liveness and the bucket the function reads.
* `GET /exports` — every CSV file under the `exports/orders/` prefix, each with an `id`.
* `GET /exports/{id}` — a summary of one export, for example `/exports/20261012_223600`.
* `GET /summary` — totals and a per-export series across all exports.

```bash
curl "${API}health"
curl "${API}exports"
curl "${API}summary"
```

To test it, copy an export into the bucket:

```bash
aws s3 cp orders.csv "s3://${EXPORT_BUCKET}/exports/orders/orders_20261012_223600.csv"
curl "${API}exports/20261012_223600"
```

Any CSV with an order-number column works. The function matches the remaining columns by name, accepting the common spellings an export is likely to use, and reports the metrics it could not compute under `unavailableMetrics` instead of failing.

The function reads the exports from S3.