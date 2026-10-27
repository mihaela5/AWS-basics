
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