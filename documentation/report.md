# Report 
**Mihaela Stoyanova, Krisztián Kozári**

## Introduction 
The goal of this project is to design and deploy a cloud infrastructure for CloudShirt, a startup company from Germany. The solution uses Amazon Web Services (AWS) and AWS CloudFormation to automate the deployment and configuration of the infrastructure.
The application is based on the CloudShirt ASP.NET Core 8.0 web application. The infrastructure includes a Virtual Private Cloud (VPC), subnets across multiple Availability Zones, security groups, Amazon EC2, an Application Load Balancer (ALB), an Auto Scaling Group, Amazon Elastic File System (EFS), Amazon RDS, Amazon S3, and an Elastic Stack monitoring solution.
The infrastructure is divided into separate CloudFormation templates. A master template, main.yaml, orchestrates the deployment of the individual components. A UserData script automates the installation and configuration of the CloudShirt application on EC2 instances.
The main objectives are to provide high availability, support scheduled scaling, store application logs centrally, provision a relational database using Infrastructure as Code, and provide monitoring and serverless functionality. Assignment 2, Docker in the Cloud, extends the same solution: the application is containerised, built on a dedicated Buildserver, pushed to a private Amazon ECR registry, and deployed on a Docker Swarm cluster formed by the Auto Scaling Group instances. Assignment 3, Cloud Orchestration, adds a second cloud: Terraform provisions an independent environment on Google Cloud, the application runs on a private GKE cluster from Kubernetes manifests, and Ansible configures the cluster, verifies the deployment and collects the application logs.

## Solution overview
CloudShirt is a startup from Germany that wants to run its .NET web shop on AWS. This solution deploys the CloudShirt ASP.NET Core 8 application with one command. A single CloudFormation root stack, CloudShirtInfrastructure, creates ten nested stacks. Customers reach the shop through one Application Load Balancer URL, which spreads traffic over web servers in two Availability Zones. The servers use a private Amazon RDS for SQL Server database, write their logs to Amazon EFS and ship them with Filebeat to an Elastic Stack. A script exports the order table to S3, and a serverless API reads those exports. For Assignment 2 the application is containerised, built nightly on the Buildserver, stored in two private ECR repositories, and run as a Swarm service on the Auto Scaling Group instances.

Assignment 3 moves the application to Kubernetes. `terraform/gcp` creates a dedicated VPC, a private zonal GKE cluster with two workers, an Artifact Registry repository and a Cloud Storage bucket; `terraform/aws` manages the existing CloudFormation stack through Terraform, so both clouds are described as code. The manifests in `kubernetes/` run the website (five replicas), the public API (two replicas) and SQL Server (one stateful pod) in the `cloudshirt` namespace, with the website published through one external IP. Ansible applies the same manifests, verifies the rollout and writes the collected container logs to `logs/`.

![Overall deployment](./diagrams/deployment.png)

The diagram shows the AWS deployment; the Google Cloud deployment is described in the Cloud Orchestration section.

## Learning objectives 

Cloud infrastructure and AWS services: The solution uses AWS services including EC2, VPC, Elastic Load Balancing, EFS, RDS, S3, AWS Lambda, API Gateway, and CloudFormation.

| Learning objective | Where it is covered? | How? |
| --- | --- | --- |
| Networking | `01-networking.yaml` | A VPC with public subnets for the ALB and web servers and private subnets that only hold the database, each pair spread over two AZs, with separate route tables. |
| Security | `02-security.yaml`, `03-storage.yaml` | Security groups are chained: internet to ALB, ALB to web servers, web servers to EFS (2049), RDS (1433) and Elasticsearch (9200). EFS is encrypted, the S3 bucket blocks public access and uses SSE. |
| Compute and scaling | `05-application.yaml` | Launch template with Amazon Linux 2023, Auto Scaling Group with 2 to 4 instances, scheduled scaling actions. |
| Load balancing and high availability | `05-application.yaml` | Internet-facing ALB over two AZs, target group with ELB health checks, instances replaced automatically when unhealthy. |
| Storage | `03-storage.yaml` | EFS for shared application logs, S3 for order exports. |
| Databases | `04-database.yaml` | RDS for SQL Server in a DB subnet group over two private subnets, snapshot on deletion. |
| Monitoring and logging | `06-monitoring.yaml`, `08-cloudwatch.yaml`, `userdata.sh `| Elastic Stack with Filebeat for logs, CloudWatch alarms, SNS topic and dashboard for metrics. |
| Serverless | `07-serverless.yaml` | Lambda and API Gateway reading the S3 exports. |
| Infrastructure as code and automation | main.yaml, provision.sh | Nested stacks, `aws cloudformation package` and `deploy`, one script for create, update and delete. |


