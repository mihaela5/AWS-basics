# Ansible

The playbooks configure the CloudShirt GKE cluster and deploy the manifests in
[`kubernetes/`](../kubernetes). Terraform owns the network, the cluster, the
node pool and the Artifact Registry repository; Ansible owns the cluster access
and the Kubernetes objects that run the application.

The worker nodes are managed by GKE: it creates them from the node pool, patches
them with auto-upgrade and auto-repair, and joins them to the cluster. The node
prerequisites that Ansible would install on a self-managed cluster (container
runtime, kubelet, kube-proxy) are therefore provided by GKE, and the playbooks
verify the node pool instead of reconfiguring it.

## Layout

| Path | Purpose |
| --- | --- |
| `ansible.cfg` | Inventory and role paths, retry files disabled |
| `inventory/hosts.yml` | The local control host in the `gke` group |
| `inventory/group_vars/all.yml` | Cluster, namespace and image settings |
| `playbooks/site.yml` | Full run: prerequisites, access, deployment and verification |
| `playbooks/verify.yml` | Read-only check of an existing deployment |
| `playbooks/logs.yml` | Collect the application logs of the running deployment |
| `roles/prerequisites` | gcloud tooling, authentication, project, Python client and collection |
| `roles/gke_access` | Kubeconfig, API readiness and node readiness |
| `roles/cloudshirt` | Namespace, configuration, secret, SQL Server, API and website |
| `roles/verify` | Replica, pod, external IP and HTTP checks |
| `roles/logs` | Pod discovery, container log collection and the run summary |

## Rollout order

Terraform and Ansible are separate stages:

1. `terraform -chdir=terraform/gcp apply` creates the VPC, cluster, node pool,
   Artifact Registry repository and bucket. It also runs
   `scripts/build-and-push.sh` through the
   `terraform_data.build_cloudshirt_images` resource, which builds and pushes the
   web and API images with the commit tag and `latest`. This needs `bash`,
   `git`, Docker with buildx and an authenticated `gcloud` on the machine that
   runs Terraform. The cluster starts with only the GKE system pods; no
   CloudShirt workload exists yet.
2. Mirror the SQL Server image into Artifact Registry; skip this when it is
   already there. The build script does not handle it; the command is in
   `terraform/gcp/README.md`. The private nodes cannot pull from Docker Hub or
   MCR.
3. `ansible-playbook playbooks/site.yml` writes the kubeconfig, applies the
   manifests and waits until the website answers on its external IP.

Terraform does not invoke Ansible. It uses a `local-exec` only for the image
build; the cluster configuration and application deployment remain a separate
Ansible stage. That keeps `terraform apply` focused on infrastructure, writes
the kubeconfig from Ansible rather than Terraform, and lets the application be
redeployed without recreating the cluster. A wrapper script or CI job can call
all three steps in order.

## Prerequisites

- Ansible runs on a Linux or macOS control host. On Windows use WSL (Ubuntu) or
  the Google Cloud Shell; Ansible does not run natively on Windows.
- Python 3.11 or newer. The setup uses `uv` when it is installed; otherwise
  install `python3-venv` and `pip` (on Ubuntu, `sudo apt install python3-venv`).
- The GCP resources in [`terraform/gcp`](../terraform/gcp/README.md) applied:
  the cluster, the node pool and the `cloudshirt-images` repository.
- The web and API images are built and pushed by `terraform apply` through
  `scripts/build-and-push.sh`; if the cluster already exists, ensure those images
  are in Artifact Registry. The SQL Server image is not built by that script;
  mirror it into Artifact Registry first. The nodes are private and have no
  Cloud NAT, so images from Docker Hub or MCR cannot be pulled.
- `gcloud` installed and authenticated with `gcloud auth login`. The project is
  read from `gcp_project_id`, the `GCP_PROJECT_ID` environment variable, or the
  active `gcloud` configuration, in that order.
- Access from the control host to the public GKE control-plane endpoint.
  `admin_cidr_blocks` in `terraform/gcp` must contain the host's address; the
  example file uses `0.0.0.0/0`.

## Setup

With `uv` (recommended; it creates the virtual environment without the
`python3-venv` package):

```bash
cd ansible
uv venv .venv
source .venv/bin/activate
uv pip install -r requirements.txt
ansible-galaxy collection install -r requirements.yml
```

Without `uv`:

```bash
cd ansible
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
ansible-galaxy collection install -r requirements.yml
```

Both paths install `ansible-core` and the Kubernetes Python client in the same
environment. Ansible itself is Python, so this step cannot be skipped; the
`kubernetes.core` collection will not run without the client package.

In WSL, keep the checkout in the Linux filesystem. Ansible ignores
`ansible.cfg` in a world-writable directory such as `/mnt/c`, and then the
inventory and roles are not found. If the checkout has to stay on `/mnt/c`,
run the playbooks with `ANSIBLE_CONFIG="$PWD/ansible.cfg" ansible-playbook ...`.

Ansible uses the `gcloud` on `PATH`. When WSL runs the Windows Cloud SDK, set
`CLOUDSDK_CONFIG` to the Windows configuration so `gcloud` and
`gke-gcloud-auth-plugin` see the account from `gcloud auth login`, for example
`export CLOUDSDK_CONFIG=/mnt/c/Users/<user>/AppData/Roaming/gcloud`.

## Configure and deploy

```bash
export GCP_PROJECT_ID=cloud-orchestration-512823   # optional when gcloud already selects it
export SA_PASSWORD='...'         # required only when cloudshirt-db does not exist
ansible-playbook playbooks/site.yml
```

