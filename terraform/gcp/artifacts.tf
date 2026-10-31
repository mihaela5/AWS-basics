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

resource "terraform_data" "build_cloudshirt_images" {
  triggers_replace = [
    var.gcp_project_id,
    var.gcp_region,
    var.cloudshirt_repo_url
  ]

  depends_on = [
    google_artifact_registry_repository.cloudshirt_images
  ]

  provisioner "local-exec" {
    interpreter = [var.bash_executable]
    command     = "../../scripts/build-and-push.sh"

    environment = {
      GCP_PROJECT = var.gcp_project_id
      GCP_REGION  = var.gcp_region
      AR_REPO     = google_artifact_registry_repository.cloudshirt_images.repository_id
      REPO_URL    = var.cloudshirt_repo_url
      REPO_REF    = "main"
    }
  }
}

