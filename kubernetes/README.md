# CloudShirt on Kubernetes

These manifests deploy CloudShirt to the GKE cluster from `terraform/gcp`.
The website runs as five replicas behind one external IP, the public API runs
as two internal replicas, and SQL Server runs as a single stateful pod with a
persistent volume. Run the commands on this page from the repository root.

| Object | Kind | Purpose |
| --- | --- | --- |
| `cloudshirt` | Namespace | Isolates the application |
| `cloudshirt-config` | ConfigMap | ASP.NET Core environment and service URLs |
| `cloudshirt-db` | Secret | SA password and connection strings, created by the deploy script |
| `cloudshirt-sql` | StatefulSet + Service | SQL Server with an 8 GiB persistent volume |
| `cloudshirt-api` | Deployment + Service | Public API, two internal replicas |
| `cloudshirt-web` | Deployment + Service | Website, five replicas behind a `LoadBalancer` |

## Assignment requirements

| Requirement | Implementation |
| --- | --- |
| REQ-16 | The application is deployed to GCP from these manifests; `scripts/deploy-k8s.sh` applies them. |
| REQ-17 | The `cloudshirt-web` Service is a `LoadBalancer` and gets one external IP. |
| REQ-18 | Every image reference points at the `cloudshirt-images` Artifact Registry repository. |
| REQ-19 | `terraform/gcp/cluster.tf` provisions the GKE cluster and its node pool. |
| REQ-20 | `cloudshirt-web` runs five replicas on the node pool managed by the GKE control plane. |
| REQ-21 | [`ansible/`](../ansible/README.md) prepares the control host, writes the kubeconfig and applies these manifests with the `kubernetes.core` roles. |

## Prerequisites

- The GCP resources from `terraform/gcp` applied: the cluster, the node pool,
  and the `cloudshirt-images` Artifact Registry repository.
- `gcloud` authenticated with access to the project and the GKE cluster.
- `kubectl` and `gke-gcloud-auth-plugin` installed.
- The web and API images built by `terraform apply`, and the SQL Server image
  mirrored into Artifact Registry. See
  [`terraform/gcp/README.md`](../terraform/gcp/README.md).

The worker nodes are private and have no Cloud NAT. They can reach Artifact
Registry through Private Google Access, so every image must be mirrored there;
Docker Hub and `mcr.microsoft.com` are not reachable from the pods.