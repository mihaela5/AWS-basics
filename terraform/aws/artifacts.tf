data "aws_caller_identity" "current" {}

locals {
  templates_dir = "${path.module}/../../templates"
  lambda_dir    = "${path.module}/../../lambda/order_insights"

  staging_bucket_name = (
    var.staging_bucket_name != ""
    ? var.staging_bucket_name
    : "cloudshirt-cfn-staging-${data.aws_caller_identity.current.account_id}"
  )

  child_template_files = [
    "01-networking.yaml",
    "02-security.yaml",
    "03-storage.yaml",
    "04-database.yaml",
    "05-application.yaml",
    "06-monitoring.yaml",
    "07-serverless.yaml",
    "08-cloudwatch.yaml",
    "09-buildserver.yaml",
    "10-ecr.yaml",
  ]

  lambda_zip_key = "terraform/lambda/order_insights-${data.archive_file.order_insights.output_sha256}.zip"

  # Replace the local Lambda path with its uploaded S3 object.
  serverless_template = replace(
    file("${local.templates_dir}/07-serverless.yaml"),
    "      Code: ../lambda/order_insights",
    "      Code:\n        S3Bucket: ${local.staging_bucket_name}\n        S3Key: ${local.lambda_zip_key}"
  )

  template_bodies = {
    for name in local.child_template_files : name => (
      name == "07-serverless.yaml"
      ? local.serverless_template
      : file("${local.templates_dir}/${name}")
    )
  }

  # New prefix when templates change, so CloudFormation updates the nested stacks.
  templates_version = substr(sha256(join("", [
    for name in local.child_template_files : local.template_bodies[name]
  ])), 0, 12)

  template_keys = {
    for name in local.child_template_files : name => "terraform/templates/${local.templates_version}/${name}"
  }

  # Rewrite nested template URLs to S3.
  root_template = replace(
    file("${local.templates_dir}/main.yaml"),
    "TemplateURL: ./",
    "TemplateURL: https://${local.staging_bucket_name}.s3.${var.aws_region}.amazonaws.com/terraform/templates/${local.templates_version}/"
  )
}

# Reuse provision.sh's staging bucket, creating it if missing; keep it on destroy.
resource "terraform_data" "staging_bucket" {
  triggers_replace = [local.staging_bucket_name]

  provisioner "local-exec" {
    command = "aws s3api head-bucket --bucket \"${local.staging_bucket_name}\" || aws s3 mb \"s3://${local.staging_bucket_name}\" --region \"${var.aws_region}\""
  }
}

data "archive_file" "order_insights" {
  type        = "zip"
  source_file = "${local.lambda_dir}/insights.py"
  output_path = "${path.module}/.terraform/order_insights.zip"
}

resource "aws_s3_object" "child_templates" {
  for_each = local.template_bodies

  bucket       = local.staging_bucket_name
  key          = local.template_keys[each.key]
  content      = each.value
  content_type = "text/yaml"

  depends_on = [terraform_data.staging_bucket]
}

resource "aws_s3_object" "lambda_zip" {
  bucket       = local.staging_bucket_name
  key          = local.lambda_zip_key
  source       = data.archive_file.order_insights.output_path
  etag         = data.archive_file.order_insights.output_md5
  content_type = "application/zip"

  depends_on = [terraform_data.staging_bucket]
}

check "template_urls_rewritten" {
  assert {
    condition     = !strcontains(local.root_template, "TemplateURL: ./")
    error_message = "Not all nested TemplateURL values in templates/main.yaml were rewritten to S3 URLs."
  }
}

check "lambda_code_rewritten" {
  assert {
    condition     = strcontains(local.serverless_template, "S3Bucket: ${local.staging_bucket_name}")
    error_message = "The Lambda Code in templates/07-serverless.yaml was not rewritten to an S3 location."
  }
}
