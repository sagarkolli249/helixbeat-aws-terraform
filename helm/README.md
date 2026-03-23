# HelixBeat – Helm Charts

Helm charts for all in-cluster services. Each chart wraps an upstream Bitnami/community chart via dependency and provides HelixBeat-specific defaults.

## Structure

```
helm/
├── keycloak/          # Identity & access management (Bitnami Keycloak)
├── observability/     # Prometheus + Grafana + Loki + Promtail
├── alb-controller/    # AWS Load Balancer Controller
└── minio/             # S3-compatible in-cluster object storage (Bitnami MinIO)
```

Each chart has:
- `Chart.yaml` — chart metadata and upstream dependency version
- `values.yaml` — base values shared across all environments
- `values-dev.yaml` — dev overrides (minimal resources, India region)
- `values-staging.yaml` — staging overrides (HA replicas, larger storage)

## Node Scheduling

All charts default to **India region nodes** via `nodeSelector`:

```yaml
nodeSelector:
  region: india   # matches EKS node group label set by Terraform
  role: app       # or role: system for controllers
```

The Terraform EKS module sets `region=india` on India clusters (dev-in, staging-in) and `region=us` on US clusters (dev-us, staging-us). Since India is the primary region for dev and staging, all charts target `region: india` by default.

## Prerequisites

These must exist before installing any chart:

| Prerequisite | Source |
|---|---|
| EKS cluster | Terraform `eks` module |
| ALB Controller IRSA role ARN | Terraform `iam` module output `aws_lb_controller_role_arn` |
| Monitoring IRSA role ARN | Terraform `iam` module output `monitoring_role_arn` |
| EFS CSI Driver IRSA role ARN | Terraform `efs` module output `efs_csi_role_arn` |
| Monitoring S3 bucket | Terraform `iam` module output `monitoring_bucket_name` |
| VPC ID | Terraform output `vpc_id` |
| StorageClass `gp3` | Deploy before charts (see below) |

### Create gp3 StorageClass

```bash
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
EOF
```

## Installation Order

Install in this order (ALB controller must be running before charts that create Ingress resources):

```
1. alb-controller
2. observability
3. keycloak
4. minio
```

---

## ALB Controller

```bash
# Get values from Terraform outputs
CLUSTER_NAME=$(terraform -chdir=terraform/environments/dev-in output -raw cluster_name)
VPC_ID=$(terraform -chdir=terraform/environments/dev-in output -raw vpc_id)
ROLE_ARN=$(terraform -chdir=terraform/environments/dev-in output -raw general_kms_key_arn)
# Use IAM module output for ALB controller role ARN
ALB_ROLE_ARN=<iam_module.aws_lb_controller_role_arn>

cd helm/alb-controller
helm dependency update

helm upgrade --install alb-controller . \
  --namespace kube-system \
  --create-namespace \
  -f values.yaml \
  -f values-dev.yaml \
  --set aws-load-balancer-controller.clusterName=${CLUSTER_NAME} \
  --set aws-load-balancer-controller.vpcId=${VPC_ID} \
  --set aws-load-balancer-controller.region=ap-south-1 \
  --set aws-load-balancer-controller.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=${ALB_ROLE_ARN}
```

---

## Observability (Prometheus + Grafana + Loki)

```bash
MONITORING_BUCKET=<iam_module.monitoring_bucket_name>
MONITORING_ROLE_ARN=<iam_module.monitoring_role_arn>

cd helm/observability
helm dependency update

helm upgrade --install observability . \
  --namespace monitoring \
  --create-namespace \
  -f values.yaml \
  -f values-dev.yaml \
  --set loki.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=${MONITORING_ROLE_ARN} \
  --set loki.loki.storage.s3.bucketNames.chunks=${MONITORING_BUCKET} \
  --set loki.loki.storage.s3.bucketNames.ruler=${MONITORING_BUCKET} \
  --set prometheus.grafana.adminPassword=<secure-password>
```

---

## Keycloak

```bash
cd helm/keycloak
helm dependency update

helm upgrade --install keycloak . \
  --namespace auth \
  --create-namespace \
  -f values.yaml \
  -f values-dev.yaml \
  --set keycloak.auth.adminPassword=<secure-password> \
  --set keycloak.externalDatabase.host=<docdb-endpoint> \
  --set keycloak.externalDatabase.password=<db-password>
```

---

## MinIO

```bash
cd helm/minio
helm dependency update

helm upgrade --install minio . \
  --namespace storage \
  --create-namespace \
  -f values.yaml \
  -f values-dev.yaml \
  --set minio.auth.rootPassword=<secure-password>
```

---

## Updating Chart Versions

To upgrade a dependency, edit the `version` field in `Chart.yaml` and run:

```bash
helm dependency update
helm upgrade --install <release> . -f values.yaml -f values-<env>.yaml
```
