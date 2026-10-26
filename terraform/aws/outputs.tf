output "stack_id" {
  description = "ID of the root CloudFormation stack"
  value       = aws_cloudformation_stack.cloudshirt.id
}

output "stack_name" {
  description = "Name of the root CloudFormation stack"
  value       = aws_cloudformation_stack.cloudshirt.name
}

output "staging_bucket_name" {
  description = "S3 bucket holding the Terraform-uploaded CloudFormation artifacts"
  value       = local.staging_bucket_name
}

output "stack_outputs" {
  description = "All outputs from the root CloudFormation stack"
  value       = aws_cloudformation_stack.cloudshirt.outputs
}

output "buildserver_instance_id" {
  description = "Instance ID of the CloudShirt Buildserver"
  value       = try(aws_cloudformation_stack.cloudshirt.outputs["BuildserverInstanceId"], null)
}

output "buildserver_private_ip" {
  description = "Private IP address of the CloudShirt Buildserver"
  value       = try(aws_cloudformation_stack.cloudshirt.outputs["BuildserverPrivateIp"], null)
}

output "ecr_repository_name" {
  description = "Name of the CloudShirt ECR repository"
  value       = try(aws_cloudformation_stack.cloudshirt.outputs["EcrRepositoryName"], null)
}

output "ecr_repository_uri" {
  description = "URI used to tag and push CloudShirt images"
  value       = try(aws_cloudformation_stack.cloudshirt.outputs["EcrRepositoryUri"], null)
}

output "order_insights_api_endpoint" {
  description = "Invoke URL of the CloudShirt order insights API"
  value       = try(aws_cloudformation_stack.cloudshirt.outputs["OrderInsightsApiEndpoint"], null)
}

output "order_export_bucket_name" {
  description = "S3 bucket holding the order exports"
  value       = try(aws_cloudformation_stack.cloudshirt.outputs["OrderExportBucketName"], null)
}

output "autoscaling_group_name" {
  description = "Name of the CloudShirt Auto Scaling Group"
  value       = try(aws_cloudformation_stack.cloudshirt.outputs["AutoScalingGroupName"], null)
}
