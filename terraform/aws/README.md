# AWS Terraform

This root module wraps the existing CloudFormation nested stack. It does not
reimplement the templates: Terraform uploads them to the staging S3 bucket,
rewrites the nested `TemplateURL` entries and the Lambda `Code` location, and
creates one `aws_cloudformation_stack` resource.

## Prerequisites

- Terraform >= 1.5
- AWS credentials with the same permissions as `scripts/provision.sh`
- The database password exported as `TF_VAR_db_password` (8–128 characters)
- No CloudFormation stack with the same `stack_name` already running

## First run

On apply, Terraform checks whether `cloudshirt-cfn-staging-<account-id>`
already exists and creates it with `aws s3 mb` if it does not, so the AWS CLI
must be on `PATH`. Terraform does not delete the bucket on
`terraform destroy`, matching `provision.sh`. If you delete the bucket later
while the Terraform state still exists, recreate it with
`terraform apply -replace=terraform_data.staging_bucket`.

```bash
export TF_VAR_db_password='choose-a-strong-password'
terraform init
terraform plan
terraform apply
```

## Notes

- Templates are uploaded under `terraform/templates/<content-hash>/` and the
  Lambda zip under `terraform/lambda/`. A change to any template or the Lambda
  code changes the version prefix, so CloudFormation updates the nested stacks.
- The staging bucket is not an `aws_s3_bucket` resource because the Academy SCP
  denies `s3:GetBucketObjectLockConfiguration`, which the provider reads. The
  `terraform_data` check above creates it with the AWS CLI instead.
- Terraform state is local. It is ignored by Git and must not be committed; it
  contains the database password supplied through `TF_VAR_db_password`.
- `terraform destroy` deletes the CloudFormation stack but leaves the staging
  bucket in place. The templates' retention policies still leave the RDS
  snapshot and the order export S3 bucket behind, as `provision.sh --delete`
  does.
- Do not run `scripts/provision.sh` against the same `stack_name` while
  Terraform is managing the stack.
