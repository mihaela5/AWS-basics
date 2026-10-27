
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

output "artifact_registry_repository" {
  description = "Artifact Registry repository name"
  value       = google_artifact_registry_repository.cloudshirt_images.name
}

output "artifact_registry_url" {
  description = "Docker registry URL for CloudShirt images"
  value       = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.cloudshirt_images.repository_id}"
}


output "gke_cluster_name" {
  description = "Name of the CloudShirt GKE cluster"
  value       = google_container_cluster.cloudshirt.name
}

output "gke_cluster_location" {
  description = "Location of the GKE cluster"
  value       = google_container_cluster.cloudshirt.location
}

output "gke_get_credentials_command" {
  description = "Command to configure kubectl for this cluster"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.cloudshirt.name} --location ${google_container_cluster.cloudshirt.location} --project ${var.gcp_project_id}"
}
