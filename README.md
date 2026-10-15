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

---

## 6. Docker image

The CloudShirt source lives in its own repository. We forked it to `https://github.com/athype/CloudShirt` so that the image definition sits next to the code it builds, and so the Buildserver builds a revision we control rather than whatever upstream `main` happens to be that night.

* `src/Web/Dockerfile` — three stages: the SDK image restores and publishes, the ASP.NET runtime image receives only the published output.
* `.dockerignore` — keeps `.git`, build output, tests and local configuration out of the build context.

### Build locally

```bash
git clone https://github.com/athype/CloudShirt.git
cd CloudShirt
docker build -f src/Web/Dockerfile -t cloudshirt/web:local .
```

The build needs network access: the NuGet restore downloads packages, and `src/Web/wwwroot/lib` is git-ignored, so the client-side libraries are restored from cdnjs during publish. Copying only the `.csproj` files before `dotnet restore` keeps that download in its own layer, so editing application code does not repeat it.

### Run locally

Without a database the application still starts, but the catalog pages stay empty. For a quick check of the image, run it against the in-memory database the application supports:

```bash
docker run --rm -p 8080:80 -e UseOnlyInMemoryDatabase=true cloudshirt/web:local
```

<http://localhost:8080> then serves the storefront with seeded catalog data.

### How the connection strings are injected

Nothing is baked into the image. The application reads both connection strings through the standard ASP.NET Core configuration chain, where environment variables override `appsettings.json`, so nested keys use a double underscore:

```bash
docker run --rm -p 8080:80 \
  -e ConnectionStrings__CatalogConnection="Server=<rds-endpoint>,1433;User ID=<user>;Password=<password>;Initial Catalog=Microsoft.eShopOnWeb.CatalogDb;TrustServerCertificate=True;" \
  -e ConnectionStrings__IdentityConnection="Server=<rds-endpoint>,1433;User ID=<user>;Password=<password>;Initial Catalog=Microsoft.eShopOnWeb.Identity;TrustServerCertificate=True;" \
  cloudshirt/web:local
```

The image sets `ASPNETCORE_ENVIRONMENT=Development` because `src/Web/Program.cs` only reads the connection strings from configuration in the `Development` and `Docker` environments. Every other value sends the application to Azure Key Vault, which this deployment does not have: the startup would fail while constructing the Key Vault client. `src/Web/appsettings.Docker.json` is excluded through `.dockerignore` because it contains a hard-coded SQL Server password.

The container listens on port 80 (`ASPNETCORE_URLS`), which is the port the Swarm services publish.