## Requirements - AWS Basics
| REQ | Solution | Files |
| --- | --- | --- |
| REQ-01 | The CloudShirt .NET application runs in an EC2 Auto Scaling Group with a minimum of two instances, distributed across two Availability Zones and registered behind an Application Load Balancer. The ALB provides a single URL for accessing the application and distributes traffic between the available instances. | [05-application.yaml](../templates/05-application.yaml) - launch template, ALB, target group and Auto Scaling Group<br>[01-networking.yaml](../templates/01-networking.yaml) - VPC and subnets in two AZs<br>[userdata.sh](../scripts/userdata.sh) - installs and starts the application |
| REQ-02 | The Auto Scaling Group has two scheduled actions: it scales out from 2 to 4 instances at 18:00 Eastern Time and scales back to 2 instances at 20:00 (time zone `America/New_York`). This lets the application handle the expected peak in traffic. | [05-application.yaml](../templates/05-application.yaml) - scheduled scale-out and scale-in actions |
| REQ-03 | EFS is provisioned with CloudFormation, with mount targets in both Availability Zones, and mounted on the web servers at `/mnt/cloudshirt-logs`. Each instance writes its application log to its own directory on the shared file system and logrotate rotates it daily into dated files. The logs are therefore stored centrally and remain available when instances are replaced or scaled. | [03-storage.yaml](../templates/03-storage.yaml) - EFS file system and mount targets<br>[02-security.yaml](../templates/02-security.yaml) - EFS security group (NFS port 2049)<br>[userdata.sh](../scripts/userdata.sh) - mount, log directory and daily log rotation |
| REQ-04 | An Amazon RDS SQL Server database is provisioned with CloudFormation in the private subnets and only accepts connections from the web servers. The application connects through the RDS endpoint. Database credentials and connection information are passed to the instances through CloudFormation parameters. | [04-database.yaml](../templates/04-database.yaml) - RDS instance and subnet group<br>[02-security.yaml](../templates/02-security.yaml) - database security group (port 1433)<br>[05-application.yaml](../templates/05-application.yaml) - passes endpoint and credentials to the user data |
| REQ-05 | The `06-monitoring.yaml` template provisions an Elastic Stack instance with Elasticsearch and Kibana v8.x. Elasticsearch receives the log data, while Kibana provides a web interface (port 5601) for searching and analysing it. | [06-monitoring.yaml](../templates/06-monitoring.yaml) - Elastic Stack instance<br>[02-security.yaml](../templates/02-security.yaml) - monitoring security group<br>[08-cloudwatch.yaml](../templates/08-cloudwatch.yaml) - extra: CloudWatch alarms and dashboard |
| REQ-06 | The UserData script installs Filebeat on each application instance. It collects the instance's own application logs from `/mnt/cloudshirt-logs/<hostname>/app.log*` and the system log `/var/log/messages` and sends them to Elasticsearch. A Filebeat failure does not stop the application setup. | [userdata.sh](../scripts/userdata.sh) - Filebeat installation and configuration<br>[06-monitoring.yaml](../templates/06-monitoring.yaml) - provides the Elasticsearch address |
| REQ-07 | The script `export.sh` exports the Orders table from the RDS database to a CSV file with a UTC timestamp in its name and uploads it to the S3 export bucket (`exports/orders/`) with the AWS CLI. It runs on a web server because the database is private, and it can be run repeatedly. | [export.sh](../scripts/export.sh) - the export script<br>[03-storage.yaml](../templates/03-storage.yaml) - the S3 export bucket |
| REQ-08 | The `07-serverless.yaml` template provisions an AWS Lambda function exposed through an API Gateway REST API. The function summarises the order exports that the REQ-07 script writes to the `exports/orders/` prefix in Amazon S3 and returns them over four read-only routes, so staff can see order totals, buyer counts and, where the export carries prices, unit counts and best-selling products without opening the database. The function is provisioned entirely through CloudFormation and uses an IAM role that can only list and read that prefix. | [07-serverless.yaml](../templates/07-serverless.yaml) - Lambda, API Gateway and IAM role<br>[insights.py](../lambda/order_insights/insights.py) - the Lambda code<br>[main.yaml](../templates/main.yaml) - passes the bucket name and ARN to the stack |

## Learning objectives - Docker in the Cloud (Assignment 2)

All five learning objectives are met.

