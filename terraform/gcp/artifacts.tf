locals {
  bucket_name = var.gcp_bucket_name != "" ? var.gcp_bucket_name : "cloudshirt-${var.gcp_project_id}-gcp"
}

resource "google_storage_bucket" "cloudshirt" {
  name                        = local.bucket_name
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

  labels = {
    application = "cloudshirt"
    managed_by  = "terraform"
    environment = "development"
  }
}
