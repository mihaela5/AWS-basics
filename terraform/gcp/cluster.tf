resource "google_container_cluster" "cloudshirt" {
  name        = var.gke_cluster_name
  project     = var.gcp_project_id
  location    = var.gcp_zone
  description = "CloudShirt GKE cluster for the Kubernetes deployment"

  network    = google_compute_network.cloudshirt.id
  subnetwork = google_compute_subnetwork.gke.id

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = "cloudshirt-pods"
    services_secondary_range_name = "cloudshirt-services"
  }

  remove_default_node_pool = true
  initial_node_count       = 1

  release_channel {
    channel = "REGULAR"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.gke_master_ipv4_cidr_block
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.admin_cidr_blocks
      content {
        cidr_block   = cidr_blocks.value
        display_name = "admin-${cidr_blocks.key}"
      }
    }
  }

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  workload_identity_config {
    workload_pool = "${var.gcp_project_id}.svc.id.goog"
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  enable_shielded_nodes = true
  deletion_protection   = false

  resource_labels = {
    application = "cloudshirt"
    managed_by  = "terraform"
    environment = "development"
  }

  lifecycle {
    precondition {
      condition     = startswith(var.gcp_zone, "${var.gcp_region}-")
      error_message = "gcp_zone must be a zone in gcp_region."
    }
  }
}

resource "google_container_node_pool" "cloudshirt" {
  name       = "cloudshirt-node-pool"
  project    = var.gcp_project_id
  cluster    = google_container_cluster.cloudshirt.name
  location   = google_container_cluster.cloudshirt.location
  node_count = var.gke_node_count

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.gke_machine_type
    disk_size_gb = var.gke_node_disk_size_gb
    disk_type    = "pd-standard"
    image_type   = "COS_CONTAINERD"

    # A dedicated service account with narrow IAM roles instead of the default
    # compute account. The cloud-platform scope is required for Artifact
    # Registry; the IAM bindings in iam.tf limit what the identity can do.
    service_account = google_service_account.gke_nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = {
      application = "cloudshirt"
      managed_by  = "terraform"
    }
  }
}
