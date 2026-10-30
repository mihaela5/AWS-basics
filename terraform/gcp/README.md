# Google Cloud Terraform

This root module provisions the Google Cloud half of the CloudShirt multi-cloud
deployment: a dedicated VPC, a private zonal GKE cluster, a two-node worker pool,
a dedicated node service account with image-pull permission on Artifact
Registry, a Docker repository and a Cloud Storage bucket. It is separate from
the AWS root module in `terraform/aws`, which keeps its own state.

## Architecture

| Resource | Name | Purpose |
| --- | --- | --- |
| VPC | `cloudshirt-gcp-vpc` | Isolated network for the cluster |
| Subnet | `cloudshirt-gke-subnet` (`10.128.0.0/20`) | Node IP range; Private Google Access enabled |
| Pod secondary range | `cloudshirt-pods` (`10.129.0.0/16`) | Pod IP addresses |
| Service secondary range | `cloudshirt-services` (`10.130.0.0/20`) | Service ClusterIP addresses |
| Control-plane range | `172.16.0.0/28` | GKE private-cluster control-plane peering |
| GKE cluster | `cloudshirt-gke` (zonal) | Private nodes, public control-plane endpoint |
| Node pool | `cloudshirt-node-pool` | 2 × `e2-standard-2` workers by default |
| Node service account | `cloudshirt-gke-nodes` | Logging, monitoring, Artifact Registry read |
| Artifact Registry | `cloudshirt-images` (`europe-west4`) | Docker images for the application |
| Cloud Storage | `cloudshirt-<project>-gcp` | Shared bucket for the GCP deployment |

The GCP address plan (`10.128.0.0/20` for nodes, `10.129.0.0/16` for pods and
`10.130.0.0/20` for services) does not overlap the AWS VPC's `10.0.0.0/16` in
`templates/01-networking.yaml`, so the networks can be connected later without
renumbering.

## Prerequisites

- Terraform >= 1.5
- Google Cloud CLI (`gcloud`) with the `gke-gcloud-auth-plugin` component
- `kubectl`
- Docker with `buildx`, `git` and `bash` (Git Bash on Windows) for the image
  build that runs during `terraform apply`. Terraform executes the build script
  with `bash`; on Windows, set `bash_executable` to Git Bash when WSL's
  `bash.exe` comes first on `PATH`
- Application Default Credentials (`gcloud auth application-default login`)
- A project with billing enabled
- Permissions to create networks, GKE clusters, service accounts and Artifact
  Registry repositories (the project Owner role covers this)
- The following APIs enabled: `compute.googleapis.com`,
  `container.googleapis.com`, `artifactregistry.googleapis.com`,
  `iam.googleapis.com` and `storage.googleapis.com`

For a fresh project, enable the APIs once:

```bash
gcloud services enable \
  compute.googleapis.com \
  container.googleapis.com \
  artifactregistry.googleapis.com \
  iam.googleapis.com \
  storage.googleapis.com \
  --project YOUR_PROJECT_ID
```

## Configuration

Create `terraform.tfvars` from `terraform.tfvars.example`:

```hcl
gcp_project_id    = "cloud-orchestration-512823"
gcp_region        = "europe-west4"
gcp_zone          = "europe-west4-a"
gcp_bucket_name   = "cloudshirt-405019634597-gcp"
admin_cidr_blocks = ["0.0.0.0/0"]

gke_node_count   = 2
gke_machine_type = "e2-standard-2"

# Windows only: use Git Bash when WSL's bash.exe comes first on PATH.
# bash_executable = "C:/Program Files/Git/bin/bash.exe"
```

`terraform.tfvars` is ignored by Git. `gcp_bucket_name` is optional and defaults
to `cloudshirt-<project-id>-gcp`.

### Control-plane access

`admin_cidr_blocks` controls who can reach the **public GKE control-plane
endpoint**. The variable has no default so each environment chooses explicitly.
The example and this repository's `terraform.tfvars` use `0.0.0.0/0` because the
operator's public IP changes; access still requires valid Google IAM
credentials. The worker nodes remain private. In a production deployment,
replace it with the operator's `/32` (or the CI runner's address range).

## First run

Authenticate and select the project:

```bash
gcloud auth application-default login
gcloud config set project cloud-orchestration-512823
```

Initialise, validate and review:

```bash
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

`terraform init` creates `.terraform.lock.hcl`; keep it under version control.
Do not commit `terraform.tfvars` or any `*.tfstate` file.

## Outputs

| Output | Use |
| --- | --- |
| `artifact_registry_url` | Registry prefix for `docker tag` / `docker push` |
| `gke_cluster_name`, `gke_cluster_location` | Cluster identity |
| `gke_cluster_endpoint` | Public control-plane endpoint |
| `gke_cluster_ca_certificate` | Cluster CA (marked sensitive) |
| `gke_get_credentials_command` | Writes the kubeconfig used by `kubectl` and Ansible |
| `gke_node_pool_name` | Node pool name |
| `gke_node_service_account_email` | Node identity used for image pulls |
| `gke_workload_identity_pool` | Pool for Kubernetes service accounts |

Write the kubeconfig with:

```bash
eval "$(terraform output -raw gke_get_credentials_command)"
```

On Windows PowerShell:

```powershell
Invoke-Expression (terraform output -raw gke_get_credentials_command)
```

## Verify the cluster

```bash
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -A
```

Expected: one control-plane endpoint, two nodes in `Ready` state with only
internal IP addresses, and all `kube-system` pods running.

Check the private-node configuration:

```bash
gcloud container clusters describe cloudshirt-gke \
  --zone europe-west4-a \
  --format="value(privateClusterConfig.enablePrivateNodes)"
