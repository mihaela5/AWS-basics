resource "google_service_account" "gke_nodes" {
  project      = var.gcp_project_id
  account_id   = "cloudshirt-gke-nodes"
  display_name = "CloudShirt GKE node service account"
  description  = "Service account used by the CloudShirt GKE worker nodes"
}

# GKE requires logging, monitoring and metadata permissions on the node identity.
resource "google_project_iam_member" "gke_nodes_default" {
  project = var.gcp_project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# Image-pull permission, scoped to the CloudShirt repository only.
resource "google_artifact_registry_repository_iam_member" "gke_nodes_reader" {
  project    = var.gcp_project_id
  location   = google_artifact_registry_repository.cloudshirt_images.location
  repository = google_artifact_registry_repository.cloudshirt_images.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.gke_nodes.email}"
}
