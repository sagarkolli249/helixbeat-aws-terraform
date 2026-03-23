# HelixBeat — AWS Infrastructure

Production-grade, multi-environment AWS infrastructure managed with Terraform. Supports four live environments across two regions (US/IN) and two stages (dev/staging), orchestrated through a GitHub Actions IaC pipeline with resource-level cost-gated approvals.

**Primary region: India (ap-south-1)** — all workloads default to India node pools. US clusters act as secondary.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Network Topology](#network-topology)
3. [Architecture Diagrams](#architecture-diagrams)
4. [Node Pool Strategy](#node-pool-strategy)
5. [Resource Mapping](#resource-mapping)
6. [Module Reference](#module-reference)
7. [Environment Configurations](#environment-configurations)
8. [Helm Charts](#helm-charts)
9. [CI/CD Pipeline](#cicd-pipeline)
10. [Security Posture](#security-posture)
11. [Backup & Disaster Recovery](#backup--disaster-recovery)
12. [Cost Management](#cost-management)
13. [Operations](#operations)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         HELIXBEAT AWS ENVIRONMENTS                          │
│                                                                             │
│  PRIMARY (India)                    SECONDARY (US)                          │
│  ─────────────────────────────      ───────────────────────────────         │
│  dev-in     ap-south-1  2 AZs       dev-us     us-east-1  2 AZs            │
│  staging-in ap-south-1  2 AZs       staging-us us-east-1  2 AZs            │
│                                                                             │
│  All helm workloads target India nodes by default (nodeSelector region=india)│
└─────────────────────────────────────────────────────────────────────────────┘

              github.com/sagarkolli249/helixbeat-aws-terraform
                              │
                              │  git push / workflow_dispatch
                              ▼
                    ┌─────────────────┐
                    │  GitHub Actions  │
                    │  IaC Pipeline   │
                    │  plan → cost    │
                    │  gate → apply   │
                    └────────┬────────┘
                             │ terraform apply (per env, parallel)
                    ┌────────▼────────┐
                    │  Remote State   │
                    │  S3 + DynamoDB  │
                    │  (per env)      │
                    └────────┬────────┘
                             │
          ┌──────────────────┼──────────────────┐
          ▼                  ▼                  ▼
      dev-in             dev-us           staging-in/us
      VPC Stack          VPC Stack        VPC Stack
      (primary)          (secondary)      (primary/secondary)
```

---

## Network Topology

### VPC Layout

Each environment has an isolated VPC. AZ count is intentionally reduced from 3 to 2 — sufficient for AWS service requirements (ALB, DocumentDB) while cutting cost.

| Environment | Region      | VPC CIDR      | AZs | NAT Gateways         |
|-------------|-------------|---------------|-----|----------------------|
| dev-us      | us-east-1   | 10.10.0.0/16  | 2   | 1 shared (cost save) |
| dev-in      | ap-south-1  | 10.20.0.0/16  | 2   | 1 shared (cost save) |
| staging-us  | us-east-1   | 10.30.0.0/16  | 2   | 2 (one per AZ, HA)   |
| staging-in  | ap-south-1  | 10.40.0.0/16  | 2   | 2 (one per AZ, HA)   |

> **Cost note:** A single shared NAT Gateway in dev saves ~$65/month per environment vs. one NAT GW per AZ. The `single_nat_gateway = true` flag in dev environments controls this.

### Subnet Structure (2 Availability Zones)

```
VPC  10.x0.0.0/16
│
├── AZ-a
│   ├── Public Subnet   10.x0.0.0/24    ← ALB, NAT Gateway
│   └── Private Subnet  10.x0.2.0/24    ← EKS Nodes, EC2 ASG, DocumentDB, EFS
│
└── AZ-b
    ├── Public Subnet   10.x0.1.0/24
    └── Private Subnet  10.x0.3.0/24
```

### NAT Gateway Topology

```
DEV (single_nat_gateway = true)         STAGING (single_nat_gateway = false)
─────────────────────────────────       ─────────────────────────────────────
Public AZ-a  ┌──────────┐              Public AZ-a  ┌──────────┐
             │  NAT-GW  │                           │ NAT-GW-a │
             └────┬─────┘                           └────┬─────┘
                  │ shared by                            │ AZ-a private only
  Private AZ-a ◄──┤                   Private AZ-a ◄────┘
  Private AZ-b ◄──┘                   Public AZ-b  ┌──────────┐
                                                    │ NAT-GW-b │
                                                    └────┬─────┘
                                       Private AZ-b ◄────┘
```

### Routing

| Subnet Type | Destination     | Target                              |
|-------------|-----------------|-------------------------------------|
| Public      | 0.0.0.0/0       | Internet Gateway                    |
| Public      | VPC CIDR        | local                               |
| Private     | 0.0.0.0/0       | NAT-GW-0 (dev) / NAT-GW-{AZ} (staging) |
| Private     | VPC CIDR        | local                               |
| Private     | S3, ECR, SSM…   | VPC Endpoints (no NAT traversal)    |

### VPC Endpoints (Private Connectivity)

| Type      | Service               | Purpose                             |
|-----------|-----------------------|-------------------------------------|
| Gateway   | S3                    | ECR image layers, artifact storage  |
| Interface | ecr.api               | ECR API calls                       |
| Interface | ecr.dkr               | Docker registry pulls               |
| Interface | ec2                   | EC2 metadata / API                  |
| Interface | sts                   | IAM role assumption (IRSA)          |
| Interface | logs                  | CloudWatch Logs from private nodes  |
| Interface | ssm                   | Systems Manager                     |
| Interface | ssmmessages           | SSM Session Manager shell           |
| Interface | ec2messages           | SSM run commands                    |
| Interface | elasticloadbalancing  | ALB API                             |
| Interface | autoscaling           | ASG scale-in/out events             |

---

## Architecture Diagrams

### Full Stack — Single Environment (India / dev-in shown)

```
  INTERNET
     │
     │ HTTPS :443 / HTTP :80
     ▼
┌──────────────────────────────────────────────────────────────────────┐
│  PUBLIC SUBNETS  (AZ-a, AZ-b)                                        │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │              Application Load Balancer (ALB)                  │    │
│  │   SG: 0.0.0.0/0 → :80,:443        WAF WebACL attached        │    │
│  │   Listener :80  → 301 redirect to HTTPS                      │    │
│  │   Listener :443 → Target Group (IP mode, /health check)      │    │
│  │   TLS: ACM wildcard *.helixbeat.com  (TLS 1.2 minimum)       │    │
│  └──────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  Dev:  ┌──────────────┐                                              │
│        │  NAT-GW (×1) │  ← shared by all private subnets            │
│        └──────┬───────┘                                              │
│  Staging:     │              ┌──────────────┐  ┌──────────────┐      │
│               │              │ NAT-GW (AZ-a)│  │ NAT-GW (AZ-b)│      │
│               │              └──────┬───────┘  └──────┬───────┘      │
└──────────────────────────────────────────────────────────────────────┘
               │ (outbound via NAT)
               ▼
┌──────────────────────────────────────────────────────────────────────┐
│  PRIVATE SUBNETS  (AZ-a, AZ-b)                                       │
│                                                                      │
│  ┌──────────────────────────────┐  ┌──────────────────────────────┐  │
│  │        EKS Cluster           │  │   EC2 Auto Scaling Group     │  │
│  │  ┌──────────────────────┐    │  │  IMDSv2 · gp3 enc · no pubIP │  │
│  │  │   Control Plane      │    │  │  SSM-only (no SSH)           │  │
│  │  │   Private API only   │    │  │  Rolling refresh, 75% min HA │  │
│  │  │   K8s secrets → KMS  │    │  └──────────────────────────────┘  │
│  │  └──────────────────────┘    │                                    │
│  │  ┌──────────────────────┐    │  ┌──────────────────────────────┐  │
│  │  │  System Node Pool    │    │  │   DocumentDB Cluster (5.0)   │  │
│  │  │  m5.large × 2        │    │  │   Primary    (AZ-a)          │  │
│  │  │  label: region=india │    │  │   Replica    (AZ-b)          │  │
│  │  │  taint: system       │    │  │   Port 27017 · KMS encrypted  │  │
│  │  └──────────────────────┘    │  │   Backup: 35 days            │  │
│  │  ┌──────────────────────┐    │  └──────────────────────────────┘  │
│  │  │  App Node Pool       │    │                                    │
│  │  │  m5.large/xlarge × 2 │    │  ┌──────────────────────────────┐  │
│  │  │  label: region=india │◄───┼──│  Helm Workloads              │  │
│  │  │  HPA: 1–10 nodes     │    │  │  nodeSelector: region=india  │  │
│  │  └──────────────────────┘    │  │  Keycloak · MinIO            │  │
│  └──────────────────────────────┘  │  Prometheus · Grafana · Loki │  │
│                                    └──────────────────────────────┘  │
│  ┌──────────────────────────────┐  ┌──────────────────────────────┐  │
│  │     EFS Filesystem           │  │   VPC Endpoints (~10 total)  │  │
│  │  Mount Targets × 2 AZ        │  │   SSM · ECR · S3 · CW Logs   │  │
│  │  Access Points: /kafka /app  │  │   STS · EC2 · ELB · ASG      │  │
│  │  TLS enforced · KMS enc      │  └──────────────────────────────┘  │
│  └──────────────────────────────┘                                    │
└──────────────────────────────────────────────────────────────────────┘
     │
     ▼
  Route53
  Public:  in.helixbeat.com → ALB alias
  Private: internal.helixbeat.com → DocumentDB CNAME
```

---

### Security Control Plane

```
┌──────────────────────────────────────────────────────────────────────┐
│                         SECURITY PLANE                               │
│                                                                      │
│  ┌────────────────┐  ┌──────────────────┐  ┌──────────────────────┐ │
│  │   GuardDuty    │  │   SecurityHub    │  │     AWS Config       │ │
│  │  S3 data logs  │  │  CIS v1.4.0      │  │  All resource types  │ │
│  │  K8s audit     │  │  FSBP v1.0       │  │  6 managed rules     │ │
│  │  Malware scan  │  │  (region-cond.)  │  │  Continuous record   │ │
│  └────────────────┘  └──────────────────┘  └──────────────────────┘ │
│                                                                      │
│  ┌────────────────┐  ┌──────────────────┐  ┌──────────────────────┐ │
│  │  CloudTrail    │  │   WAFv2 WebACL   │  │      KMS CMK         │ │
│  │  Multi-region  │  │  CRS + KBI + SQLi│  │  Key rotation: ON    │ │
│  │  Mgmt + Data   │  │  Rate: 2000/5min │  │  30-day delete win   │ │
│  │  KMS enc → S3  │  │  Per-IP          │  │  Grants: CW, CT, EKS │ │
│  └────────────────┘  └──────────────────┘  └──────────────────────┘ │
│                                                                      │
│  ┌────────────────┐  ┌──────────────────┐                           │
│  │  Inspector v2  │  │  SSM Patch Mgr   │                           │
│  │  EC2 scanning  │  │  Sunday 2AM UTC  │                           │
│  │  ECR scanning  │  │  7-day approval  │                           │
│  └────────────────┘  └──────────────────┘                           │
│                                                                      │
│  SNS Alerts: GuardDuty high-sev · WAF >100 blocks · Backup failures  │
│              ALB 5xx · ALB p99 >2s · DocDB CPU >80% · Storage <5GB  │
└──────────────────────────────────────────────────────────────────────┘
```

---

### Backup Architecture

```
  Resources tagged  BackupPolicy = helixbeat-daily
  ┌─────────────────────────────────────────────────────────────┐
  │  EKS EBS PVCs  │  EC2 Volumes  │  DocumentDB (tag-based)    │
  └────────────────────────┬────────────────────────────────────┘
                           │
          ┌────────────────┼──────────────────────┐
          ▼                ▼                      ▼
    Daily 3AM UTC   Weekly Sun 4AM      Monthly 1st 5AM UTC
    Retain: 35d     Retain: 90d         Cold: 1d → Retain: 365d

  EFS Filesystem ──→ Explicit ARN selection ──→ Daily plan

            ▼  all rules target  ▼
  ┌─────────────────────────────────────┐
  │   AWS Backup Vault (KMS encrypted)  │
  │   Vault Lock — Compliance mode      │
  │   Min: 35d · Max: 7yr · Change: 3d  │
  └─────────────────────────────────────┘
            │ on failure
            ▼
       SNS → email / Teams
```

---

### CI/CD Pipeline Flow

```
  Developer  →  git push to main  (terraform/** changed)
                        │
                        ▼
  ┌───────────────────────────────────────────────────────────┐
  │                 GitHub Actions Pipeline                    │
  │                                                           │
  │  changed-envs  ──→  matrix [dev-us, dev-in, ...]         │
  │                                                           │
  │  ┌─────────────────────────────────────────────────────┐  │
  │  │  plan job (parallel per env)                         │  │
  │  │  fmt · validate · init · plan -out=tfplan            │  │
  │  │  terraform show -json tfplan  →  tfplan.json         │  │
  │  │  infracost breakdown --path tfplan.json              │  │
  │  │    → per-resource cost table in step summary         │  │
  │  │  tfsec + checkov  →  SARIF → GitHub Security tab     │  │
  │  │  upload: tfplan + infracost.json → S3                │  │
  │  └──────────────────────────┬──────────────────────────┘  │
  │                             ▼                             │
  │  ┌─────────────────────────────────────────────────────┐  │
  │  │  cost-gate job                                       │  │
  │  │  aggregate all infracost.json artifacts              │  │
  │  │  per-resource breakdown table per environment        │  │
  │  │  post commit comment  +  stamp deployment status     │  │
  │  └──────────────────────────┬──────────────────────────┘  │
  │                             ▼                             │
  │                  ┌─────────────────────┐                  │
  │                  │   MANUAL APPROVAL   │  sees cost/env   │
  │                  │  GitHub Environment │  in popup        │
  │                  └──────────┬──────────┘                  │
  │                             ▼                             │
  │  ┌─────────────────────────────────────────────────────┐  │
  │  │  apply job                                           │  │
  │  │  download tfplan from S3  →  terraform apply        │  │
  │  │  post-apply resource cost summary in step summary    │  │
  │  │  Teams notification (success / failure)             │  │
  │  └─────────────────────────────────────────────────────┘  │
  └───────────────────────────────────────────────────────────┘

  Manual destroy:  workflow_dispatch (action=destroy, env=X)
                   → MANUAL APPROVAL → terraform destroy
```

---

## Node Pool Strategy

### Region Labels

The Terraform EKS module stamps every node group with a `region` label derived from the cluster's AWS region:

| Cluster | AWS Region  | Node Label      | Role     |
|---------|-------------|-----------------|----------|
| dev-in  | ap-south-1  | `region=india`  | Primary  |
| staging-in | ap-south-1 | `region=india` | Primary  |
| dev-us  | us-east-1   | `region=us`     | Secondary |
| staging-us | us-east-1 | `region=us`    | Secondary |

### Node Groups per Cluster

Each EKS cluster has two managed node groups:

| Node Group | Label                   | Taint              | Purpose                         |
|------------|-------------------------|--------------------|---------------------------------|
| system     | `role=system region=X`  | `dedicated=system:NoSchedule` | CoreDNS, ALB controller, monitoring controllers |
| app        | `role=app region=X`     | —                  | Application workloads           |

### Workload Scheduling (India as Default)

All Helm charts use `nodeSelector: {region: india}` by default. Workloads land on India nodes unless explicitly overridden:

```yaml
# Default (all helm charts) — targets India nodes
nodeSelector:
  region: india
  role: app

# Override for US-only workloads
nodeSelector:
  region: us
  role: app
```

System components (ALB controller, Prometheus operators) additionally tolerate the `dedicated=system:NoSchedule` taint:

```yaml
nodeSelector:
  region: india
  role: system
tolerations:
  - key: dedicated
    value: system
    effect: NoSchedule
```

---

## Resource Mapping

### Complete Resource Inventory (per environment)

#### Networking — VPC Module

| Resource | Name Pattern | Count (dev) | Count (staging) | Notes |
|----------|-------------|-------------|-----------------|-------|
| `aws_vpc` | `helixbeat-{env}` | 1 | 1 | DNS enabled |
| `aws_internet_gateway` | `helixbeat-{env}-igw` | 1 | 1 | |
| `aws_subnet` (public) | `helixbeat-{env}-public-{az}` | 2 | 2 | One per AZ |
| `aws_subnet` (private) | `helixbeat-{env}-private-{az}` | 2 | 2 | One per AZ |
| `aws_eip` | `helixbeat-{env}-nat-eip-{n}` | **1** | **2** | Shared in dev |
| `aws_nat_gateway` | `helixbeat-{env}-nat-{az}` | **1** | **2** | Shared in dev |
| `aws_route_table` (public) | `helixbeat-{env}-rt-public` | 1 | 1 | → IGW |
| `aws_route_table` (private) | `helixbeat-{env}-rt-private-{n}` | **1** | **2** | Shared in dev |
| `aws_route_table_association` | — | 4 | 4 | 2 public + 2 private |
| `aws_vpc_endpoint` (gateway) | `helixbeat-{env}-vpce-s3` | 1 | 1 | S3 gateway |
| `aws_vpc_endpoint` (interface) | `helixbeat-{env}-vpce-{svc}` | ~10 | ~10 | ECR, SSM, etc. |
| `aws_security_group` (endpoints) | `helixbeat-{env}-vpce-sg` | 1 | 1 | HTTPS from VPC |
| `aws_flow_log` | `helixbeat-{env}-flow-log` | 1 | 1 | ALL traffic → CWL |
| `aws_cloudwatch_log_group` | `/helixbeat/{env}/vpc-flow-logs` | 1 | 1 | 90-day retention |
| `aws_iam_role` | `helixbeat-{env}-vpc-flow-logs-role` | 1 | 1 | |
| `aws_default_security_group` | — | 1 | 1 | Deny-all baseline |

**Subtotal: ~22 resources (dev) / ~23 resources (staging)**

---

#### Security & Compliance — Security Module

| Resource | Name Pattern | Count | Notes |
|----------|-------------|-------|-------|
| `aws_s3_account_public_access_block` | — | 1 | Account-wide |
| `aws_kms_key` | `helixbeat-{env}-general-kms` | 1 | CMK, rotation ON |
| `aws_kms_alias` | `alias/helixbeat-{env}-general` | 1 | |
| `aws_s3_bucket` (cloudtrail) | `helixbeat-{env}-cloudtrail-{acct}` | 1 | Versioned, 7-year lifecycle |
| `aws_s3_bucket` (config) | `helixbeat-{env}-config-{acct}` | 1 | KMS encrypted |
| `aws_cloudtrail` | `helixbeat-{env}-trail` | 1 | Multi-region, mgmt + data events |
| `aws_cloudwatch_log_group` | `/helixbeat/{env}/cloudtrail` | 1 | 365-day, KMS |
| `aws_iam_role` × 2 | cloudtrail-cw-role, config-role | 2 | |
| `aws_guardduty_detector` | — | 1 | S3, K8s audit, malware |
| `aws_securityhub_account` | — | 1 | |
| `aws_securityhub_standards_subscription` | CIS v1.4.0 + FSBP | 2 | Conditional per region |
| `aws_config_configuration_recorder` | `helixbeat-{env}` | 1 | All resource types |
| `aws_config_delivery_channel` | `helixbeat-{env}` | 1 | → S3 bucket |
| `aws_config_config_rule` | × 6 rules | 6 | S3 public, encrypted vols, trail, root keys, MFA, EKS enc |
| `aws_wafv2_web_acl` | `helixbeat-{env}-waf` | 1 | CRS + KBI + SQLi + rate 2000/5min |
| `aws_cloudwatch_metric_alarm` × 2 | guardduty, waf | 2 | |
| `aws_sns_topic` | `helixbeat-{env}-security-alerts` | 1 | KMS |

**Subtotal: ~27 resources**

---

#### Container Platform — EKS Module

| Resource | Name Pattern | Count | Notes |
|----------|-------------|-------|-------|
| `aws_kms_key` | `{cluster}-eks-kms` | 1 | K8s Secrets encryption |
| `aws_kms_alias` | `alias/{cluster}-eks` | 1 | |
| `aws_iam_role` (cluster) | `{cluster}-cluster-role` | 1 | |
| `aws_iam_role_policy_attachment` × 2 | EKSClusterPolicy, VPCResourceController | 2 | |
| `aws_security_group` (cluster) | `{cluster}-cluster-sg` | 1 | Control plane |
| `aws_security_group` (nodes) | `{cluster}-nodes-sg` | 1 | Worker nodes |
| `aws_eks_cluster` | `{cluster}` | 1 | Private API, encrypted secrets |
| `aws_iam_openid_connect_provider` | — | 1 | IRSA |
| `aws_iam_role` (nodes) | `{cluster}-node-role` | 1 | |
| `aws_iam_role_policy_attachment` × 4 | WorkerNode, CNI, ECR, SSM | 4 | |
| `aws_eks_node_group` (system) | `{cluster}-system` | 1 | **label: role=system, region={india\|us}** |
| `aws_eks_node_group` (app) | `{cluster}-app` | 1 | **label: role=app, region={india\|us}** |
| `aws_cloudwatch_log_group` | `/aws/eks/{cluster}/cluster` | 1 | 90-day |
| `aws_ecr_repository` × 3 | api, worker, frontend | 3 | Immutable, scan-on-push, KMS |
| `aws_ecr_lifecycle_policy` × 3 | — | 3 | Keep last 20 images |

**Subtotal: ~23 resources**

---

#### Load Balancing — ALB Module

| Resource | Name Pattern | Count | Notes |
|----------|-------------|-------|-------|
| `aws_security_group` | `helixbeat-{env}-alb-sg` | 1 | 0.0.0.0/0 → :80,:443 |
| `aws_lb` | `helixbeat-{env}-alb` | 1 | Internet-facing, HTTP/2 |
| `aws_lb_target_group` | `helixbeat-{env}-default-tg` | 1 | IP mode, /health |
| `aws_lb_listener` HTTP :80 | — | 1 | 301 → HTTPS |
| `aws_lb_listener` HTTPS :443 | — | 1 | ACM cert, TLS 1.2+ |
| `aws_wafv2_web_acl_association` | — | 1 | ALB ↔ WAF |
| `aws_s3_bucket` (access-logs) | `helixbeat-{env}-alb-logs-{acct}` | 1 | |
| `aws_cloudwatch_metric_alarm` × 2 | 5xx, response-time | 2 | |

**Subtotal: ~9 resources**

---

#### Database — DocumentDB Module

| Resource | Name Pattern | Count | Notes |
|----------|-------------|-------|-------|
| `aws_secretsmanager_secret` | `helixbeat/{env}/docdb/master` | 1 | KMS |
| `aws_docdb_subnet_group` | `helixbeat-{env}-docdb-sng` | 1 | 2 private subnets |
| `aws_security_group` | `helixbeat-{env}-docdb-sg` | 1 | :27017 from app tier |
| `aws_docdb_cluster_parameter_group` | `helixbeat-{env}-docdb-pg` | 1 | TLS on, audit logs |
| `aws_docdb_cluster` | `helixbeat-{env}-docdb` | 1 | Engine 5.0.0, KMS, 35d backup |
| `aws_docdb_cluster_instance` | `helixbeat-{env}-docdb-{n}` | **2** | AZ-a writer, AZ-b reader |
| `aws_cloudwatch_metric_alarm` × 3 | cpu, storage, connections | 3 | |

**Subtotal: ~10 resources**

---

#### Shared Filesystem — EFS Module

| Resource | Name Pattern | Count | Notes |
|----------|-------------|-------|-------|
| `aws_security_group` | `helixbeat-{env}-efs-sg` | 1 | NFS :2049 from EKS nodes |
| `aws_efs_file_system` | — | 1 | KMS, elastic throughput, IA@30d |
| `aws_efs_mount_target` | — | **2** | One per AZ (down from 3) |
| `aws_efs_access_point` (kafka) | — | 1 | uid/gid 1000, /kafka |
| `aws_efs_access_point` (app) | — | 1 | uid/gid 1000, /app |
| `aws_iam_role` | `helixbeat-{env}-efs-csi-role` | 1 | IRSA for EFS CSI driver |
| `aws_iam_role_policy_attachment` | AmazonEFSCSIDriverPolicy | 1 | |
| `aws_efs_file_system_policy` | — | 1 | Deny non-TLS mounts |

**Subtotal: ~8 resources**

---

#### EC2 App Tier — EC2 Module

| Resource | Name Pattern | Count | Notes |
|----------|-------------|-------|-------|
| `aws_iam_role` | `helixbeat-{env}-ec2-role` | 1 | SSM + CW + Inspector + Secrets |
| `aws_iam_role_policy_attachment` × 4 | SSM, CW, Inspector, ECR | 4 | |
| `aws_iam_role_policy` | read-secrets | 1 | Secrets Manager + KMS |
| `aws_iam_instance_profile` | `helixbeat-{env}-ec2-profile` | 1 | |
| `aws_security_group` | `helixbeat-{env}-ec2-sg` | 1 | :8080/:8443 from ALB |
| `aws_launch_template` | `helixbeat-{env}-lt` | 1 | IMDSv2, gp3 enc, no public IP |
| `aws_autoscaling_group` | `helixbeat-{env}-asg` | 1 | Rolling refresh, 75% min HA |
| `aws_inspector2_enabler` | — | 1 | EC2 + ECR scanning |
| `aws_ssm_patch_baseline` | `helixbeat-{env}-al2-baseline` | 1 | 7-day approval |
| `aws_ssm_maintenance_window` | `helixbeat-{env}-patch-window` | 1 | Sundays 02:00 UTC |
| `aws_ssm_maintenance_window_target` | all-instances | 1 | |

**Subtotal: ~13 resources**

---

#### Object Storage — S3 Module

| Resource | Name Pattern | Count | Notes |
|----------|-------------|-------|-------|
| `aws_s3_bucket` × 3 | app-data, backups, artifacts | 3 | KMS SSE |
| `aws_s3_bucket_public_access_block` × 3 | — | 3 | All 4 flags |
| `aws_s3_bucket_server_side_encryption_configuration` × 3 | — | 3 | KMS CMK |
| `aws_s3_bucket_versioning` × 3 | — | 3 | |
| `aws_s3_bucket_intelligent_tiering_configuration` | app-data | 1 | Archive@90d, Deep@180d |
| `aws_s3_bucket_lifecycle_configuration` × 3 | — | 3 | Per-bucket rules |
| `aws_s3_bucket_object_lock_configuration` | backups | 1 | COMPLIANCE 35d |
| `aws_s3_bucket_policy` × 3 | — | 3 | Deny HTTP + unencrypted PUT |
| `aws_vpc_endpoint_policy` | s3 | 1 | Restrict to HelixBeat buckets |

**Subtotal: ~21 resources**

---

#### IAM & IRSA — IAM Module

| Resource | Name Pattern | Count | Notes |
|----------|-------------|-------|-------|
| `aws_iam_role` (cluster-autoscaler) | `{cluster}-cluster-autoscaler` | 1 | IRSA |
| `aws_iam_role` (aws-lb-controller) | `{cluster}-aws-lb-controller` | 1 | IRSA |
| `aws_iam_role` (external-dns) | `{cluster}-external-dns` | 1 | IRSA |
| `aws_iam_role` (monitoring) | `{cluster}-monitoring` | 1 | IRSA (Prometheus/Loki) |
| `aws_iam_policy` × 4 | autoscaler, lb-ctrl, ext-dns, monitoring | 4 | |
| `aws_iam_role_policy_attachment` × 4 | — | 4 | |
| `aws_iam_account_password_policy` | — | 1 | 16-char, 90-day, 12-prev |
| `aws_s3_bucket` | `helixbeat-{env}-monitoring-{acct}` | 1 | Loki/Thanos long-term store |
| S3 bucket config × 4 | public-access-block, enc, versioning, lifecycle | 4 | |

**Subtotal: ~19 resources**

---

#### TLS — ACM Module

| Resource | Name Pattern | Count | Notes |
|----------|-------------|-------|-------|
| `aws_acm_certificate` | `*.helixbeat.com` | 1 | Wildcard + apex SAN |
| `aws_route53_record` | `_acme-challenge.*` | 1–2 | DNS validation |
| `aws_acm_certificate_validation` | — | 1 | 15-minute timeout |

**Subtotal: ~3 resources**

---

#### DNS — Route53 Module

| Resource | Name Pattern | Count | Notes |
|----------|-------------|-------|-------|
| `aws_route53_zone` (public) | `helixbeat.com` | 1 | |
| `aws_route53_zone` (private) | `internal.helixbeat.com` | 1 | VPC-private |
| `aws_route53_health_check` | ALB primary | 1 | HTTPS /health, 30s |
| `aws_route53_record` (apex) | `helixbeat.com` | 1 | A alias → ALB |
| `aws_route53_record` (wildcard) | `*.helixbeat.com` | 1 | A alias → ALB |
| `aws_route53_record` (docdb) | `docdb.internal.*` | 1 | CNAME → DocDB |

**Subtotal: ~6 resources**

---

#### Backup — Backup Module

| Resource | Name Pattern | Count | Notes |
|----------|-------------|-------|-------|
| `aws_backup_vault` | `helixbeat-{env}-backup-vault` | 1 | KMS |
| `aws_backup_vault_lock_configuration` | — | 1 | Compliance: 35d–7yr |
| `aws_iam_role` | `helixbeat-{env}-backup-role` | 1 | |
| `aws_iam_role_policy_attachment` × 3 | Backup + Restore + EFS | 3 | |
| `aws_backup_plan` | `helixbeat-{env}-daily-backup` | 1 | 3 rules |
| `aws_backup_selection` × 2 | tagged-resources, efs | 2 | |
| `aws_backup_vault_notifications` | — | 1 | → SNS on failure |

**Subtotal: ~10 resources**

---

### Total Resource Count Summary

| Module | Dev Resources | Staging Resources | Key Services |
|--------|----------:|----------:|-------------|
| VPC | ~22 | ~23 | 2 subnets/AZ × 2 AZs; 1 or 2 NAT GWs |
| Security | ~27 | ~27 | KMS, GuardDuty, WAF, CloudTrail, Config, SecurityHub |
| EKS | ~23 | ~23 | Cluster, 2 node groups (region-labeled), OIDC, ECR × 3 |
| ALB | ~9 | ~9 | Load Balancer, 2 listeners, WAF association |
| DocumentDB | ~10 | ~10 | 2-node cluster (AZ-a writer, AZ-b reader) |
| EFS | ~8 | ~8 | Filesystem, 2 mount targets, 2 access points |
| EC2 | ~13 | ~13 | ASG, Launch Template, SSM Patch Manager |
| S3 | ~21 | ~21 | 3 buckets + Object Lock + lifecycle |
| IAM | ~19 | ~19 | 4 IRSA roles, password policy, monitoring bucket |
| ACM | ~3 | ~3 | Wildcard TLS certificate |
| Route53 | ~6 | ~6 | Public + private zones, alias records |
| Backup | ~10 | ~10 | Vault + lock, 3-tier backup plan |
| **Total** | **~171** | **~172** | |

---

## Module Reference

### Module Dependency Graph

```
  security ──── kms_key_arn, waf_web_acl_arn ──────────────────┐
     │                                                          │
  vpc (single_nat_gateway: dev=true, staging=false)            │
     │  vpc_id, subnet_ids                                     │
     │                                                         │
  eks ──── oidc_provider_arn, node_sg_id ──┐                   │
     │     region_label = india|us          │                  │
     │                                     │                  │
  iam (IRSA)     efs (CSI driver) ◄─────────┘                  │
                                                               │
  acm ◄──────────────────────────────────────────────────────────┘
     │  certificate_arn
  alb ──── alb_dns, alb_zone, alb_sg ──────┐
                                           │
  documentdb ◄────── subnet_ids, node_sg ──┘
  ec2        ◄────── vpc, security, alb
  s3         ◄────── kms_key_arn
  backup     ◄────── kms_key_arn, efs_arns
  route53    ◄────── alb_dns, alb_zone, docdb_endpoint
```

### env-base Key Variables

```hcl
module "helixbeat" {
  source = "../../env-base"

  # Region & AZs
  aws_region         = "ap-south-1"
  availability_zones = ["ap-south-1a", "ap-south-1b"]   # 2 AZs for all envs

  # NAT Gateway (cost control)
  single_nat_gateway = true    # dev: 1 shared NAT GW (~$65/mo saving)
                               # staging: false → 2 NAT GWs (HA)

  # Module toggles (all default to true)
  modules = {
    eks        = true
    ec2        = true
    alb        = true    # disable if no domain delegation
    acm        = true    # disable if no domain delegation
    documentdb = true
    efs        = true
    s3         = true
    iam        = true
    backup     = true
  }
}
```

`region_label` (`india` or `us`) is derived automatically from `country_code` — no manual override needed.

---

## Environment Configurations

| Setting | dev-us | dev-in | staging-us | staging-in |
|---------|--------|--------|------------|------------|
| **Region** | us-east-1 | ap-south-1 | us-east-1 | ap-south-1 |
| **VPC CIDR** | 10.10.0.0/16 | 10.20.0.0/16 | 10.30.0.0/16 | 10.40.0.0/16 |
| **AZs** | a, b | a, b | a, b | a, b |
| **NAT Gateways** | 1 shared | 1 shared | 2 (HA) | 2 (HA) |
| **Node Pool Label** | `region=us` | `region=india` | `region=us` | `region=india` |
| **Node Pool Primary** | secondary | **primary** | secondary | **primary** |
| **System Nodes** | m5.large × 2 | m5.large × 2 | m5.large × 2 | m5.large × 2 |
| **App Nodes** | m5.large 1–5 | m5.large 1–5 | m5.xlarge 2–8 | m5.xlarge 2–8 |
| **EC2 Type** | m5.large | m5.large | m5.xlarge | m5.xlarge |
| **EC2 ASG** | 1–4 | 1–4 | 2–8 | 2–8 |
| **DocDB Class** | db.r6g.large | db.r6g.large | db.r6g.xlarge | db.r6g.xlarge |
| **DocDB Instances** | 2 | 2 | 2 | 2 |
| **DocDB Deletion Protection** | off | off | on | on |
| **ALB Deletion Protection** | off | off | on | on |
| **ACM + ALB** | disabled* | enabled | enabled | enabled |

> *dev-us: ACM and ALB disabled until `us.helixbeat.com` is delegated to Route53 name servers at GoDaddy.

---

## Helm Charts

All in-cluster services live under `helm/`. Each chart wraps an upstream Bitnami/community dependency and provides HelixBeat-specific defaults.

### Directory Structure

```
helm/
├── README.md               ← installation guide
├── keycloak/               ← Identity & Access Management
│   ├── Chart.yaml          ← Bitnami Keycloak 24.x dependency
│   ├── values.yaml         ← base values (all envs)
│   ├── values-dev.yaml     ← dev overrides
│   └── values-staging.yaml ← staging overrides
├── observability/          ← Prometheus + Grafana + Loki + Promtail
│   ├── Chart.yaml          ← kube-prometheus-stack + Loki + Promtail
│   ├── values.yaml
│   ├── values-dev.yaml
│   └── values-staging.yaml
├── alb-controller/         ← AWS Load Balancer Controller
│   ├── Chart.yaml          ← eks-charts aws-load-balancer-controller
│   ├── values.yaml
│   ├── values-dev.yaml
│   └── values-staging.yaml
└── minio/                  ← S3-compatible in-cluster object storage
    ├── Chart.yaml          ← Bitnami MinIO
    ├── values.yaml
    ├── values-dev.yaml
    └── values-staging.yaml
```

### Chart Summary

| Chart | Upstream Version | Default Namespace | Node Target | Notes |
|-------|-----------------|-------------------|-------------|-------|
| `keycloak` | Bitnami 24.x | `auth` | `region=india, role=app` | External DB, proxy=edge for ALB |
| `observability` | kube-prometheus-stack 58.x + Loki 6.x | `monitoring` | `region=india, role=app` | Loki stores logs in S3 monitoring bucket |
| `alb-controller` | AWS LB Controller 2.8.1 | `kube-system` | `region=india, role=system` | IRSA role from Terraform IAM module |
| `minio` | Bitnami MinIO latest | `storage` | `region=india, role=app` | Standalone in dev, distributed in staging |

### Installation Order

```
1. alb-controller   ← must be running before any Ingress resource is created
2. observability    ← Prometheus scrapes all ServiceMonitors incl. Keycloak + MinIO
3. keycloak         ← depends on external DB (DocumentDB endpoint from Terraform)
4. minio            ← independent
```

### Quick Install (dev-in)

```bash
# Get Terraform outputs
CLUSTER=$(terraform -chdir=terraform/environments/dev-in output -raw cluster_name)
VPC_ID=$(terraform -chdir=terraform/environments/dev-in output -raw vpc_id)
ALB_ROLE=<iam_module.aws_lb_controller_role_arn>
MON_ROLE=<iam_module.monitoring_role_arn>
MON_BUCKET=<iam_module.monitoring_bucket_name>
DOCDB_HOST=$(terraform -chdir=terraform/environments/dev-in output -raw documentdb_endpoint)

# 1. ALB Controller
helm dependency update helm/alb-controller
helm upgrade --install alb-controller helm/alb-controller \
  -n kube-system \
  -f helm/alb-controller/values.yaml \
  -f helm/alb-controller/values-dev.yaml \
  --set aws-load-balancer-controller.clusterName=${CLUSTER} \
  --set aws-load-balancer-controller.vpcId=${VPC_ID} \
  --set "aws-load-balancer-controller.serviceAccount.annotations.eks\.amazonaws\.com/role-arn"=${ALB_ROLE}

# 2. Observability
helm dependency update helm/observability
helm upgrade --install observability helm/observability \
  -n monitoring --create-namespace \
  -f helm/observability/values.yaml \
  -f helm/observability/values-dev.yaml \
  --set "loki.serviceAccount.annotations.eks\.amazonaws\.com/role-arn"=${MON_ROLE} \
  --set loki.loki.storage.s3.bucketNames.chunks=${MON_BUCKET} \
  --set loki.loki.storage.s3.bucketNames.ruler=${MON_BUCKET} \
  --set prometheus.grafana.adminPassword=<secure-password>

# 3. Keycloak
helm dependency update helm/keycloak
helm upgrade --install keycloak helm/keycloak \
  -n auth --create-namespace \
  -f helm/keycloak/values.yaml \
  -f helm/keycloak/values-dev.yaml \
  --set keycloak.auth.adminPassword=<secure-password> \
  --set keycloak.externalDatabase.host=${DOCDB_HOST}

# 4. MinIO
helm dependency update helm/minio
helm upgrade --install minio helm/minio \
  -n storage --create-namespace \
  -f helm/minio/values.yaml \
  -f helm/minio/values-dev.yaml \
  --set minio.auth.rootPassword=<secure-password>
```

See `helm/README.md` for full details including prerequisites and staging install commands.

---

## CI/CD Pipeline

### Triggers

| Event | Envs Affected | Action |
|-------|--------------|--------|
| PR opened/updated (`terraform/**`) | Changed envs | Plan + tfsec + checkov + per-resource cost (no apply) |
| Push to `main` (`terraform/**`) | Changed envs | Full pipeline → approval → apply |
| `workflow_dispatch` action=plan | Selected env | Plan + cost only |
| `workflow_dispatch` action=apply | Selected env | Full pipeline → approval → apply |
| `workflow_dispatch` action=destroy | Selected env | Approval → destroy |
| Schedule 06:00 UTC daily | All 4 envs | Drift detection |

### Cost Estimation

The pipeline uses **plan-based Infracost** (`infracost breakdown --path tfplan.json`) so only resources being created or changed in that run are priced — not pre-existing infrastructure.

Cost is visible in three places:
1. **Plan job step summary** — per-resource table (name, type, monthly cost, components)
2. **Commit comment** — collapsible per-environment breakdown before approval
3. **GitHub deployment status popup** — `$X.XX/mo · N resources` shown when reviewers open the approval dialog

### Required GitHub Secrets

| Secret | Purpose |
|--------|---------|
| `AWS_TF_ROLE_ARN` | OIDC role for plan + apply |
| `AWS_REGION` | Default AWS region |
| `TF_STATE_BUCKET` | S3 bucket for remote state |
| `TF_LOCK_TABLE` | DynamoDB table prefix for state locking |
| `INFRACOST_API_KEY` | Free at infracost.io |
| `TEAMS_WEBHOOK` | Microsoft Teams notifications |

### GitHub Environments (Approval Gates)

| GitHub Environment | Protects |
|-------------------|---------|
| `terraform-dev-us` | dev-us apply + destroy |
| `terraform-dev-in` | dev-in apply + destroy |
| `terraform-staging-us` | staging-us apply + destroy |
| `terraform-staging-in` | staging-in apply + destroy |

---

## Security Posture

### Encryption at Rest

| Layer | Key |
|-------|-----|
| EBS volumes (EC2 + EKS) | KMS CMK `helixbeat-{env}-general` |
| Kubernetes Secrets | Dedicated KMS `{cluster}-eks-kms` |
| All S3 buckets | KMS CMK SSE |
| DocumentDB | KMS CMK |
| EFS | KMS CMK |
| CloudTrail, SNS, Secrets Manager | KMS CMK |

### Encryption in Transit

| Connection | Mechanism |
|-----------|-----------|
| Browser → ALB | TLS 1.2+ (ACM wildcard) |
| ALB → EKS pod / EC2 | HTTPS :8443 / HTTP :8080 |
| EFS mounts | TLS enforced via filesystem policy |
| EC2/EKS → AWS services | HTTPS via VPC endpoints |
| DocumentDB | TLS via parameter group |

### Network Isolation

- No EC2 or EKS nodes with public IPs
- EKS API: private endpoint only
- EC2 reachable only through ALB SG (:8080/:8443)
- DocumentDB :27017 only from app-tier SG
- EFS :2049 only from EKS node SG
- No SSH/RDP — SSM Session Manager only
- Default VPC SG: all rules removed (deny-all)

### Threat Detection

| Control | Coverage |
|---------|---------|
| GuardDuty | S3, K8s audit, malware |
| SecurityHub | CIS v1.4, FSBP v1.0 |
| AWS Config | All resources, 6 rules |
| CloudTrail | Multi-region, mgmt + data events |
| WAF | CRS + KBI + SQLi + rate limiting |
| Inspector v2 | EC2 + ECR scanning |
| SSM Patch Manager | Weekly, 7-day approval |

---

## Backup & Disaster Recovery

### Backup Schedule

| Tier | Time (UTC) | Retention | Storage |
|------|-----------|-----------|---------|
| Daily | 03:00 | 35 days | Standard |
| Weekly | Sunday 04:00 | 90 days | Standard |
| Monthly | 1st 05:00 | 365 days | Cold after 1 day |

All resources tagged `BackupPolicy=helixbeat-daily` are auto-selected (EC2 vols, EKS PVCs, DocumentDB). EFS uses explicit ARN selection.

### Vault Lock

| Setting | Value |
|---------|-------|
| Reconfiguration window | 3 days |
| Minimum retention | 35 days |
| Maximum retention | 7 years |
| Mode | Compliance |

### Drift Detection

Daily at 06:00 UTC — on drift: S3 report saved, Jira ticket created (PLAT, high priority), Teams alert sent.

---

## Cost Management

Cost estimation uses `terraform show -json tfplan | infracost breakdown` so only resources **in the plan** are priced. Pre-existing infrastructure is excluded.

| Where | What you see |
|-------|-------------|
| Plan step summary | Per-resource table: name, type, monthly cost, components |
| Commit comment | Collapsible per-env breakdown, sorted by cost |
| Approval popup | `$X.XX/mo · N resources being created` |
| Apply step summary | Post-apply table of every resource that was just created |

Alert threshold: **$500/month delta** — warns in the commit comment but does not block apply.

---

## Operations

### Access EKS (India — Primary)

```bash
aws eks update-kubeconfig --name helixbeat-dev-in --region ap-south-1
kubectl get nodes -o wide --show-labels
# Look for:  region=india  role=app / role=system
```

### Access EKS (US — Secondary)

```bash
aws eks update-kubeconfig --name helixbeat-dev-us --region us-east-1
kubectl get nodes -o wide --show-labels
# Look for:  region=us  role=app / role=system
```

### Access EC2 Instances

```bash
aws ssm start-session --target <instance-id> --region ap-south-1
```

### Manual Terraform Operations

```bash
cd terraform/environments/dev-in

terraform init -reconfigure   # uses S3 backend defined in main.tf

terraform plan -out=tfplan
terraform apply tfplan

# Destroy — always go through pipeline for approval trail
terraform destroy
```

### Clear a Stuck State Lock

```bash
aws dynamodb delete-item \
  --table-name helixbeat-tfstate-lock-dev-in \
  --key '{"LockID": {"S": "helixbeat-tfstate-dev-in/dev-in/terraform.tfstate"}}' \
  --region ap-south-1
```

### Remote State Layout

```
s3://helixbeat-tfstate-{env}/
├── dev-us/terraform.tfstate        DynamoDB: helixbeat-tfstate-lock-dev-us
├── dev-in/terraform.tfstate        DynamoDB: helixbeat-tfstate-lock-dev-in
├── staging-us/terraform.tfstate    DynamoDB: helixbeat-tfstate-lock-staging-us
└── staging-in/terraform.tfstate    DynamoDB: helixbeat-tfstate-lock-staging-in
```

### Re-enable ACM + ALB in dev-us

Once `us.helixbeat.com` NS records point to Route53:

```hcl
# terraform/environments/dev-us/main.tf
modules = {
  acm = true
  alb = true
}
```

Push to `main` — pipeline will plan and apply. ACM validation completes in ~5 minutes.
