# The Google Cloud resources are split across:
#   network.tf    - VPC, subnet and secondary ranges
#   artifacts.tf  - Cloud Storage bucket and Artifact Registry repository
#   iam.tf        - GKE node service account and Artifact Registry pull permission
#   cluster.tf    - GKE cluster and node pool
#   variables.tf  - input variables
#   outputs.tf    - kubectl, registry and cluster connection details
#
# This file is kept only as a pointer; it defines no resources.