`SA_PASSWORD` is read from the environment rather than passed with `-e`, so it
does not appear in the `ansible-playbook` command line.

From the repository root, `bash scripts/provision-gcp.sh` runs the Terraform
stage, mirrors the SQL Server image and then this playbook in one step.

The play applies the following in order:

1. `prerequisites` checks gcloud, kubectl and the GKE authentication plugin,
   installs missing gcloud components, requires an active account and a project,
   and installs the Kubernetes Python client if it is missing.
2. `gke_access` writes the kubeconfig with
   `gcloud container clusters get-credentials`, waits for the Kubernetes API,
   waits for at least `gke_min_ready_nodes` nodes, and waits for every node to
   be Ready.
3. `cloudshirt` applies the namespace and ConfigMap, creates the
   `cloudshirt-db` Secret when it is absent, and applies the SQL Server, API and
   website manifests with the Artifact Registry image references substituted.
   It waits for each StatefulSet and Deployment rollout.
4. `verify` checks the replica counts and pod readiness, waits for the external
   IP of the `cloudshirt-web` Service, requests the home page and prints a
   summary.

## Variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `gcp_project_id` | `GCP_PROJECT_ID`, then the gcloud project | Project that hosts the cluster |
| `gcp_region` | `europe-west4` | Artifact Registry and image region |
| `gcp_zone` | `europe-west4-a` | Zone of the zonal GKE cluster |
| `gke_cluster_name` | `cloudshirt-gke` | Cluster name |
| `gke_min_ready_nodes` | `2` | Minimum node count before the deployment starts |
| `cloudshirt_namespace` | `cloudshirt` | Namespace for all application objects |
| `cloudshirt_image_tag` | `latest` (`IMAGE_TAG`) | Tag applied to the web and API images; use the commit tag printed by `build-and-push.sh` for reproducible rollouts |
| `cloudshirt_registry` | `<region>-docker.pkg.dev/<project>/cloudshirt-images` (`ARTIFACT_REGISTRY`) | Registry prefix for all image references |
| `cloudshirt_sa_password` | `SA_PASSWORD` | SQL Server SA password (8+ characters, 3 of upper/lower/digit/symbol) |
| `cloudshirt_rollout_retries`, `cloudshirt_rollout_delay` | `60`, `10` | Rollout polling, 10 minutes in total |
| `verify_lb_retries`, `verify_lb_delay` | `60`, `10` | External IP polling |
| `verify_http` | `true` | Set to `false` when the control host cannot reach the external IP |
| `logs_output_dir` | `<repository>/logs` | Destination for the timestamped log directories |
| `logs_since` | `24h` | Window passed to `kubectl logs --since` |

Override any value with `-e`, for example:

```bash
ansible-playbook playbooks/site.yml -e gcp_zone=europe-west4-b -e cloudshirt_image_tag=abc1234
```

## Repeat runs

- `kubernetes.core.k8s` with `apply: true` compares each live object with the
  manifest, so a second run leaves matching objects unchanged.
- The database secret is created only when `cloudshirt-db` is absent. If it
  exists and `SA_PASSWORD` is set, the play compares it with the stored value
  and fails instead of overwriting the password the SQL volume was initialised
  with.
- The kubeconfig refresh, rollout waits and verification tasks only read the
  cluster and report no changes. Every `logs` run writes a new timestamped
  directory and leaves the cluster untouched.
- The web and API images are built by `terraform apply` through
  `scripts/build-and-push.sh`. To rebuild from the current `main` without other
  changes, run
  `terraform -chdir=terraform/gcp apply -replace=terraform_data.build_cloudshirt_images`.
- The manifests use `imagePullPolicy: IfNotPresent`. A rebuilt `latest` image is
  not pulled on a node that already has that tag; pass the commit tag printed by
  the script (`-e cloudshirt_image_tag=<tag>`) to roll out a new build.

## Verify

Run the checks on their own after a deployment:

```bash
ansible-playbook playbooks/verify.yml
```

The run ends with a summary like:

```text
TASK [verify : Show the deployment summary] ************************************
ok: [control] => {
    "msg": [
        "Web replicas: 5/5",
        "API replicas: 2/2",
        "Pods: 8 running",
        "Website: http://203.0.113.10/"
    ]
}
```

The same values are available with `kubectl`:

## Collect logs

The logs playbook reuses `prerequisites` and `gke_access`, then reads the
output of every container of every pod in the `cloudshirt` namespace:

```bash
ansible-playbook playbooks/logs.yml
```

The run writes a timestamped directory:

```text
logs/20261030T223000Z/
├── cloudshirt-api-6f9c4b8d7-x2vqn_api.log
├── cloudshirt-sql-0_sqlserver.log
├── cloudshirt-web-7d4b6c9f5-9kz4m_web.log
├── ...
└── summary.txt
```

Each line starts with the timestamp recorded by the container runtime, for
example `2026-10-30T22:31:04.123456789Z`. `summary.txt` adds the collection
time, project, zone, cluster, namespace, `--since` window, pods and nodes, and
the result of each `kubectl logs` call. The files are working copies, not
sources, so `logs/` is in `.gitignore`.

## Cleanup

The playbooks do not delete resources. To remove the application objects, run
the delete path of the Bash deployment script:

```bash
bash scripts/deploy-k8s.sh --delete
```

The cluster and registry are removed with `terraform destroy` from
`terraform/gcp`.
