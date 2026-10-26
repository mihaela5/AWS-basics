resource "aws_cloudformation_stack" "cloudshirt" {
  name               = var.stack_name
  template_body      = local.root_template
  capabilities       = ["CAPABILITY_NAMED_IAM"]
  on_failure         = "ROLLBACK"
  timeout_in_minutes = 60

  parameters = {
    KeyName                    = var.key_name
    BuildserverInstanceProfile = var.buildserver_instance_profile
    WebServerInstanceProfile   = var.webserver_instance_profile
    ImageRetentionCount        = tostring(var.image_retention_count)
    DBUsername                 = var.db_username
    DBPassword                 = var.db_password
    UserDataScriptUrl          = var.userdata_script_url
    AlarmEmail                 = var.alarm_email
  }

  tags = {
    Project   = "CloudShirt"
    ManagedBy = "Terraform"
  }

  depends_on = [
    terraform_data.staging_bucket,
    aws_s3_object.child_templates,
    aws_s3_object.lambda_zip,
  ]
}