| Learning objective | Where it is covered? | How? |
| --- | --- | --- |
| 2.1 Dockerize an existing service or application | [CloudShirt](https://github.com/athype/CloudShirt) - `src/Web/Dockerfile`, `src/PublicApi/Dockerfile`, `.dockerignore` | The web application and the public API have multi-stage Dockerfiles: an SDK stage restores and publishes, and an ASP.NET runtime stage contains only the published output. The build context is trimmed by `.dockerignore`, and the connection strings are injected as environment variables. |
| 2.2 Deploy a Docker application on a server in the cloud | [09-buildserver.yaml](../templates/09-buildserver.yaml)<br>[05-application.yaml](../templates/05-application.yaml) | The Buildserver in private subnet 1 builds the images and initialises the swarm; the ASG instances join as workers and run the application service. The ALB serves the application through one URL. |
| 2.3 Deploy a Docker cluster over multiple servers | [09-buildserver.yaml](../templates/09-buildserver.yaml)<br>[05-application.yaml](../templates/05-application.yaml)<br>[02-security.yaml](../templates/02-security.yaml) | The Buildserver is the Swarm manager. Each ASG instance joins as a worker after reading the manager IP and join token from SSM. The security groups open TCP 2377 and TCP/UDP 7946 and UDP 4789 between the nodes, and the service runs two replicas spread over the workers. |
| 2.4 Provision a private Docker registry and push an image | [10-ecr.yaml](../templates/10-ecr.yaml)<br>[scripts/build.sh](../scripts/build.sh) | Two private ECR repositories, `cloudshirt` and `cloudshirt-api`, are provisioned with scan-on-push and a lifecycle policy. The Buildserver authenticates with the ECR credential helper and the nightly build pushes the date and `latest` tags. |
| 2.5 Deploy a dockerized application on the cluster from the private registry | [scripts/deploy.sh](../scripts/deploy.sh)<br>[05-application.yaml](../templates/05-application.yaml) | The `cloudshirt` Swarm service runs the ECR image with two replicas and `--with-registry-auth`, so the workers pull from the private registry without stored credentials. The ALB target group points at the published port 80 on the ASG instances. |

## Requirements - Docker in Cloud

The Docker solution is built from the CloudShirt fork. The Buildserver addition satisfies REQ-09 and REQ-13, the ASG worker configuration satisfies REQ-14, and the ECR stack provisions the private registry used by REQ-12. The remaining requirements are listed with their current status.

| REQ | Solution | Files |
| --- | --- | --- |
| REQ-08 | **Met.** The fork contains a multi-stage `Dockerfile` for the web app (SDK build stage, ASP.NET runtime stage) and a `docker-compose.yml` that defines the web, public API and SQL services. | [CloudShirt](https://github.com/athype/CloudShirt) - `src/Web/Dockerfile`, `src/PublicApi/Dockerfile`, `docker-compose.yml` |
| REQ-09 | **Met.** A separate `CloudShirtBuildserver` EC2 instance runs in private subnet 1 without a public IP. Its UserData installs Docker with the Compose and buildx plugins, git, AWS CLI v2, the ECR credential helper and the SSM agent, and clones the fork. SSH is allowed only from the web servers; normal access is SSM Session Manager. | [09-buildserver.yaml](../templates/09-buildserver.yaml)<br>[01-networking.yaml](../templates/01-networking.yaml) - NAT egress<br>[02-security.yaml](../templates/02-security.yaml) - Buildserver security group<br>[main.yaml](../templates/main.yaml) |
| REQ-10 | **Met.** Compose defines and runs the services, and the deploy-time image references point at the ECR repository populated by the nightly build. | [CloudShirt](https://github.com/athype/CloudShirt) - `docker-compose.yml` |
| REQ-11 | **Met.** The nightly `build.sh` is installed on the Buildserver and scheduled through `/etc/cron.d/nightly-build` (`0 2 * * *` by default). It pulls the fork, runs `docker compose build`, tags the images with the date and `latest`, and logs to `/var/log/nightly-build.log`. | [build.sh](../scripts/build.sh)<br>[09-buildserver.yaml](../templates/09-buildserver.yaml) - cron installation |
| REQ-12 | **Met.** The private repositories `cloudshirt` and `cloudshirt-api` are provisioned with scan-on-push and a lifecycle policy that keeps the last `ImageRetentionCount` images (default 10). The Buildserver is authenticated through the ECR credential helper; the nightly build pushes the date and `latest` tags. | [10-ecr.yaml](../templates/10-ecr.yaml) - repositories, scanning and lifecycle policy<br>[main.yaml](../templates/main.yaml) - ECR stack and outputs |
| REQ-13 | **Met.** The Buildserver runs `docker swarm init` with its private IP and publishes the manager IP (`/cloudshirt/swarm/manager-ip`, String) and the worker join token (`/cloudshirt/swarm/worker-join-token`, SecureString) to SSM Parameter Store. The security groups allow TCP 2377, TCP/UDP 7946 and UDP 4789 between the Buildserver and the web servers. | [09-buildserver.yaml](../templates/09-buildserver.yaml) - swarm init and parameter publishing<br>[02-security.yaml](../templates/02-security.yaml) - Swarm ports<br>[main.yaml](../templates/main.yaml) - Buildserver stack |
| REQ-14 | **Met.** The ASG launch template installs Docker and the AWS CLI. On first boot each web server reads the manager IP and worker token from SSM Parameter Store, retries until the manager is ready, and runs `docker swarm join`. `WebServerInstanceProfile` defaults to `LabInstanceProfile`; when the stack creates the role instead, it gets `AmazonEC2ContainerRegistryReadOnly` and an inline `ssm:GetParameter` policy scoped to the two Swarm parameters. The security groups also allow 7946 and 4789 between the workers themselves, because overlay traffic is peer-to-peer. `docker node ls` on the Buildserver lists the ASG instances as workers, and scaling the group adds and removes nodes. | [05-application.yaml](../templates/05-application.yaml) - launch template, worker role and join<br>[main.yaml](../templates/main.yaml) - Buildserver dependency and parameter forwarding<br>[02-security.yaml](../templates/02-security.yaml) - Swarm ports |

## Application deployment 

`05-application.yaml` creates everything that serves the CloudShirt shop: the load balancer, the web servers and the scaling rules. It covers `REQ-01` (high availability behind one URL) and `REQ-02` (scale out between 18:00 and 20:00 Eastern). The web servers set themselves up with userdata.sh, which also covers the mounting side of `REQ-03` and the Filebeat part of `REQ-06`.

The launch template passes the settings to every new instance as environment variables and downloads `userdata.sh` from GitHub. Before that script runs, the instance installs Docker and joins the Buildserver's Swarm as a worker; the join reads the manager IP and token from SSM Parameter Store and retries, because the manager's UserData finishes after CloudFormation marks the Buildserver stack complete. The EFS mount and Filebeat steps are allowed to fail without stopping the application. The load balancer starts sending traffic as soon as the health check passes.

![User data flow](./diagrams/userdata-flow.png)

### Serverless component

`07-serverless.yaml` is deployed by `main.yaml` as the `ServerlessStack` nested stack. It depends on the storage stack and receives the export bucket name and its ARN from it, so the Lambda reads the same bucket that the REQ-07 export script writes to. The `DeploymentVersion` parameter is declared on the root stack and forwarded to the serverless stack.

The function reads the order exports from Amazon S3 instead of querying Amazon RDS directly. This keeps the component independent of the database: the CloudShirt application seeds data at startup but never applies EF Core migrations, so the schema is created out of band. Reading the exports also means the endpoint still works during the period when the database has no tables.

| Resource | Purpose |
| -------- | ------- |
| `InsightsLogGroup` | CloudWatch log group `/aws/lambda/CloudShirt-OrderInsights`, kept for 14 days. |
| `InsightsRole` | IAM role for the function. It may list the bucket for the `exports/orders/` prefix and read objects under it, and has no other access. |
| `OrderInsightsFunction` | AWS Lambda function `CloudShirt-OrderInsights`. It runs on Python 3.12, has 256 MB of memory and a 30 second timeout, and reads the bucket name from the `ORDER_EXPORT_BUCKET` environment variable. |
| `Api` | API Gateway REST API `CloudShirt-Order-Insights`, regional endpoint. |
| `ApiProxyResource` | The `{proxy+}` resource, so every path reaches the same function. |
| `ApiProxyMethod` | The `ANY` method using a Lambda proxy integration. Routing happens inside the function. |
| `ApiDeployment` | API Gateway deployment. It carries the `DeploymentVersion` value in its description. |
| `ApiStage` | The `prod` stage, throttled to 20 requests per second with a burst of 40, with detailed metrics enabled. |
| `ApiInvokePermission` | Allows API Gateway to invoke the function. |

The function serves four routes: `GET /health` returns the service name and bucket, `GET /exports` lists the CSV files under `exports/orders/` and gives each one an `id`, `GET /exports/{id}` summarises a single export, and `GET /summary` totals every export and returns a per-export series.

The export script names its files `orders_YYYYMMDD_HHMMSS.csv`, so each run produces a new object rather than overwriting the previous one. The function accepts that naming and also the `orders-YYYY-MM-DD.csv` form, and takes the part after `orders_` or `orders-` as the export's `id`.

![Overall deployment](./diagrams/deployment.png)

Because `scripts/export.sh` runs `SELECT *` against the `Orders` table alone, its exports contain no prices or quantities: those columns live in the separate `OrderItems` table. The endpoint therefore reports order and buyer counts as measurements, and returns `null` for units, revenue and best-selling products, naming them in `unavailableMetrics`. This is the intended behaviour rather than a failure, and an export that joins `OrderItems` fills those fields in with no change to the infrastructure.

The order export columns are matched by name rather than by position, and each column accepts the spellings it is likely to arrive as, for example `order_id`, `OrderID` or `Id` for the order number and `qty` or `units` for the quantity. A column that cannot be found is treated as absent, and the metrics that depend on it are returned as `null` and named in `unavailableMetrics`. This means an export of the `Orders` table alone still produces a useful response, even though prices and quantities only exist in the `OrderItems` table.

The stack outputs `ApiEndpoint`, the invoke URL of the API, and `OrderInsightsFunctionName`, the name of the function.

![ExportOrders](./diagrams/order-export.png)


### CloudWatch monitoring

`08-cloudwatch.yaml` is deployed by `main.yaml` as the `CloudwatchStack` nested stack. It depends on the application stack and receives the Auto Scaling Group name, the load balancer full name (`app/<name>/<id>`) and the target group full name (`targetgroup/<name>/<id>`) from it.

| Resource | Purpose |
| -------- | ------- |
| `AlarmTopic` | Amazon SNS topic `CloudShirt-Alarms` that every alarm publishes to. The email subscription is created only when `AlarmEmail` is set, because an empty endpoint is not valid. |
| `CloudShirtHighCpuAlarm` | Alarm `CloudShirt-HighCPU`. Fires when the average `CPUUtilization` of the Auto Scaling Group is above 70% for two consecutive 5-minute periods. |
| `CloudShirtALBUnhealthyHostAlarm` | Alarm `CloudShirt-ALB-Unhealthy-Host`. Fires when the maximum `UnHealthyHostCount` of the target group reaches one, so a single target failing its ALB health checks is reported. |
| `CloudShirtDashboard` | CloudWatch dashboard `CloudShirt-Overview` with widgets for ASG CPU utilisation, ALB request count, ALB target response time, healthy vs. unhealthy targets, and ALB 5XX errors. |

Both alarms set `TreatMissingData` to `notBreaching`, so a period without metric data does not raise a false alarm. The stack outputs `AlarmTopicArn`, the SNS topic that the alarms publish to, and `CloudShirtDashboardOutput`, the name of the dashboard.

## Learning objectives - Cloud Orchestration (Assignment 3)

All three learning objectives are met.

| Learning objective | Where it is covered? | How? |
| --- | --- | --- |
| 3.1 Provision resources with Terraform in a multi-cloud environment | [terraform/aws](../terraform/aws/README.md)<br>[terraform/gcp](../terraform/gcp/README.md) | Two independent Terraform root modules with separate state: `terraform/aws` manages the existing CloudFormation stack, and `terraform/gcp` creates the VPC, private GKE cluster, node pool, Artifact Registry repository and Cloud Storage bucket on Google Cloud. |
| 3.2 Deploy a microservices solution on Kubernetes | [kubernetes](../kubernetes/README.md)<br>[scripts/deploy-k8s.sh](../scripts/deploy-k8s.sh) | The website, public API and SQL Server run as separate Kubernetes workloads in the `cloudshirt` namespace, connected through Services; the website has five replicas behind one external IP. |
| 3.3 Configure a Kubernetes cluster with Ansible | [ansible](../ansible/README.md) | The playbooks prepare the control host, write the kubeconfig with `gcloud container clusters get-credentials`, apply the manifests with the `kubernetes.core` collection, wait for the rollouts and verify the deployment. |

## Requirements - Cloud Orchestration

| REQ | Solution | Files |
| --- | --- | --- |
| REQ-15 | **Met.** `terraform/aws` manages the AWS infrastructure through Terraform. It uploads the CloudFormation child templates and the Lambda package to the staging bucket, rewrites the nested `TemplateURL` and `Code` locations to S3, and creates the root `CloudShirtInfrastructure` stack. The CloudFormation templates remain the implementation, so the AWS resources are unchanged. | [terraform/aws](../terraform/aws/README.md)<br>[terraform/aws/main.tf](../terraform/aws/main.tf)<br>[terraform/aws/artifacts.tf](../terraform/aws/artifacts.tf) |
| REQ-16 | **Met.** The CloudShirt application is deployed to GCP from the manifests in `kubernetes/`, using the Artifact Registry images and the GKE cluster from REQ-19. The same manifests are applied by `scripts/deploy-k8s.sh` and by Ansible. | [kubernetes](../kubernetes/README.md)<br>[scripts/deploy-k8s.sh](../scripts/deploy-k8s.sh) |
| REQ-17 | **Met.** The `cloudshirt-web` Service has type `LoadBalancer`, so GKE creates one external forwarding rule and IP. The five web pods are the only workloads behind it. | [kubernetes/40-web.yaml](../kubernetes/40-web.yaml) |
| REQ-18 | **Met.** `terraform/gcp/artifacts.tf` creates the `cloudshirt-images` Artifact Registry repository. `scripts/build-and-push.sh` builds the web and API images, tags them with the commit and `latest`, and pushes them; the SQL Server image is mirrored into the same repository. | [terraform/gcp/artifacts.tf](../terraform/gcp/artifacts.tf)<br>[scripts/build-and-push.sh](../scripts/build-and-push.sh) |
| REQ-19 | **Met.** `terraform/gcp/cluster.tf` creates the zonal GKE cluster and the two-node node pool, including the private-network configuration, the dedicated node service account and the control-plane authorised networks. No cluster step is manual. | [terraform/gcp/cluster.tf](../terraform/gcp/cluster.tf)<br>[terraform/gcp/iam.tf](../terraform/gcp/iam.tf) |
| REQ-20 | **Met.** The `cloudshirt-web` Deployment has `replicas: 5`. The `verify` role checks that all five replicas are ready and that the pods are running across the node pool. | [kubernetes/40-web.yaml](../kubernetes/40-web.yaml)<br>[ansible/roles/verify/tasks/main.yml](../ansible/roles/verify/tasks/main.yml) |
| REQ-21 | **Met.** `ansible-playbook ansible/playbooks/site.yml` runs the `prerequisites`, `gke_access`, `cloudshirt` and `verify` roles. It checks the tools and project, writes the kubeconfig, applies the namespace, configuration, secret and workloads, waits for each rollout and verifies the result. | [ansible](../ansible/README.md)<br>[ansible/playbooks/site.yml](../ansible/playbooks/site.yml) |
| REQ-22 | **Met.** `ansible-playbook ansible/playbooks/logs.yml` reads every container of every CloudShirt pod with `kubectl logs --timestamps` into a timestamped `logs/` directory and writes a `summary.txt` with the collection context. | [ansible/roles/logs/tasks/main.yml](../ansible/roles/logs/tasks/main.yml)<br>[ansible/playbooks/logs.yml](../ansible/playbooks/logs.yml) |

## GCP and Kubernetes solution

### Infrastructure

`terraform/gcp` is a separate root module with its own state. It creates:

| Resource | Configuration |
| --- | --- |
| VPC and subnet | `cloudshirt-gcp-vpc`, `cloudshirt-gke-subnet` (`10.128.0.0/20`) with Private Google Access and secondary ranges for pods (`10.129.0.0/16`) and services (`10.130.0.0/20`) |
| GKE cluster | Zonal `cloudshirt-gke` in `europe-west4-a`, private nodes, public control-plane endpoint restricted by `admin_cidr_blocks`, Workload Identity and workload logging |
| Node pool | Two `e2-standard-2` workers with auto-repair and auto-upgrade |
| Node identity | Dedicated `cloudshirt-gke-nodes` service account with the default node role and repository-scoped Artifact Registry read access |
| Artifact Registry | `cloudshirt-images` Docker repository in `europe-west4` |
| Cloud Storage | A bucket for the GCP deployment, named `cloudshirt-<project>-gcp` by default |

The `terraform_data.build_cloudshirt_images` resource runs `scripts/build-and-push.sh` during `apply`; it runs again when the project, region or source URL changes. The AWS and GCP modules are independent: `terraform destroy` in one does not touch the other.

### Kubernetes workloads

| Object | Kind | Role |
| --- | --- | --- |
| `cloudshirt` | Namespace | Isolates the application |
| `cloudshirt-config` | ConfigMap | ASP.NET Core environment, service URLs and log level |
| `cloudshirt-db` | Secret | SA password and the two connection strings |
| `cloudshirt-sql` | StatefulSet + Service | SQL Server 2022 with an 8 GiB `ReadWriteOnce` volume |
| `cloudshirt-api` | Deployment + Service | Public API, two internal replicas |
| `cloudshirt-web` | Deployment + Service | Website, five replicas behind a `LoadBalancer` |

The API pods wait for the database, the web pods also wait for the API, and all workloads have startup, readiness and liveness probes. The Deployments spread replicas across nodes with `topologySpreadConstraints`. The website is published on port 80 through the single external IP; the API and database stay on ClusterIP Services.

### Ansible

The playbooks run on the operator machine and use the Kubernetes API; there is no SSH to the private nodes. `gke_access` writes the kubeconfig, waits for the API and for every node to be Ready. `cloudshirt` applies the namespace and ConfigMap, creates the database Secret only when it is absent, and applies the SQL Server, API and web manifests with the Artifact Registry image references substituted. It waits for each StatefulSet and Deployment rollout. `verify` checks the replica counts, pod readiness and the external IP, requests the home page and prints a summary. `logs` reuses `gke_access` and writes the container logs with timestamps; SQL Server also keeps its errorlog file on the persistent volume, and GKE forwards the same output to Cloud Logging.

### Verification

The module was applied to the `pcc-2026` project in `europe-west4` on 30 October 2026 (UTC). The live checks were:

| Check | Result |
| --- | --- |
| VPC and subnet | `cloudshirt-gcp-vpc` and `cloudshirt-gke-subnet` (`10.128.0.0/20`) created, with Private Google Access |
| GKE cluster | `cloudshirt-gke` `RUNNING`, GKE 1.36.4, private nodes, `WORKLOADS` logging |
| Node pool | `cloudshirt-node-pool` `RUNNING`, two `e2-standard-2` nodes, both `Ready` with internal IPs only |
| Node identity | `cloudshirt-gke-nodes@pcc-2026.iam.gserviceaccount.com` |
| Artifact Registry | `cloudshirt-images` Docker repository in `europe-west4` |
| Images | `cloudshirt:45a4af2` and `cloudshirt-api:45a4af2`, both also tagged `latest` |
| Cloud Storage | `krisz-cac` bucket in `europe-west4` |
| Capacity | a temporary five-replica `hello-app` Deployment reached five ready replicas across both nodes, then was deleted |
| Application | `ansible-playbook playbooks/site.yml` deployed the namespace, secret, SQL Server, API and website; web 5/5, API 2/2 and SQL 1/1 ready |
| Website | `cloudshirt-web` received the external IP `34.90.177.12` and returned HTTP 200 |
| Logs | `ansible-playbook playbooks/logs.yml` wrote eight container logs under `logs/20261030T231123Z/` with per-line timestamps and `summary.txt` |

The control-plane endpoint is reachable at `34.178.33.158`; `terraform output` also returns the registry URL and the `gcloud container clusters get-credentials` command. The second apply built and pushed both images with the CloudShirt commit tag (`45a4af2`) and `latest`, and a final `terraform plan` reported no changes, so the module is idempotent. Terraform runs the image build with `bash`; on Windows the default resolves to WSL's `bash.exe`, which does not inherit the Terraform environment, so the module takes a `bash_executable` variable and passes it to the `local-exec` interpreter.

The application rollout and the log collection are the Ansible stage (`playbooks/site.yml` and `playbooks/logs.yml`). The live rollout applied the same manifests and the website answered on its external IP; the first run exposed that `kubernetes.core.k8s_info` takes `label_selectors` rather than `label_selector`, which was corrected in the `verify` and `logs` roles. A second `site.yml` run reported 0 changes, so the roles are idempotent. The logs playbook then collected one file per container with per-line timestamps and a summary. The SQL Server image was mirrored into Artifact Registry before the rollout.

## Justification of choices 
| Choice | Reason | Trade-off |
| --- | --- | --- |
| One root stack with nested stacks | Clear separation by layer, reusable outputs, one create or delete command | Needs packaging; a failed child stack rolls back the whole root stack |
| Web servers in public subnets, database and Buildserver in private subnets | The private subnets have no inbound route; the NAT gateway only provides outbound access for package downloads and ECR | The NAT gateway has an hourly cost; web servers have public IPs and rely on security groups |
| RDS SQL Server Express | The CloudShirt application is built for SQL Server; the Express edition is the cheapest | Single AZ, size limits |
| EFS directory per instance plus logrotate | Shared storage survives instance replacement, and separate directories avoid interleaved logs and duplicate indexing | Only application output goes to EFS |
| Export script runs on EC2 | The database is private, so the script has to run inside the VPC | Needs an instance profile and a running web server |
| `LabInstanceProfile` for instances | AWS Academy does not allow custom instance roles | Broader permissions than a least-privilege role |
| Buildserver IAM | `BuildserverInstanceProfile` defaults to `LabInstanceProfile` because AWS Academy blocks custom IAM roles; `CloudShirtBuildserverRole` adds ECR push/pull, SSM Session Manager and writes to the Swarm parameters when the parameter is empty | Lab deployments use the broader LabRole instead of the least-privilege role |
| Worker IAM | `WebServerInstanceProfile` defaults to `LabInstanceProfile`; when the stack creates `CloudShirtWebServerRole`, it grants only `AmazonEC2ContainerRegistryReadOnly` and `ssm:GetParameter` on the two Swarm parameters | Lab deployments use the broader LabRole instead of the least-privilege role |
| Amazon ECR instead of Docker Hub | Private by default, IAM authentication without stored passwords, scan-on-push and a lifecycle policy | The registry is tied to AWS, and the images are deleted with the stack |
| Nightly build with cron instead of a CI tool | The Buildserver already has Docker, git and ECR access inside the private subnet, so cron needs no external runner, pipeline credentials or extra service | No per-commit build, no test gate and no build history; a failure is visible only in the log |
| Multi-stage Dockerfile | The SDK image is used only for restore and publish; the runtime image ships only the published output, which reduces size and attack surface | A longer first build and a larger build cache on the Buildserver |
| A single Swarm manager | One Buildserver as manager is enough for the assignment and keeps the cost and the number of moving parts down | The manager is a single point of failure; losing it stops scheduling and blocks new workers from joining |
| User data downloaded from GitHub | Instances stay small and the script is versioned; `provision.sh` passes the URL as a parameter | The repository must be readable by the instances; changes must be on `main` |
| Swarm worker bootstrap from SSM | The launch template reads the manager IP and join token from Parameter Store and retries; no token is stored in the template or on disk | Workers need `ssm:GetParameter`, and the instance profile must be able to read the parameters |
| Swarm pool outside the VPC CIDR | `--default-addr-pool 10.100.0.0/16` prevents Docker's default `10.0.0.0/8` pool from overlapping the VPC `10.0.0.0/16` | The pool cannot be changed without recreating the cluster |
| Single-node Elastic Stack with security disabled | Simplest setup for a lab (REQ-05, REQ-06) | Not suitable for production |
| CloudWatch alarms and dashboard as an extra stack | Metrics and alerting for the ALB and ASG next to the log analysis in Elastic | Alarm email is optional and empty by default |
| Terraform wrapper around the CloudFormation stack | Reuses the tested templates and keeps one CloudFormation stack as the unit of deployment | Terraform does not model the individual AWS resources, so drift inside the stack is visible only in CloudFormation |
| Separate AWS and GCP root modules | Independent state and lifecycles; either cloud can be created or destroyed alone | Two applies and no single dependency graph across both clouds |
| Private zonal GKE cluster | Private nodes and an IAM-protected control-plane endpoint; two workers are enough for the workload | The control plane and nodes are in one zone, so there is no regional availability |
| Dedicated node service account | The node identity is limited to logging, monitoring and read access to one repository | One more IAM resource to create and maintain |
| SQL Server as an in-cluster StatefulSet | Uses the same SQL Server image as the Docker assignment and avoids a managed database cost | One replica; backups, patching and failover are the operator's responsibility |
| Artifact Registry with the image build in `apply` | Images are versioned with the infrastructure and pulled privately through Private Google Access | `apply` needs Docker, network and credentials; the SQL Server image is mirrored manually |
| `LoadBalancer` Service for the website | Kubernetes requests one external IP; only the web pods are exposed | One cloud forwarding rule, and the listener is HTTP only |
| Ansible over the Kubernetes API | No SSH to private nodes; the same idempotent `k8s` apply as the Bash script | The control host needs access to the public endpoint and a Python Kubernetes client |
| Container logs through `kubectl` and Cloud Logging | No log agent to deploy; each run produces timestamped files with context | Logs are read on demand, and retention depends on the Cloud Logging configuration |

### Provision flow 
![DeploymentOrder](./diagrams/deployment-order.png)

## Roll-out

The prerequisites, stack order, deployment commands and verification steps are in [rollout.md](./rollout.md).


## Recommendations 
- **Secrets:** the database password has a default in the templates and is passed through user data. Use AWS Secrets Manager or SSM Parameter Store and remove the defaults.
- **Network exposure:** SSH (22) and Kibana (5601) are open to the internet and the web servers still allow direct port 80 access. Restrict them to known IP ranges, use SSM Session Manager instead of SSH, and remove the temporary port 80 rule.
- **HTTPS:** add an ACM certificate and an HTTPS listener (with a Route 53 name) so that customers do not use plain HTTP.
- **Database availability:** enable Multi-AZ and encryption for RDS, and move to a larger edition for production.
- **Monitoring:** enable Elastic security and run more than one node, or use Amazon OpenSearch Service. Add a CloudWatch agent for memory and disk metrics.
- **Log coverage:** only application output goes to EFS. Check that `/var/log/messages` exists on Amazon Linux 2023 or switch that input to the journal.
- **Scaling:** add target tracking on CPU or request count next to the scheduled actions, so that unexpected spikes are handled too.
- **Automation:** run the export on a schedule with EventBridge and SSM, and add a CI pipeline with `cfn-lint` and a deployment test.
- **Cost and cleanup:** add lifecycle rules to the export bucket and clean up retained buckets after redeployments.
- **Swarm high availability:** run three managers across Availability Zones instead of one Buildserver manager, so losing a manager does not stop scheduling or block new workers from joining.
- **Container secrets:** the Swarm service receives the database password as an environment variable. Use Docker secrets or AWS Secrets Manager and reference the secret from the service instead.
- **CI/CD for images:** replace or complement the nightly cron build with a pipeline that builds on every commit, runs the tests and a vulnerability scan, and pushes immutable version tags.
- **Container monitoring:** ship the Swarm service logs to CloudWatch or the Elastic Stack and alarm on failed tasks, restart loops and unhealthy replicas.
- **Managed orchestration:** ECS or EKS removes the self-managed Swarm control plane and adds managed rolling updates, service discovery and tighter integration with the ALB and CloudWatch.
- **Terraform state:** move both root modules to a GCS backend with locking; the current state is local, so a lost workstation loses the mapping between the code and the cloud resources.
- **Image supply:** add Cloud NAT or a mirror job so the private nodes do not depend on manually mirrored images; the SQL Server image is the remaining manual step.
- **Database:** move SQL Server to Cloud SQL, or at least add scheduled backups of the `data-cloudshirt-sql-0` volume, because the StatefulSet is a single replica.
- **Cluster availability:** use a regional cluster and a private control-plane endpoint for production; the current cluster is zonal with a public endpoint.
- **Secrets:** store the SA password and connection strings in Secret Manager and sync them with External Secrets instead of creating the Kubernetes Secret from an environment variable.
- **HTTPS:** add a managed certificate and an Ingress or HTTPS load balancer so the website does not serve plain HTTP.
- **CI/CD:** build the images and run `terraform plan` and `ansible-playbook --check` in a pipeline, and use immutable image tags instead of the `latest` default.
- **Observability:** enable Cloud Monitoring alerts and a log-based error metric; workload logging is on, but nothing alerts on it.
- **Capacity:** add a Cluster Autoscaler and PodDisruptionBudgets before production, and review the two-node pool against the five web, two API and one SQL Server pods.
- **Dependencies:** the image build reports `NU1902` and `NU1903` for `Azure.Identity`, `System.Text.Json` and the Blazor WebAssembly server package; update them in the CloudShirt fork and add a dependency scan to the build.


## Conclusion 

The project defines a modular multi-cloud infrastructure for the CloudShirt application. The AWS tier uses CloudFormation and supports high availability across two Availability Zones and scheduled scaling between 18:00 and 20:00 Eastern Time. It provisions EFS, RDS, an Elastic Stack monitoring environment, a CloudWatch stack with alarms, SNS notifications and a dashboard, and a separate serverless stack. The Google Cloud tier is an independent Terraform module with a private GKE cluster, Artifact Registry and a Cloud Storage bucket.

The solution covers all three assignments. The AWS basics part provides the network, data, monitoring, serverless and application layers, and the Docker part adds the container pipeline: multi-stage images, private ECR repositories, a Buildserver that builds nightly and a Swarm cluster of ASG workers behind the same ALB. The Cloud Orchestration part adds the second cloud: Terraform manages the AWS stack and provisions the GCP environment, Kubernetes runs the website, the API and SQL Server with five web replicas behind one external IP, and Ansible configures the cluster, verifies it and collects the logs. The main remaining risks are operational: a single Swarm manager, a cron-driven build without a test gate, long-lived credentials in user data, local Terraform state, and a single-zone cluster with one SQL Server replica.