
output "gcp_project_id" {
  description = "Google Cloud project hosting the CloudShirt resource"
  value       = var.gcp_project_id
}

output "gcp_region" {
  description = "Configured Google Cloud region"
  value       = var.gcp_region
}

output "gcp_bucket_name" {
  description = "Name of the CloudShirt Google Cloud Storage bucket"
  value       = google_storage_bucket.cloudshirt.name
}

output "gcp_bucket_url" {
  description = "Google Cloud Storage URL for the bucket"
  value       = "gs://${google_storage_bucket.cloudshirt.name}"
}
