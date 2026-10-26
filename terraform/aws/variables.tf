variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"

  # Networking defaults to us-east-1a/b.
  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.aws_region))
    error_message = "aws_region must be a valid AWS region such as us-east-1."
  }
}

variable "stack_name" {
  description = "Name of the root CloudFormation stack"
  type        = string
  default     = "CloudShirtInfrastructure"
}

variable "staging_bucket_name" {
  description = "S3 bucket used for CloudFormation artifacts. Defaults to cloudshirt-cfn-staging-<account-id>."
  type        = string
  default     = ""

  validation {
    condition     = var.staging_bucket_name == "" || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.staging_bucket_name))
    error_message = "staging_bucket_name must be a valid S3 bucket name (3-63 lowercase letters, digits, dots, or hyphens)."
  }
}

variable "key_name" {
  description = "EC2 KeyPair for SSH administration"
  type        = string
  default     = "vockey"
}

variable "db_username" {
  description = "RDS SQL Server master username"
  type        = string
  default     = "cloudshirtadmin"
}

variable "db_password" {
  description = "RDS SQL Server master password. Supply it via TF_VAR_db_password; never commit it."
  type        = string
  sensitive   = true
  nullable    = false

  validation {
    condition     = length(var.db_password) >= 8 && length(var.db_password) <= 128
    error_message = "db_password must be between 8 and 128 characters."
  }
}

variable "userdata_script_url" {
  description = "URL of the EC2 userdata script fetched by the application instances"
  type        = string
  default     = "https://raw.githubusercontent.com/mihaela5/AWS-basics/main/scripts/userdata.sh"
}

variable "buildserver_instance_profile" {
  description = "Existing instance profile for the Buildserver. Leave empty to create a dedicated role."
  type        = string
  default     = "LabInstanceProfile"
}

variable "webserver_instance_profile" {
  description = "Existing instance profile for the web servers. Leave empty to create a dedicated role."
  type        = string
  default     = "LabInstanceProfile"
}

variable "alarm_email" {
  description = "Optional email address for CloudWatch alarm notifications"
  type        = string
  default     = ""
}

variable "image_retention_count" {
  description = "Number of images kept in the CloudShirt ECR repository"
  type        = number
  default     = 10

  validation {
    condition     = var.image_retention_count >= 1 && var.image_retention_count <= 100
    error_message = "image_retention_count must be between 1 and 100."
  }
}
