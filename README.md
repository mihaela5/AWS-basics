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
export AWS_REGION="eu-central-1"
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