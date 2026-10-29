resource "google_compute_network" "cloudshirt" {
  name                    = "cloudshirt-gcp-vpc"
  project                 = var.gcp_project_id
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  description             = "CloudShirt GCP VPC for the GKE cluster"
}

resource "google_compute_subnetwork" "gke" {
  name                     = "cloudshirt-gke-subnet"
  project                  = var.gcp_project_id
  region                   = var.gcp_region
  network                  = google_compute_network.cloudshirt.id
  ip_cidr_range            = "10.128.0.0/20"
  private_ip_google_access = true
  description              = "GKE nodes, pods and services for CloudShirt"

  secondary_ip_range {
    range_name    = "cloudshirt-pods"
    ip_cidr_range = "10.129.0.0/16"
  }

  secondary_ip_range {
    range_name    = "cloudshirt-services"
    ip_cidr_range = "10.130.0.0/20"
  }
}
