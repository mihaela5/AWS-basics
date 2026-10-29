output "gcp_project_id" {
  description = "Google Cloud project hosting the CloudShirt resources"
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
  description = "Artifact Registry repository ID"
  value       = google_artifact_registry_repository.cloudshirt_images.repository_id
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
  description = "Location (zone) of the GKE cluster"
  value       = google_container_cluster.cloudshirt.location
}

output "gke_cluster_endpoint" {
  description = "Public endpoint of the GKE control plane"
  value       = google_container_cluster.cloudshirt.endpoint
}

output "gke_cluster_ca_certificate" {
  description = "CA certificate for the GKE cluster"
  value       = google_container_cluster.cloudshirt.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "gke_get_credentials_command" {
  description = "Command to configure kubectl for this cluster"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.cloudshirt.name} --location ${google_container_cluster.cloudshirt.location} --project ${var.gcp_project_id}"
}

output "gke_node_pool_name" {
  description = "Name of the CloudShirt GKE node pool"
  value       = google_container_node_pool.cloudshirt.name
}

output "gke_node_service_account_email" {
  description = "Service account used by the GKE worker nodes"
  value       = google_service_account.gke_nodes.email
}

output "gke_workload_identity_pool" {
  description = "Workload Identity pool for Kubernetes service accounts"
  value       = "${var.gcp_project_id}.svc.id.goog"
}
