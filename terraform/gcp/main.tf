
resource "google_storage_bucket" "cloudshirt" {
  name                        = var.gcp_bucket_name
  project                     = var.gcp_project_id
  location                    = var.gcp_region
  uniform_bucket_level_access = true

  labels = {
    application = "cloudshirt"
    managed_by  = "terraform"
    environment = "development"
  }

  # Avoid deleting stored data accidentally.
  force_destroy = false
}

resource "google_artifact_registry_repository" "cloudshirt_images" {
  project       = var.gcp_project_id
  location      = var.gcp_region
  repository_id = "cloudshirt-images"
  description   = "Docker images for the CloudShirt application"
  format        = "DOCKER"
}


resource "google_container_cluster" "cloudshirt" {
  name     = var.gke_cluster_name
  location = "europe-west4-a"
  project  = var.gcp_project_id

  deletion_protection      = false
  remove_default_node_pool = true
  initial_node_count       = 1

  networking_mode = "VPC_NATIVE"
}

resource "google_container_node_pool" "cloudshirt" {
  name     = "cloudshirt-node-pool"
  location = google_container_cluster.cloudshirt.location
  cluster  = google_container_cluster.cloudshirt.name
  project  = var.gcp_project_id

  node_count = var.gke_node_count

  node_config {
    machine_type = var.gke_machine_type
    disk_size_gb = 30
    disk_type    = "pd-standard"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}
