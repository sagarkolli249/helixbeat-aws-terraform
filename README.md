# HelixBeat — AWS Infrastructure

Production-grade, multi-environment AWS infrastructure managed with Terraform. Supports four live environments across two regions (US/IN) and two stages (dev/staging), orchestrated through a GitHub Actions IaC pipeline with cost-gated approvals.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Network Topology](#network-topology)
3. [Architecture Diagrams](#architecture-diagrams)
4. [Resource Mapping](#resource-mapping)
5. [Module Reference](#module-reference)
6. [Environment Configurations](#environment-configurations)
7. [CI/CD Pipeline](#cicd-pipeline)
8. [Security Posture](#security-posture)
9. [Backup & Disaster Recovery](#backup--disaster-recovery)
10. [Cost Management](#cost-management)
11. [Operations](#operations)

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                          HELIXBEAT AWS ENVIRONMENTS                          │
│                                                                              │
│   dev-us (us-east-1)      dev-in (ap-south-1)                               │
│   staging-us (us-east-1)  staging-in (ap-south-1)                           │
│                                                                              │
│   Each environment = 1 isolated VPC + full stack                             │
└──────────────────────────────────────────────────────────────────────────────┘

              github.com/sagarkolli249/helixbeat-aws-terraform
                              │
                              │  git push / workflow_dispatch
                              ▼
                    ┌─────────────────┐
                    │  GitHub Actions  │
                    │  IaC Pipeline   │
                    │  ─────────────  │
                    │  plan → cost    │
                    │  gate → apply   │
                    └────────┬────────┘
                             │ terraform apply
                    ┌────────▼────────┐
                    │  Remote State   │
                    │  S3 + DynamoDB  │
                    │  (per env)      │
                    └────────┬────────┘
                             │
               ┌─────────────┼─────────────┐
               ▼             ▼             ▼
           dev-us         dev-in       staging-us ...
           VPC Stack      VPC Stack    VPC Stack
```

---

## Network Topology

### VPC Layout (per environment)

Each environment receives its own isolated VPC. The CIDR blocks are:

| Environment | Region       | VPC CIDR      |
|-------------|--------------|---------------|
| dev-us      | us-east-1    | 10.10.0.0/16  |
| dev-in      | ap-south-1   | 10.10.0.0/16  |
| staging-us  | us-east-1    | 10.20.0.0/16  |
| staging-in  | ap-south-1   | 10.20.0.0/16  |

### Subnet Structure (3 Availability Zones)

```
VPC  10.x0.0.0/16
│
├── AZ-a
│   ├── Public Subnet   10.x0.0.0/24    ← ALB, NAT Gateway
│   └── Private Subnet  10.x0.3.0/24    ← EKS Nodes, EC2 ASG, DocumentDB, EFS
│
├── AZ-b
│   ├── Public Subnet   10.x0.1.0/24
│   └── Private Subnet  10.x0.4.0/24
│
└── AZ-c
    ├── Public Subnet   10.x0.2.0/24
    └── Private Subnet  10.x0.5.0/24
```

### Routing

| Subnet Type | Destination      | Target               |
|-------------|------------------|----------------------|
| Public      | 0.0.0.0/0        | Internet Gateway     |
| Public      | 10.x0.0.0/16     | local                |
| Private     | 0.0.0.0/0        | NAT Gateway (per AZ) |
| Private     | 10.x0.0.0/16     | local                |
| Private     | S3, ECR, SSM...  | VPC Endpoints        |

### VPC Endpoints (Private Connectivity — no NAT traversal)

| Type      | Service               | Purpose                            |
|-----------|-----------------------|------------------------------------|
| Gateway   | S3                    | ECR image layers, artifact storage |
| Interface | ecr.api               | ECR API calls                      |
| Interface | ecr.dkr               | Docker registry pulls              |
| Interface | ec2                   | EC2 metadata / API                 |
| Interface | sts                   | IAM role assumption (IRSA)         |
| Interface | logs                  | CloudWatch Logs from private nodes |
| Interface | ssm                   | Systems Manager                    |
| Interface | ssmmessages           | SSM Session Manager shell          |
| Interface | ec2messages           | SSM run commands                   |
| Interface | elasticloadbalancing  | ALB API                            |
| Interface | autoscaling           | ASG scale-in/out events            |

---

## Architecture Diagrams

### Full Stack — Single Environment

```
  INTERNET
     │
     │ HTTPS :443 / HTTP :80
     ▼
┌─────────────────────────────────────────────────────────────────────┐
│  PUBLIC SUBNETS  (AZ-a, AZ-b, AZ-c)                                │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │              Application Load Balancer (ALB)                  │  │
│  │   SG: 0.0.0.0/0 → :80,:443        WAF WebACL attached        │  │
│  │   Listener :80  → 301 redirect to HTTPS                      │  │
│  │   Listener :443 → Target Group (IP mode, /health check)      │  │
│  │   TLS: ACM wildcard *.helixbeat.com  (TLS 1.2 minimum)       │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  ┌──────────┐      ┌──────────┐      ┌──────────┐                  │
│  │ NAT-GW   │      │ NAT-GW   │      │ NAT-GW   │  ← HA, 1 per AZ │
│  │  AZ-a    │      │  AZ-b    │      │  AZ-c    │                  │
│  └────┬─────┘      └────┬─────┘      └────┬─────┘                  │
└───────┼─────────────────┼─────────────────┼───────────────────────┘
        │                 │                 │
        └─────────────────┼─────────────────┘
                          │  outbound HTTPS via NAT
                          ▼
┌─────────────────────────────────────────────────────────────────────┐
│  PRIVATE SUBNETS  (AZ-a, AZ-b, AZ-c)                               │
│                                                                     │
│  ┌───────────────────────────┐   ┌───────────────────────────────┐  │
│  │       EKS Cluster         │   │   EC2 Auto Scaling Group      │  │
│  │  ┌─────────────────────┐  │   │  ┌─────────────────────────┐  │  │
│  │  │  Control Plane      │  │   │  │  Launch Template        │  │  │
│  │  │  AWS-managed        │  │   │  │  IMDSv2 enforced        │  │  │
│  │  │  Private API only   │  │   │  │  gp3 encrypted EBS      │  │  │
│  │  │  K8s secrets → KMS  │  │   │  │  No public IP           │  │  │
│  │  └─────────────────────┘  │   │  └─────────────────────────┘  │  │
│  │  ┌─────────────────────┐  │   │  SG: :8080/:8443 from ALB     │  │
│  │  │  System Node Group  │  │   │  Self: node-to-node           │  │
│  │  │  m5.large × 2       │  │   │  ASG: rolling refresh         │  │
│  │  │  taint: system      │  │   │  SSM-only access (no SSH)     │  │
│  │  └─────────────────────┘  │   └───────────────────────────────┘  │
│  │  ┌─────────────────────┐  │                                      │
│  │  │  App Node Group     │  │   ┌───────────────────────────────┐  │
│  │  │  m5.xlarge × 2      │  │   │   DocumentDB Cluster (5.0)    │  │
│  │  │  HPA: 1–10 nodes    │  │   │   Primary   (AZ-a) ──┐        │  │
│  │  └─────────────────────┘  │   │   Replica   (AZ-b) ──┤ r/w   │  │
│  └───────────────────────────┘   │   Replica   (AZ-c) ──┘ split │  │
│                                   │   Port: 27017  KMS encrypted  │  │
│  ┌───────────────────────────┐   │   Backup: 35 days             │  │
│  │     EFS Filesystem        │   │   SG: :27017 from app tier    │  │
│  │  Mount Targets × 3 AZ     │   └───────────────────────────────┘  │
│  │  Access Points:           │                                      │
│  │    /kafka  (uid/gid 1000) │   ┌───────────────────────────────┐  │
│  │    /app    (uid/gid 1000) │   │   VPC Endpoints (~10 total)   │  │
│  │  TLS in-transit enforced  │   │   SSM · ECR · S3 · CW Logs    │  │
│  │  Elastic throughput       │   │   STS · EC2 · ELB · ASG       │  │
│  └───────────────────────────┘   └───────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
     │                                   │
     ▼                                   ▼
  Route53                             AWS Services
  Public zone: helixbeat.com          (via VPC Endpoints
  Private zone: internal.helixbeat.com  — no NAT traversal)
```

---

### Security Control Plane

```
┌──────────────────────────────────────────────────────────────────────┐
│                         SECURITY PLANE                               │
│                                                                      │
│  ┌────────────────┐  ┌──────────────────┐  ┌──────────────────────┐ │
│  │   GuardDuty    │  │   SecurityHub    │  │     AWS Config       │ │
│  │  ─────────── │  │  ──────────────  │  │  ──────────────────  │ │
│  │  S3 data logs  │  │  CIS v1.4.0      │  │  All resource types  │ │
│  │  K8s audit     │  │  FSBP v1.0       │  │  6 managed rules:    │ │
│  │  Malware scan  │  │                  │  │  • S3 public read    │ │
│  └────────────────┘  └──────────────────┘  │  • Encrypted vols   │ │
│                                             │  • CloudTrail on    │ │
│  ┌────────────────┐  ┌──────────────────┐  │  • IAM root keys    │ │
│  │  CloudTrail    │  │  WAFv2 WebACL    │  │  • Console MFA      │ │
│  │  ─────────── │  │  ──────────────  │  │  • EKS secrets enc  │ │
│  │  Multi-region  │  │  AWS CRS         │  └──────────────────────┘ │
│  │  All mgmt evts │  │  Known Bad Inputs│                            │
│  │  S3 + Lambda   │  │  SQLi rules      │  ┌──────────────────────┐ │
│  │  data events   │  │  Rate: 2000      │  │     KMS CMK          │ │
│  │  KMS encrypted │  │  req/5min/IP     │  │  ──────────────────  │ │
│  │  → S3 + CW Log │  └──────────────────┘  │  Key rotation: ON    │ │
│  └────────────────┘                        │  30-day delete win   │ │
│                                             │  Grants:             │ │
│  ┌────────────────┐  ┌──────────────────┐  │  • CloudWatch Logs   │ │
│  │  Inspector v2  │  │  SSM Patch Mgr   │  │  • CloudTrail        │ │
│  │  ─────────── │  │  ──────────────  │  │  • EKS Secrets       │ │
│  │  EC2 scanning  │  │  Sunday 2AM UTC  │  └──────────────────────┘ │
│  │  ECR scanning  │  │  7-day approval  │                            │
│  └────────────────┘  │  Security+Bugfix │                            │
│                       └──────────────────┘                           │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │                  SNS Security Alerts                          │    │
│  │  GuardDuty high-severity  │  WAF > 100 blocks/5min           │    │
│  │  Backup job failed        │  Restore job failed              │    │
│  │  ALB 5xx > 10             │  ALB p99 latency > 2s            │    │
│  │  DocDB CPU > 80%          │  DocDB free storage < 5GB        │    │
│  └──────────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────┘
```

---

### DNS & TLS Flow

```
  User's Browser
       │
       │  DNS lookup: api.helixbeat.com
       ▼
  Route53 Public Hosted Zone (helixbeat.com)
       │
       │  A record → ALB DNS alias (zone ID alias)
       ▼
  ALB Listener :443
       │  ACM Certificate: *.helixbeat.com (+ helixbeat.com SAN)
       │  Cipher: TLS 1.2+ (ELBSecurityPolicy-TLS13-1-2-2021-06)
       ▼
  Target Group  (type: ip)
       │  Health check: GET /health → 200
       │
       ├──→ EKS Pod IP (direct registration)
       └──→ EC2 Instance IP (legacy app tier)

  HTTP :80 → 301 redirect to HTTPS (no content served over HTTP)

  Internal Services (Route53 Private Zone: internal.helixbeat.com)
       │
       └──→ docdb.internal.helixbeat.com
               → DocumentDB cluster endpoint (writer)
```

---

### Backup Architecture

```
  Resources tagged:  BackupPolicy = helixbeat-daily
  ┌──────────────────────────────────────────────────────────────────┐
  │                                                                  │
  │  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐ │
  │  │ EKS EBS PVCs │  │  EC2 Volumes │  │ DocumentDB Cluster     │ │
  │  └──────┬───────┘  └──────┬───────┘  └───────────┬────────────┘ │
  │         └─────────────────┴──────────────────────┘              │
  │                            │                                     │
  │         ┌──────────────────┼──────────────────────┐             │
  │         ▼                  ▼                      ▼             │
  │   Daily 3AM UTC    Weekly Sun 4AM UTC    Monthly 1st 5AM UTC    │
  │   Retain: 35 days  Retain: 90 days       Cold: 1 day            │
  │                                          Retain: 365 days       │
  │                                                                  │
  │  EFS Filesystem ──→ Explicit ARN selection ──→ Daily plan       │
  └──────────────────────────┬───────────────────────────────────────┘
                             │
                             ▼
            ┌────────────────────────────────────┐
            │     AWS Backup Vault (KMS)          │
            │  helixbeat-{env}-backup-vault       │
            │                                     │
            │  Vault Lock (Compliance mode)        │
            │  ├─ Changeable window: 3 days        │
            │  ├─ Minimum retention: 35 days       │
            │  └─ Maximum retention: 7 years       │
            └────────────────────────────────────┘
                             │ failures
                             ▼
                    SNS → email / Teams alert
```

---

### CI/CD Pipeline Flow

```
  Developer
       │
       │  git push → main  (terraform/** paths changed)
       ▼
  ┌────────────────────────────────────────────────────────────────┐
  │                   GitHub Actions Pipeline                       │
  │                                                                │
  │  ┌────────────────┐                                            │
  │  │  changed-envs  │← git diff: which of 4 envs need apply     │
  │  └───────┬────────┘                                            │
  │          │  matrix: [dev-us, dev-in, staging-us, staging-in]   │
  │          ▼  (parallel per env)                                 │
  │  ┌──────────────────────────────────────────────────────────┐  │
  │  │                       plan job                            │  │
  │  │  terraform fmt -check                                     │  │
  │  │  terraform validate                                       │  │
  │  │  terraform init  (S3 backend + DynamoDB lock)             │  │
  │  │  terraform plan -out=tfplan -detailed-exitcode            │  │
  │  │  tfsec           → SARIF → GitHub Security tab            │  │
  │  │  checkov          → SARIF → GitHub Security tab           │  │
  │  │  infracost diff  → cost delta vs main branch              │  │
  │  │  upload: tfplan + infracost.json → S3 artifacts           │  │
  │  └────────────────────────────┬─────────────────────────────┘  │
  │                               │                                │
  │                               ▼                                │
  │  ┌──────────────────────────────────────────────────────────┐  │
  │  │                    cost-gate job                          │  │
  │  │  download all infracost.json artifacts                    │  │
  │  │  build resource-level cost breakdown per environment      │  │
  │  │  post commit comment with full detail                     │  │
  │  │  update GitHub deployment status with cost summary        │  │
  │  └────────────────────────────┬─────────────────────────────┘  │
  │                               │                                │
  │                               ▼                                │
  │                    ┌─────────────────────┐                     │
  │                    │   MANUAL APPROVAL   │← required reviewer  │
  │                    │  GitHub Environment │  sees cost in popup │
  │                    └──────────┬──────────┘                     │
  │                               │                                │
  │                               ▼                                │
  │  ┌──────────────────────────────────────────────────────────┐  │
  │  │                      apply job                            │  │
  │  │  download tfplan from S3                                  │  │
  │  │  terraform apply -input=false tfplan                      │  │
  │  │  Teams notification (success / failure)                   │  │
  │  └──────────────────────────────────────────────────────────┘  │
  └────────────────────────────────────────────────────────────────┘

  Manual destroy path:
  workflow_dispatch (action=destroy, environment=dev-us)
       → MANUAL APPROVAL
       → terraform destroy -auto-approve
```

---

## Resource Mapping

### Complete Resource Inventory (per environment)

#### Networking — VPC Module

| Resource | Name Pattern | Count | Notes |
|----------|-------------|-------|-------|
| `aws_vpc` | `helixbeat-{env}` | 1 | DNS hostnames + resolution enabled |
| `aws_internet_gateway` | `helixbeat-{env}-igw` | 1 | Attached to VPC |
| `aws_subnet` (public) | `helixbeat-{env}-public-{az}` | 3 | One per AZ |
| `aws_subnet` (private) | `helixbeat-{env}-private-{az}` | 3 | One per AZ |
| `aws_eip` | `helixbeat-{env}-nat-{az}` | 3 | Static IPs for NAT GWs |
| `aws_nat_gateway` | `helixbeat-{env}-nat-{az}` | 3 | HA: one per AZ |
| `aws_route_table` (public) | `helixbeat-{env}-public-rt` | 1 | Shared, default route → IGW |
| `aws_route_table` (private) | `helixbeat-{env}-private-rt-{az}` | 3 | Per-AZ, default route → NAT GW |
| `aws_route_table_association` | — | 6 | 3 public + 3 private |
| `aws_vpc_endpoint` (gateway) | `helixbeat-{env}-s3-endpoint` | 1 | S3 gateway (free) |
| `aws_vpc_endpoint` (interface) | `helixbeat-{env}-{svc}-endpoint` | ~10 | ECR, SSM, CW Logs, STS, etc. |
| `aws_security_group` (endpoints) | `helixbeat-{env}-vpc-endpoints-sg` | 1 | HTTPS :443 from VPC CIDR |
| `aws_flow_log` | `helixbeat-{env}-flow-logs` | 1 | ALL traffic → CloudWatch Logs |
| `aws_cloudwatch_log_group` | `/helixbeat/{env}/vpc-flow-logs` | 1 | 365-day retention |
| `aws_iam_role` | `helixbeat-{env}-flow-logs-role` | 1 | VPC Flow Logs delivery |
| `aws_default_security_group` | — | 1 | All rules removed (deny-all baseline) |

**Subtotal: ~24 resources**

---

#### Security & Compliance — Security Module

| Resource | Name Pattern | Count | Notes |
|----------|-------------|-------|-------|
| `aws_s3_account_public_access_block` | — | 1 | Blocks all public access account-wide |
| `aws_kms_key` | `helixbeat-{env}-general-kms` | 1 | CMK, 30-day deletion window, rotation ON |
| `aws_kms_alias` | `alias/helixbeat-{env}-general` | 1 | |
| `aws_s3_bucket` (cloudtrail) | `helixbeat-{env}-cloudtrail-{acct}` | 1 | Versioned, KMS, 7-year lifecycle |
| `aws_s3_bucket_versioning` | cloudtrail | 1 | |
| `aws_s3_bucket_lifecycle_configuration` | cloudtrail | 1 | IA@90d, GLACIER@365d, expire@2555d |
| `aws_s3_bucket` (config) | `helixbeat-{env}-config-{acct}` | 1 | KMS encrypted, Config delivery target |
| `aws_cloudtrail` | `helixbeat-{env}-trail` | 1 | Multi-region, management + data events |
| `aws_cloudwatch_log_group` | `/helixbeat/{env}/cloudtrail` | 1 | 365-day retention, KMS encrypted |
| `aws_iam_role` | `helixbeat-{env}-cloudtrail-cw-role` | 1 | CloudTrail → CloudWatch delivery |
| `aws_iam_role` | `helixbeat-{env}-config-role` | 1 | AWS Config recorder role |
| `aws_guardduty_detector` | — | 1 | S3 logs, K8s audit, malware scan |
| `aws_securityhub_account` | — | 1 | |
| `aws_securityhub_standards_subscription` | CIS AWS v1.4.0 | 1 | Conditional per region |
| `aws_securityhub_standards_subscription` | FSBP v1.0 | 1 | Conditional per region |
| `aws_config_configuration_recorder` | `helixbeat-{env}` | 1 | All resource types incl. global |
| `aws_config_delivery_channel` | `helixbeat-{env}` | 1 | Delivery to S3 config bucket |
| `aws_config_configuration_recorder_status` | — | 1 | Recorder enabled |
| `aws_config_config_rule` | s3-bucket-public-read-prohibited | 1 | |
| `aws_config_config_rule` | encrypted-volumes | 1 | |
| `aws_config_config_rule` | cloudtrail-enabled | 1 | |
| `aws_config_config_rule` | iam-root-access-key-check | 1 | |
| `aws_config_config_rule` | mfa-enabled-for-iam-console-access | 1 | |
| `aws_config_config_rule` | eks-secrets-encrypted | 1 | |
| `aws_wafv2_web_acl` | `helixbeat-{env}-waf` | 1 | CRS + KBI + SQLi + rate 2000/5min |
| `aws_cloudwatch_metric_alarm` | guardduty-high-severity | 1 | ≥1 finding → SNS |
| `aws_cloudwatch_metric_alarm` | waf-blocked-requests | 1 | > 100 blocks/5min → SNS |
| `aws_sns_topic` | `helixbeat-{env}-security-alerts` | 1 | KMS encrypted |
| `aws_sns_topic_subscription` | email | N | One per configured address |

**Subtotal: ~29 resources**

---

#### Container Platform — EKS Module

| Resource | Name Pattern | Count | Notes |
|----------|-------------|-------|-------|
| `aws_kms_key` | `helixbeat-{env}-eks-secrets` | 1 | Kubernetes Secrets envelope encryption |
| `aws_kms_alias` | `alias/helixbeat-{env}-eks-secrets` | 1 | |
| `aws_iam_role` | `helixbeat-{env}-eks-cluster-role` | 1 | EKS control plane role |
| `aws_iam_role_policy_attachment` | AmazonEKSClusterPolicy | 1 | |
| `aws_iam_role_policy_attachment` | AmazonEKSVPCResourceController | 1 | |
| `aws_security_group` | `helixbeat-{env}-eks-cluster-sg` | 1 | Control plane: :443 from nodes |
| `aws_security_group` | `helixbeat-{env}-eks-nodes-sg` | 1 | Worker nodes |
| `aws_eks_cluster` | `helixbeat-{env}` | 1 | Private API, K8s secrets encryption |
| `aws_iam_openid_connect_provider` | — | 1 | IRSA / Workload Identity |
| `aws_iam_role` | `helixbeat-{env}-eks-node-role` | 1 | Managed node group role |
| `aws_iam_role_policy_attachment` | AmazonEKSWorkerNodePolicy | 1 | |
| `aws_iam_role_policy_attachment` | AmazonEKS_CNI_Policy | 1 | |
| `aws_iam_role_policy_attachment` | AmazonEC2ContainerRegistryReadOnly | 1 | |
| `aws_iam_role_policy_attachment` | AmazonSSMManagedInstanceCore (nodes) | 1 | |
| `aws_eks_node_group` | `helixbeat-{env}-system` | 1 | m5.large × 2, taint: dedicated=system |
| `aws_eks_node_group` | `helixbeat-{env}-app` | 1 | m5.xlarge × 2, HPA: 1–10 |
| `aws_cloudwatch_log_group` | `/aws/eks/helixbeat-{env}/cluster` | 1 | 90-day retention |
| `aws_ecr_repository` | `helixbeat-{env}/api` | 1 | Immutable tags, scan on push, KMS |
| `aws_ecr_repository` | `helixbeat-{env}/worker` | 1 | Immutable tags, scan on push, KMS |
| `aws_ecr_repository` | `helixbeat-{env}/frontend` | 1 | Immutable tags, scan on push, KMS |
| `aws_ecr_lifecycle_policy` | — | 3 | Keep last 20 images per repo |

**Subtotal: ~21 resources**

---

#### Load Balancing — ALB Module

| Resource | Name Pattern | Count | Notes |
|----------|-------------|-------|-------|
| `aws_security_group` | `helixbeat-{env}-alb-sg` | 1 | 0.0.0.0/0 → :80,:443 |
| `aws_lb` | `helixbeat-{env}-alb` | 1 | Internet-facing, HTTP/2, drop invalid headers |
| `aws_lb_target_group` | `helixbeat-{env}-default-tg` | 1 | IP mode, port 80, /health check |
| `aws_lb_listener` | HTTP :80 | 1 | Permanent redirect to HTTPS |
| `aws_lb_listener` | HTTPS :443 | 1 | ACM cert, TLS 1.2+, forward to TG |
| `aws_wafv2_web_acl_association` | — | 1 | ALB ↔ WAF WebACL |
| `aws_s3_bucket` | `helixbeat-{env}-alb-logs-{acct}` | 1 | Access logs bucket |
| `aws_s3_bucket_lifecycle_configuration` | alb-logs | 1 | IA@30d, expire@90d |
| `aws_cloudwatch_metric_alarm` | alb-5xx-errors | 1 | > 10 errors/min → SNS |
| `aws_cloudwatch_metric_alarm` | alb-response-time | 1 | p99 > 2s → SNS |

**Subtotal: ~10 resources**

---

#### Database — DocumentDB Module

| Resource | Name Pattern | Count | Notes |
|----------|-------------|-------|-------|
| `aws_secretsmanager_secret` | `helixbeat/{env}/docdb/master` | 1 | KMS encrypted |
| `aws_secretsmanager_secret_version` | — | 1 | JSON: username/password/host/port/dbname/engine |
| `aws_docdb_subnet_group` | `helixbeat-{env}-docdb-sng` | 1 | All 3 private subnets |
| `aws_security_group` | `helixbeat-{env}-docdb-sg` | 1 | :27017 from EKS nodes + EC2 ASG only |
| `aws_docdb_cluster_parameter_group` | `helixbeat-{env}-docdb-pg` | 1 | TLS on, audit logs all, TTL monitor |
| `aws_docdb_cluster` | `helixbeat-{env}-docdb` | 1 | Engine 5.0.0, KMS, 35-day backup |
| `aws_docdb_cluster_instance` | `helixbeat-{env}-docdb-0` | 1 | AZ-a (writer) |
| `aws_docdb_cluster_instance` | `helixbeat-{env}-docdb-1` | 1 | AZ-b (reader) |
| `aws_docdb_cluster_instance` | `helixbeat-{env}-docdb-2` | 1 | AZ-c (reader) |
| `aws_cloudwatch_metric_alarm` | docdb-cpu | 1 | > 80% utilization |
| `aws_cloudwatch_metric_alarm` | docdb-free-storage | 1 | < 5 GB free |
| `aws_cloudwatch_metric_alarm` | docdb-connections | 1 | > 800 connections |

**Subtotal: ~12 resources**

---

#### Shared Filesystem — EFS Module

| Resource | Name Pattern | Count | Notes |
|----------|-------------|-------|-------|
| `aws_security_group` | `helixbeat-{env}-efs-sg` | 1 | NFS :2049 from EKS node SG only |
| `aws_efs_file_system` | — | 1 | KMS encrypted, elastic throughput, IA after 30d |
| `aws_efs_mount_target` | — | 3 | One per private subnet (AZ) |
| `aws_efs_access_point` | kafka | 1 | uid/gid 1000, root path /kafka |
| `aws_efs_access_point` | app | 1 | uid/gid 1000, root path /app |
| `aws_iam_role` | `helixbeat-{env}-efs-csi-role` | 1 | IRSA for EFS CSI driver |
| `aws_iam_role_policy_attachment` | AmazonEFSCSIDriverPolicy | 1 | |
| `aws_efs_file_system_policy` | — | 1 | Deny non-TLS mounts |

**Subtotal: ~9 resources**

---

#### EC2 App Tier — EC2 Module

| Resource | Name Pattern | Count | Notes |
|----------|-------------|-------|-------|
| `aws_iam_role` | `helixbeat-{env}-ec2-role` | 1 | SSM + CW + Inspector + ECR + Secrets |
| `aws_iam_role_policy_attachment` | AmazonSSMManagedInstanceCore | 1 | Replaces SSH |
| `aws_iam_role_policy_attachment` | CloudWatchAgentServerPolicy | 1 | |
| `aws_iam_role_policy_attachment` | AmazonInspector2ManagedCisPolicy | 1 | |
| `aws_iam_role_policy_attachment` | AmazonEC2ContainerRegistryReadOnly | 1 | |
| `aws_iam_role_policy` | read-secrets | 1 | Secrets Manager + KMS decrypt for `{project}/{env}/*` |
| `aws_iam_instance_profile` | `helixbeat-{env}-ec2-profile` | 1 | |
| `aws_security_group` | `helixbeat-{env}-ec2-sg` | 1 | :8080/:8443 from ALB; self (node-to-node) |
| `aws_launch_template` | `helixbeat-{env}-lt` | 1 | IMDSv2, gp3 EBS encrypted, no public IP |
| `aws_autoscaling_group` | `helixbeat-{env}-asg` | 1 | Rolling refresh, 75% min healthy |
| `aws_inspector2_enabler` | — | 1 | EC2 + ECR vulnerability scanning |
| `aws_ssm_patch_baseline` | `helixbeat-{env}-al2-baseline` | 1 | 7-day approval, Security+Bugfix |
| `aws_ssm_maintenance_window` | `helixbeat-{env}-patch-window` | 1 | Sundays 02:00 UTC, 3h window |
| `aws_ssm_maintenance_window_target` | all-instances | 1 | Tag: Project=helixbeat |

**Subtotal: ~14 resources**

---

#### Object Storage — S3 Module

| Resource | Name Pattern | Count | Notes |
|----------|-------------|-------|-------|
| `aws_s3_bucket` | `helixbeat-{env}-app-data-{acct}` | 1 | Versioned, intelligent tiering |
| `aws_s3_bucket` | `helixbeat-{env}-backups-{acct}` | 1 | Object Lock COMPLIANCE mode |
| `aws_s3_bucket` | `helixbeat-{env}-artifacts-{acct}` | 1 | CI/CD artifacts |
| `aws_s3_bucket_public_access_block` | — | 3 | All 4 flags enabled per bucket |
| `aws_s3_bucket_server_side_encryption_configuration` | — | 3 | KMS CMK SSE |
| `aws_s3_bucket_versioning` | — | 3 | Enabled on all |
| `aws_s3_bucket_intelligent_tiering_configuration` | app-data | 1 | Archive@90d, Deep Archive@180d |
| `aws_s3_bucket_lifecycle_configuration` | app-data | 1 | Transition non-current, expire@365d |
| `aws_s3_bucket_lifecycle_configuration` | backups | 1 | GLACIER@30d, expire@2555d (7yr) |
| `aws_s3_bucket_lifecycle_configuration` | artifacts | 1 | Non-current version expire@90d |
| `aws_s3_bucket_object_lock_configuration` | backups | 1 | COMPLIANCE mode, 35-day retention |
| `aws_s3_bucket_policy` | — | 3 | Deny HTTP, deny unencrypted PUT |
| `aws_vpc_endpoint_policy` | s3 | 1 | Restrict to HelixBeat buckets only |

**Subtotal: ~21 resources**

---

#### IAM & IRSA — IAM Module

| Resource | Name Pattern | Count | Notes |
|----------|-------------|-------|-------|
| `aws_iam_role` | `{cluster}-cluster-autoscaler` | 1 | IRSA — K8s namespace: kube-system |
| `aws_iam_policy` | cluster-autoscaler | 1 | ASG describe + setDesiredCapacity |
| `aws_iam_role` | `{cluster}-aws-lb-controller` | 1 | IRSA — K8s namespace: kube-system |
| `aws_iam_policy` | aws-lb-controller | 1 | Full ELB + ACM + WAF + Route53 |
| `aws_iam_role` | `{cluster}-external-dns` | 1 | IRSA — K8s namespace: external-dns |
| `aws_iam_policy` | external-dns | 1 | Route53 ChangeResourceRecordSets |
| `aws_iam_role` | `{cluster}-monitoring` | 1 | IRSA — Prometheus / Loki / Thanos |
| `aws_iam_policy` | monitoring | 1 | CloudWatch + S3 put + EC2 describe |
| `aws_iam_role_policy_attachment` | — | 4 | One per IRSA role |
| `aws_iam_account_password_policy` | — | 1 | 16-char min, 90-day max, 12 prev |
| `aws_s3_bucket` | `helixbeat-{env}-monitoring-{acct}` | 1 | Loki/Thanos long-term metrics store |
| `aws_s3_bucket_versioning` | monitoring | 1 | |
| `aws_s3_bucket_server_side_encryption_configuration` | monitoring | 1 | KMS CMK |
| `aws_s3_bucket_public_access_block` | monitoring | 1 | |
| `aws_s3_bucket_lifecycle_configuration` | monitoring | 1 | IA@30d, expire@365d |

**Subtotal: ~19 resources**

---

#### TLS Certificate — ACM Module

| Resource | Name Pattern | Count | Notes |
|----------|-------------|-------|-------|
| `aws_acm_certificate` | `*.helixbeat.com` | 1 | Wildcard + apex SAN, DNS validation |
| `aws_route53_record` | `_acme-challenge.{domain}` | 1–2 | CNAME records for DNS validation |
| `aws_acm_certificate_validation` | — | 1 | Waits up to 15 minutes |

**Subtotal: ~3–4 resources**

---

#### DNS — Route53 Module

| Resource | Name Pattern | Count | Notes |
|----------|-------------|-------|-------|
| `aws_route53_zone` (public) | `helixbeat.com` | 1 | Public hosted zone |
| `aws_route53_zone` (private) | `internal.helixbeat.com` | 1 | VPC-associated private zone |
| `aws_route53_health_check` | ALB primary | 1 | HTTPS :443 /health, 30s interval |
| `aws_route53_record` | apex `helixbeat.com` | 1 | A alias → ALB |
| `aws_route53_record` | wildcard `*.helixbeat.com` | 1 | A alias → ALB |
| `aws_route53_record` | `docdb.internal.helixbeat.com` | 1 | CNAME → DocumentDB cluster endpoint |

**Subtotal: ~6 resources**

---

#### Backup — Backup Module

| Resource | Name Pattern | Count | Notes |
|----------|-------------|-------|-------|
| `aws_backup_vault` | `helixbeat-{env}-backup-vault` | 1 | KMS encrypted |
| `aws_backup_vault_lock_configuration` | — | 1 | Compliance: 3d change, 35d–7yr range |
| `aws_iam_role` | `helixbeat-{env}-backup-role` | 1 | AWS Backup service role |
| `aws_iam_role_policy_attachment` | AWSBackupServiceRolePolicyForBackup | 1 | |
| `aws_iam_role_policy_attachment` | AWSBackupServiceRolePolicyForRestores | 1 | |
| `aws_iam_role_policy_attachment` | AmazonElasticFileSystemClientFullAccess | 1 | EFS backup permission |
| `aws_backup_plan` | `helixbeat-{env}-daily-backup` | 1 | 3 rules: daily / weekly / monthly |
| `aws_backup_selection` | tagged-resources | 1 | Tag: BackupPolicy=helixbeat-daily |
| `aws_backup_selection` | efs | 1 | Explicit EFS filesystem ARN |
| `aws_backup_vault_notifications` | — | 1 | SNS on BACKUP_JOB_FAILED + RESTORE_JOB_FAILED |

**Subtotal: ~10 resources**

---

### Total Resource Count Summary

| Module | Resources | Key Services |
|--------|----------:|-------------|
| VPC | ~24 | Subnets × 6, NAT GW × 3, VPC Endpoints × 11, Flow Logs |
| Security | ~29 | KMS, GuardDuty, WAF, CloudTrail, Config × 6 rules, SecurityHub |
| EKS | ~21 | Cluster, 2 Node Groups, OIDC Provider, ECR × 3 |
| ALB | ~10 | Load Balancer, 2 Listeners, Target Group, WAF association |
| DocumentDB | ~12 | 3-node cluster, Secrets Manager, 3 CloudWatch alarms |
| EFS | ~9 | Filesystem, Mount Targets × 3, Access Points × 2 |
| EC2 | ~14 | ASG, Launch Template, SSM Patch Manager, Inspector |
| S3 | ~21 | 3 app buckets + Object Lock + lifecycle policies |
| IAM | ~19 | 4 IRSA roles, password policy, monitoring bucket |
| ACM | ~4 | Wildcard TLS certificate, DNS validation |
| Route53 | ~6 | Public + private zones, health check, alias records |
| Backup | ~10 | Vault + lock, 3-tier backup plan, tag-based selection |
| **Total** | **~179** | |

---

## Module Reference

### Module Dependency Graph

```
  ┌─────────────┐
  │   security  │──── kms_key_arn ──────────────────────────────────┐
  │   (always)  │──── waf_web_acl_arn ──────────────────────────┐   │
  └──────┬──────┘                                               │   │
         │ general_kms_key_arn                                  │   │
         │                                                      │   │
  ┌──────▼──────┐                                               │   │
  │     vpc     │──── vpc_id, subnet_ids ────────────────────┐  │   │
  │   (always)  │──── vpc_endpoint_sg_id ──────────────────┐ │  │   │
  └─────────────┘                                          │ │  │   │
                                                           │ │  │   │
  ┌─────────────┐                                          │ │  │   │
  │     eks     │◄───────────────────────────────────────────┘  │   │
  │ (optional)  │── oidc_provider_arn, node_sg_id ──┐       │   │   │
  └──────┬──────┘                                   │       │   │   │
         │                                          │       │   │   │
  ┌──────▼──────┐  ┌──────────────┐                 │       │   │   │
  │     iam     │  │     efs      │◄────────────────┘       │   │   │
  │  (IRSA)     │  │ (CSI driver) │◄───────────────────────-┘   │   │
  └─────────────┘  └──────────────┘                             │   │
                                                                │   │
  ┌─────────────┐                                               │   │
  │     acm     │◄──────────────────────────────────────────────┘   │
  │ (optional)  │── certificate_arn ──────────────────────────┐     │
  └─────────────┘                                             │     │
                                                              │     │
  ┌─────────────┐                                             │     │
  │     alb     │◄────────────────────────────────────────────┘     │
  │ (optional)  │── alb_dns_name, alb_zone_id, alb_sg_id ──┐        │
  └─────────────┘                                          │        │
                                                           │        │
  ┌─────────────┐                                          │        │
  │  documentdb │◄───────────────────────────────────────────────────┘
  │ (optional)  │◄──── subnet_ids, node_sg_id ─────────────┘
  └─────────────┘
  ┌─────────────┐
  │     ec2     │◄──── vpc, security, alb (all optional refs)
  └─────────────┘
  ┌─────────────┐
  │     s3      │◄──── kms_key_arn
  └─────────────┘
  ┌─────────────┐
  │   backup    │◄──── kms_key_arn, efs_file_system_arns
  └─────────────┘
  ┌─────────────┐
  │   route53   │◄──── alb_dns_name, alb_zone_id, docdb endpoint
  └─────────────┘
```

### env-base Module Toggles

```hcl
module "env_base" {
  source = "../../env-base"

  modules = {
    eks        = true    # EKS cluster + node groups + ECR
    ec2        = true    # EC2 Auto Scaling Group (legacy app tier)
    alb        = true    # Application Load Balancer (disable if no domain)
    acm        = true    # ACM TLS certificate (disable if no domain delegation)
    documentdb = true    # DocumentDB cluster
    efs        = true    # EFS shared filesystem
    s3         = true    # Application S3 buckets
    iam        = true    # IRSA roles for K8s workloads
    backup     = true    # AWS Backup vault + plans
    route53    = true    # DNS zones and records
  }
}
```

All disabled modules safely output empty strings — cross-module references use `try(module.X[0].output, "")` to avoid plan-time errors.

---

## Environment Configurations

| Setting | dev-us | dev-in | staging-us | staging-in |
|---------|--------|--------|------------|------------|
| **Region** | us-east-1 | ap-south-1 | us-east-1 | ap-south-1 |
| **VPC CIDR** | 10.10.0.0/16 | 10.10.0.0/16 | 10.20.0.0/16 | 10.20.0.0/16 |
| **AZs** | a, b, c | a, b, c | a, b, c | a, b, c |
| **EKS K8s Version** | 1.29 | 1.29 | 1.29 | 1.29 |
| **System Nodes** | m5.large × 2 | m5.large × 2 | m5.large × 2 | m5.large × 2 |
| **App Nodes** | m5.large 1–5 | m5.large 1–5 | m5.xlarge 2–8 | m5.xlarge 2–8 |
| **EC2 Type** | m5.large | m5.large | m5.xlarge | m5.xlarge |
| **EC2 ASG** | 1 min / 4 max | 1 min / 4 max | 2 min / 8 max | 2 min / 8 max |
| **EC2 Root Disk** | 50 GB | 50 GB | 100 GB | 100 GB |
| **DocDB Class** | db.r6g.large | db.r6g.large | db.r6g.xlarge | db.r6g.xlarge |
| **DocDB Instances** | 3 | 3 | 3 | 3 |
| **DocDB Deletion Protection** | off | off | on | on |
| **ALB Deletion Protection** | off | off | on | on |
| **ACM + ALB Enabled** | no* | yes | yes | yes |
| **DocDB Backup Retention** | 35 days | 35 days | 35 days | 35 days |

> *dev-us: ACM and ALB are disabled (`modules.acm = false, modules.alb = false`) until `us.helixbeat.com` is delegated at GoDaddy to the Route53 name servers shown in the public hosted zone.

---

## CI/CD Pipeline

### Triggers

| Event | Envs Affected | Action |
|-------|--------------|--------|
| PR opened/updated (`terraform/**`) | Changed envs | Plan + tfsec + checkov + cost estimate (no apply) |
| Push to `main` (`terraform/**`) | Changed envs | Full pipeline → approval → apply |
| `workflow_dispatch` action=plan | Selected env | Plan only |
| `workflow_dispatch` action=apply | Selected env | Full pipeline → approval → apply |
| `workflow_dispatch` action=destroy | Selected env | Approval → destroy |
| Schedule 06:00 UTC daily | All 4 envs | Drift detection |

### Required GitHub Secrets

| Secret | Purpose |
|--------|---------|
| `AWS_ROLE_ARN` | OIDC role ARN used for `terraform plan` (read-only) |
| `AWS_DEPLOY_ROLE_ARN` | OIDC role ARN used for `terraform apply` / destroy |
| `TF_STATE_BUCKET` | S3 bucket holding remote state files |
| `TF_LOCK_TABLE` | DynamoDB table for Terraform state locking |
| `INFRACOST_API_KEY` | Infracost cloud pricing API key |
| `TEAMS_WEBHOOK_URL` | Microsoft Teams incoming webhook for notifications |

### GitHub Environments (Approval Gates)

| GitHub Environment | Protects |
|-------------------|---------|
| `terraform-dev-us` | dev-us apply + destroy |
| `terraform-dev-in` | dev-in apply + destroy |
| `terraform-staging-us` | staging-us apply + destroy |
| `terraform-staging-in` | staging-in apply + destroy |

Each environment must have at least one **required reviewer** configured in GitHub → Settings → Environments.

---

## Security Posture

### Encryption at Rest

| Data Layer | Encryption |
|-----------|-----------|
| EBS volumes (EC2 + EKS) | KMS CMK (`helixbeat-{env}-general`) |
| Kubernetes Secrets | Dedicated KMS key (`helixbeat-{env}-eks-secrets`) |
| All S3 buckets | KMS CMK SSE (SSE-KMS) |
| DocumentDB cluster | KMS CMK |
| EFS filesystem | KMS CMK |
| CloudTrail logs | KMS CMK |
| Secrets Manager secrets | KMS CMK |
| SNS topics | KMS CMK |

### Encryption in Transit

| Connection | Mechanism |
|-----------|-----------|
| Browser → ALB | TLS 1.2+ (ACM wildcard certificate) |
| ALB → EKS / EC2 | HTTPS :8443 or HTTP :8080 (internal) |
| EFS mounts | TLS enforced via filesystem policy |
| EC2 → AWS services | HTTPS via VPC endpoints |
| DocumentDB connections | TLS enforced via parameter group |

### Network Isolation

- Zero EC2 instances with public IP addresses
- EKS API server: private endpoint only (no public access)
- EC2 app tier traffic must pass through ALB security group (:8080/:8443 only)
- DocumentDB port 27017 only from app-tier security group
- EFS port 2049 only from EKS node security group
- No SSH/RDP — access via SSM Session Manager only
- Default VPC security group: all inbound/outbound rules removed

### Identity Controls

| Control | Setting |
|---------|---------|
| IMDSv2 | Mandatory on all EC2 (hop limit = 1, prevents container leakage) |
| IRSA | All Kubernetes workloads use pod-level IAM roles (no node credentials) |
| IAM password policy | 16-char min, 90-day max age, 12 previous passwords remembered |
| Long-term access keys | None for service workloads |

### Threat Detection & Compliance

| Control | Coverage |
|---------|---------|
| GuardDuty | S3 data events, K8s audit logs, EC2 malware scanning |
| SecurityHub | CIS AWS Foundations v1.4, FSBP v1.0 |
| AWS Config | Continuous recording + 6 managed rules |
| CloudTrail | All management events + S3/Lambda data events, multi-region |
| WAF | Core Rule Set, Known Bad Inputs, SQLi protection, rate limiting (2000 req/5min/IP) |
| Inspector v2 | EC2 vulnerability assessment + ECR image scanning |
| SSM Patch Manager | Weekly patching (Sunday 02:00 UTC), 7-day approval window |

---

## Backup & Disaster Recovery

### Backup Schedule

| Tier | Schedule (UTC) | Retention | Storage Class |
|------|---------------|-----------|--------------|
| Daily | 03:00 AM | 35 days | Standard |
| Weekly | Sunday 04:00 AM | 90 days | Standard |
| Monthly | 1st of month 05:00 AM | 365 days | Cold after 1 day |

### Covered Resources

All resources tagged `BackupPolicy = helixbeat-{env}-daily` are automatically selected:

- EC2 instance root and data volumes (gp3 EBS)
- EKS EBS Persistent Volume Claims
- DocumentDB cluster snapshots
- EFS filesystem (explicit selection in addition to tags)

### Vault Lock (Compliance Mode)

| Setting | Value |
|---------|-------|
| Reconfiguration window | 3 days after vault creation |
| Minimum retention | 35 days — no early deletion |
| Maximum retention | 2555 days (7 years) |
| Mode | Compliance — cannot be overridden even by root |

### Drift Detection

Daily at 06:00 UTC the drift-check workflow runs `terraform plan` on all environments. On drift:

1. Report saved to `s3://{TF_STATE_BUCKET}/drift/{env}/{date}-drift.txt`
2. Jira ticket created (PLAT project, high priority, `terraform-drift` label)
3. Microsoft Teams alert sent to the platform channel

---

## Cost Management

### Infracost Integration

Every pipeline run produces a **resource-level cost diff** showing only resources added or changed in that run (not pre-existing infrastructure).

The cost gate job:
1. Collects per-environment Infracost JSON from plan artifacts
2. Extracts `diff.resources` — only new/changed resources
3. Builds a cost breakdown table per environment
4. Posts a **commit comment** with full per-resource detail
5. Stamps the **GitHub deployment status** so cost appears in the approval popup before any reviewer clicks Approve

### Threshold

A monthly delta exceeding **$500** is highlighted in the commit comment. The pipeline does not auto-block on cost — human reviewers make the final call at the approval gate.

---

## Operations

### Access EC2 Instances (No SSH Required)

```bash
# Start a session via SSM
aws ssm start-session \
  --target <instance-id> \
  --region us-east-1
```

### Access EKS Cluster

```bash
# Add cluster to kubeconfig
aws eks update-kubeconfig \
  --name helixbeat-dev-us \
  --region us-east-1

# Verify
kubectl get nodes -o wide
```

### Manual Terraform Operations

```bash
cd terraform/environments/dev-us

# Initialise with S3 backend
terraform init \
  -backend-config="bucket=${TF_STATE_BUCKET}" \
  -backend-config="key=dev-us/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=${TF_LOCK_TABLE}"

# Plan
terraform plan -out=tfplan

# Apply
terraform apply tfplan

# Destroy (run through pipeline for approval trail)
terraform destroy
```

### Clear a Stuck State Lock

```bash
aws dynamodb delete-item \
  --table-name "${TF_LOCK_TABLE}" \
  --key '{"LockID": {"S": "dev-us/terraform.tfstate-md5"}}' \
  --region us-east-1
```

### Remote State Layout

```
s3://<TF_STATE_BUCKET>/
├── dev-us/terraform.tfstate
├── dev-in/terraform.tfstate
├── staging-us/terraform.tfstate
└── staging-in/terraform.tfstate

DynamoDB table: <TF_LOCK_TABLE>
  Partition key: LockID (String) = "{env}/terraform.tfstate-md5"
```

### Re-enable ACM + ALB in dev-us

Once `us.helixbeat.com` is delegated to the Route53 name servers shown in the public hosted zone:

1. Edit `terraform/environments/dev-us/main.tf`:
   ```hcl
   modules = {
     acm = true
     alb = true
     # ... other modules unchanged
   }
   ```
2. Push to `main` — the pipeline will plan and apply ACM + ALB resources
3. ACM DNS validation completes within ~5 minutes (pipeline timeout is 15 minutes)
