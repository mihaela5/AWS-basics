variable "gcp_project_id" {
  description = "Google Cloud project ID for the GCP deployment"
  type        = string
  default     = "cloud-orchestration-512823"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.gcp_project_id))
    error_message = "Provide a valid Google Cloud project ID."
  }
}

variable "gcp_region" {
  description = "Google Cloud region for the GCP deployment"
  type        = string
  default     = "europe-west4"

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]$", var.gcp_region))
    error_message = "Provide a valid Google Cloud region such as europe-west4."
  }
}

variable "gcp_zone" {
  description = "Google Cloud zone for the zonal GKE cluster"
  type        = string
  default     = "europe-west4-a"

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]-[a-z]$", var.gcp_zone))
    error_message = "Provide a valid Google Cloud zone such as europe-west4-a."
  }
}

variable "admin_cidr_blocks" {
  description = "IPv4 CIDR blocks allowed to reach the public GKE control-plane endpoint."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = length(var.admin_cidr_blocks) > 0 && alltrue([for cidr in var.admin_cidr_blocks : can(cidrnetmask(cidr))])
    error_message = "Provide at least one valid IPv4 CIDR block, for example 0.0.0.0/0 or 203.0.113.10/32."
  }
}

variable "gcp_bucket_name" {
  description = "Globally unique name for the CloudShirt Google Cloud Storage bucket. Defaults to cloudshirt-<project-id>-gcp."
  type        = string
  default     = ""

  validation {
    condition     = var.gcp_bucket_name == "" || can(regex("^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$", var.gcp_bucket_name))
    error_message = "Provide a valid Google Cloud Storage bucket name."
  }
}

variable "gke_cluster_name" {
  description = "Name of the CloudShirt GKE cluster"
  type        = string
  default     = "cloudshirt-gke"
}

variable "gke_node_count" {
  description = "Number of worker nodes in the GKE node pool"
  type        = number
  default     = 2

  validation {
    condition     = var.gke_node_count >= 1 && var.gke_node_count <= 10
    error_message = "gke_node_count must be between 1 and 10."
  }
}

variable "gke_machine_type" {
  description = "Compute Engine machine type for GKE workers"
  type        = string
  default     = "e2-standard-2"
}

variable "gke_node_disk_size_gb" {
  description = "Boot disk size in GB for each GKE worker node"
  type        = number
  default     = 30

  validation {
    condition     = var.gke_node_disk_size_gb >= 10 && var.gke_node_disk_size_gb <= 500
    error_message = "gke_node_disk_size_gb must be between 10 and 500."
  }
}

variable "gke_master_ipv4_cidr_block" {
  description = "IPv4 CIDR block for the GKE control plane. Must be a /28 that does not overlap the VPC."
  type        = string
  default     = "172.16.0.0/28"

  validation {
    condition     = can(cidrnetmask(var.gke_master_ipv4_cidr_block)) && can(regex("/28$", var.gke_master_ipv4_cidr_block))
    error_message = "gke_master_ipv4_cidr_block must be an IPv4 /28 CIDR block."
  }
}

variable "cloudshirt_repo_url" {
  description = "Git URL of the CloudShirt source repository to build images from"
  type        = string
  default     = "https://github.com/athype/CloudShirt"
}