```

Test image pulls through Private Google Access. The sample image lives in a
public Google Artifact Registry repository, so it works without Cloud NAT:

```bash
kubectl run image-pull-test \
  --image=us-docker.pkg.dev/google-samples/containers/gke/hello-app:1.0 \
  --restart=Never
kubectl get pod image-pull-test
kubectl delete pod image-pull-test
```

Test that the node pool can host five replicas:

```bash
kubectl create deployment capacity-test \
  --image=us-docker.pkg.dev/google-samples/containers/gke/hello-app:1.0 \
  --replicas=5
kubectl rollout status deployment/capacity-test
kubectl get pods -o wide
kubectl delete deployment capacity-test
```

## Deploy the application

The CloudShirt workload is described in
[`kubernetes/README.md`](../../kubernetes/README.md). It uses the
`artifact_registry_url` output for the image references and the
`gke_get_credentials_command` output for the kubeconfig. `scripts/deploy-k8s.sh`
reads the project, region, zone, cluster name and registry URL from this
module's state when they are not passed as environment variables.

[`ansible/`](../../ansible/README.md) performs the same rollout through Ansible:
`ansible-playbook ansible/playbooks/site.yml` prepares the control host, writes
the kubeconfig and applies the manifests. It is a separate step after
`terraform apply`; this module builds the web and API images during apply, but
does not invoke Ansible.

## Images and Artifact Registry

The node service account already has `roles/artifactregistry.reader` on the
`cloudshirt-images` repository. `terraform apply` builds and pushes the web and
API images with `scripts/build-and-push.sh`, through the
`terraform_data.build_cloudshirt_images` resource. The script clones
`cloudshirt_repo_url`, checks out `main`, builds both Dockerfiles for
`linux/amd64`, and pushes the commit tag and `latest`. It needs `bash`, `git`,
Docker with buildx and Google Cloud credentials on the machine that runs
Terraform. The build configures Docker with the active `gcloud` account, or
with the Application Default Credentials when no account is active, so the
`gcloud auth application-default login` from the first-run section is enough.

The resource runs on the first apply and again when the project, region or
`cloudshirt_repo_url` changes. To rebuild from a newer `main` without changing
the infrastructure:

```bash
terraform apply -replace=terraform_data.build_cloudshirt_images
```

To run the same build outside Terraform, from the repository root:

```bash
GCP_PROJECT=cloud-orchestration-512823 GCP_REGION=europe-west4 \
AR_REPO=cloudshirt-images REPO_URL=https://github.com/athype/CloudShirt \
REPO_REF=main bash scripts/build-and-push.sh
```

Private nodes have no general internet egress and no Cloud NAT. They can pull
from Google-hosted registries through Private Google Access, but an image from
Docker Hub, MCR (`mcr.microsoft.com`) or another registry must be mirrored into
Artifact Registry first. The build script does not mirror the SQL Server image
used by the Kubernetes deployment; push it once with:

```bash
gcloud auth configure-docker europe-west4-docker.pkg.dev

docker pull mcr.microsoft.com/mssql/server:2022-latest
docker tag mcr.microsoft.com/mssql/server:2022-latest \
  europe-west4-docker.pkg.dev/cloud-orchestration-512823/cloudshirt-images/sqlserver:2022-latest
docker push \
  europe-west4-docker.pkg.dev/cloud-orchestration-512823/cloudshirt-images/sqlserver:2022-latest
```

If a non-Google registry is needed directly, add Cloud NAT to the VPC instead.

## Security notes

- Worker nodes are private; the control plane has a public endpoint restricted
  by `admin_cidr_blocks`, and client certificates are disabled.
- The `0.0.0.0/0` value in the example and local `terraform.tfvars` is a lab
  trade-off, not a production setting.
- The node identity is a dedicated service account with a repository-scoped
  Artifact Registry read role rather than the default compute account.
- The cluster uses Workload Identity; Kubernetes service accounts can be bound
  to Google service accounts in the deployment issue.
- Database credentials, Kubernetes Secrets and application configuration are
  not managed by this module; they belong to the Kubernetes deployment and
  Ansible issues.

## State and cleanup

Terraform state is local at `terraform/gcp/terraform.tfstate` and ignored by
Git. Back it up after an apply if the cluster is still needed:

```powershell
terraform state pull > "$env:USERPROFILE\cloudshirt-gcp-state-backup.json"
```

Use a GCS backend instead if more than one operator applies to the project.

Destroy the GCP resources from this directory:

```bash
terraform destroy
```

To release the LoadBalancer and the SQL disk before the cluster disappears,
run `bash scripts/teardown-gcp.sh` from the repository root instead; it deletes
the `cloudshirt` namespace and then runs `terraform destroy`.

The cluster and node pool are deleted first. The Artifact Registry repository
and its images are deleted as well, so capture evidence before destroying. The
storage bucket has `force_destroy = false`; empty it first if destroy fails.
Check for orphaned persistent disks and forwarding rules left by the
Kubernetes deployment:

```bash
gcloud compute disks list --project cloud-orchestration-512823 --filter="name~cloudshirt"
gcloud compute addresses list --project cloud-orchestration-512823
```

The AWS module and this module have separate state and separate lifecycles. Do
not run `terraform destroy` in `terraform/aws` when the intention is to remove
only the GCP resources.
