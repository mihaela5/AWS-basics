variable "gcp_project_id" {
  description = "Google Cloud project ID for the GCP deployment"
  type        = string
  default     = "cloud-orchestration-512823"
}

variable "gcp_region" {
  description = "Google Cloud region for the GCP deployment"
  type        = string
  default     = "europe-west4"
}

variable "gcp_bucket_name" {
  description = "Globally unique name for the CloudShirt Google Cloud Storage bucket"
  type        = string
  default     = "cloudshirt-mihaela-gcp-512823"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$", var.gcp_bucket_name))
    error_message = "Provide a valid Google Cloud Storage bucket name."
  }
}