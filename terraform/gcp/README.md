# Google Cloud Terraform

This root module provisions Google Cloud resources for CloudShirt using Terraform. It is separate from the AWS Terraform root module in `terraform/aws`, which manages the existing CloudFormation-based AWS architecture.

The GCP module configures the Google provider, creates a Cloud Storage bucket, and exposes deployment details through Terraform outputs. It does not modify or recreate the existing AWS infrastructure.

## Prerequisites

- Terraform >= 1.5
- A Google Cloud project with billing enabled
- Google Cloud CLI (`gcloud`) installed
- Google Cloud credentials configured using Application Default Credentials (ADC)
- The Cloud Storage API enabled in the target project
- Permissions to create, view, and manage Cloud Storage buckets in the target project
- A globally unique Cloud Storage bucket name

## Configuration

Create a `terraform.tfvars` file in this directory with your project-specific values:

```hcl
gcp_project_id  = "your-gcp-project-id"
gcp_region      = "europe-west4"
gcp_bucket_name = "cloudshirt-your-unique-suffix-gcp"
```

Replace the example values with your actual Google Cloud project ID and a globally unique bucket name.

Do not commit `terraform.tfvars` if it contains private configuration. Commit `terraform.tfvars.example` with placeholder values instead.

## First run

Authenticate with Google Cloud and select your project:

```bash
gcloud auth application-default login
gcloud config set project YOUR_GCP_PROJECT_ID
gcloud services enable storage.googleapis.com
```

Initialize and validate the Terraform configuration:

```bash
terraform init
terraform fmt
terraform validate
terraform plan
```

Review the plan to confirm that Terraform will create only the intended Google Cloud resources.

Apply the configuration:

```bash
terraform apply
```

Terraform will ask for confirmation before creating the resources unless automatic approval is explicitly enabled.

## Outputs

After a successful deployment, inspect the available outputs:

```bash
terraform output
```

The module exposes:

- `gcp_project_id` — Google Cloud project hosting the resources.
- `gcp_region` — configured Google Cloud region.
- `gcp_bucket_name` — name of the Cloud Storage bucket.
- `gcp_bucket_url` — Cloud Storage URI in the format `gs://<bucket-name>`.

You can retrieve the bucket URI directly:

```bash
terraform output -raw gcp_bucket_url
```

## Verification

Check that the bucket exists in Google Cloud:

```bash
gcloud storage buckets describe gs://BUCKET_NAME
```

Alternatively, use the bucket name returned by Terraform:

```bash
gcloud storage buckets describe "gs://$(terraform output -raw gcp_bucket_name)"
```

## State and cleanup

- Terraform state is managed independently from the AWS Terraform state because this module is in a separate directory.
- Do not commit `.terraform/` or local state files such as `terraform.tfstate`. Keep `.terraform.lock.hcl` under version control.
- The bucket is configured with `force_destroy = false`, so Terraform will not automatically empty a non-empty bucket to delete it.
- To destroy the GCP resources managed by this module, run `terraform destroy` from this directory after reviewing the plan.
- Remove any objects stored in the bucket before attempting to destroy it if it is no longer needed.
- Do not run `terraform destroy` from `terraform/aws` when your intention is to remove only the GCP resources.

## Notes

- This module provisions Google Cloud resources independently of the AWS deployment. Applying it does not deploy CloudShirt's application to Google Cloud.
- The GCP project ID, region, and bucket name are configurable through Terraform variables.
- Google Cloud credentials are supplied through Application Default Credentials; service-account keys should not be committed to the repository.
- Keep the AWS and GCP Terraform state files separate unless you deliberately introduce a shared orchestration and state-management design.
