# HelixBeat AWS Infrastructure – Architecture Guide

## Overview

HelixBeat runs on a hardened, multi-AZ AWS EKS infrastructure with full monitoring (Prometheus + Grafana + Loki) and automated security guardrails.

---

## Infrastructure Layout

```
AWS Account
├── us-east-1
│   ├── VPC (10.x.0.0/16)
│   │   ├── Public Subnets (NAT GW + ALB only)  ×3 AZs
│   │   ├── Private Subnets (EKS nodes)          ×3 AZs
│   │   └── VPC Endpoints (ECR, S3, SSM, STS, CW, ELB...)
│   │
│   ├── EKS Cluster (private endpoint only)
│   │   ├── System Node Group  (m5.large)   – monitoring, CoreDNS, controllers
│   │   └── App Node Group     (m5.xlarge)  – application workloads
│   │
│   ├── Security Services
│   │   ├── GuardDuty (threat detection)
│   │   ├── SecurityHub + CIS Benchmark
│   │   ├── CloudTrail (all regions, encrypted)
│   │   ├── AWS Config (30+ compliance rules)
│   │   └── WAFv2 (CRS + SQLi + rate-limit rules)
│   │
│   └── Monitoring (in-cluster, monitoring namespace)
│       ├── Prometheus (kube-prometheus-stack)
│       ├── AlertManager
│       ├── Grafana (pre-loaded dashboards)
│       ├── Loki (SimpleScalable, S3 backend)
│       └── Promtail (DaemonSet log shipper)
```

---

## Directory Structure

```
helixbeat/
├── terraform/
│   ├── modules/
│   │   ├── vpc/          – VPC, subnets, NAT, VPC endpoints, flow logs
│   │   ├── eks/          – EKS cluster, node groups, ECR, KMS
│   │   ├── security/     – GuardDuty, WAF, CloudTrail, Config, SecurityHub
│   │   └── iam/          – IRSA roles, monitoring S3 bucket, password policy
│   └── environments/
│       ├── dev/          – Dev environment (smaller nodes, 10.10.0.0/16)
│       └── staging/      – Staging environment (prod-like sizing, 10.20.0.0/16)
│
├── kubernetes/
│   ├── monitoring/
│   │   ├── namespace.yaml
│   │   ├── prometheus/values.yaml     – kube-prometheus-stack
│   │   ├── grafana/values.yaml        – Grafana + pre-built dashboards
│   │   └── loki/
│   │       ├── values.yaml            – Loki SimpleScalable
│   │       └── promtail-values.yaml   – Promtail DaemonSet
│   └── security/
│       ├── network-policies.yaml      – Default-deny + explicit allows
│       └── pod-security-standards.yaml – PSS, RBAC, ResourceQuota, gp3 SC
│
├── scripts/
│   ├── bootstrap.sh                   – Create remote state infra
│   └── deploy-monitoring.sh           – Helm deploy the monitoring stack
│
└── docs/
    └── architecture.md                – This file
```

---

## Getting Started

### Prerequisites

| Tool       | Version  | Install |
|------------|----------|---------|
| Terraform  | ≥ 1.6    | https://developer.hashicorp.com/terraform/install |
| AWS CLI    | ≥ 2.x    | https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html |
| kubectl    | ≥ 1.29   | https://kubernetes.io/docs/tasks/tools/ |
| Helm       | ≥ 3.14   | https://helm.sh/docs/intro/install/ |

### Step 1 – Bootstrap Terraform state

```bash
# Create S3 bucket + DynamoDB lock table + enable GuardDuty
./scripts/bootstrap.sh dev us-east-1
./scripts/bootstrap.sh staging us-east-1
```

### Step 2 – Configure variables

Edit `terraform/environments/<env>/terraform.tfvars`:
- Set your `aws_region`
- Add `alert_email_addresses` for security notifications
- Adjust node sizes if needed

### Step 3 – Deploy infrastructure

```bash
cd terraform/environments/dev
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### Step 4 – Deploy monitoring stack

```bash
./scripts/deploy-monitoring.sh dev us-east-1
```

### Step 5 – Access Grafana

```bash
# Port-forward (works even with private endpoint)
kubectl port-forward svc/grafana 3000:80 -n monitoring
open http://localhost:3000
```

---

## Security Controls

| Control | Implementation |
|---------|---------------|
| Network isolation | VPC private subnets, no public node IPs, default-deny SGs |
| EKS API access | Private endpoint only (no public access) |
| Secret encryption | KMS envelope encryption on all EKS Secrets |
| Node access | SSM Session Manager only (no SSH, no bastion) |
| Container images | ECR with immutable tags + scan-on-push |
| Pod security | Kubernetes restricted Pod Security Standards |
| Network policies | Default-deny + explicit allow rules per namespace |
| Audit logging | CloudTrail multi-region + EKS control-plane logs |
| Threat detection | GuardDuty with K8s audit logs, EBS malware scan |
| Compliance rules | AWS Config with 6+ managed rules (CIS aligned) |
| WAF | CRS + known-bad-inputs + SQLi + rate limiting |
| Security posture | SecurityHub + CIS Benchmark + AWS Best Practices |

---

## Monitoring Stack

### Prometheus
- Deployed via `kube-prometheus-stack`
- 2 replicas, 15d retention, 50Gi PVC per replica
- All cluster metrics auto-scraped (nodes, pods, deployments, PVCs)
- AlertManager with configurable Slack/email receivers

### Grafana
- 2 replicas with persisted dashboards
- Pre-loaded dashboards: Kubernetes cluster, Node Exporter, Pods, Loki logs
- IRSA-authenticated – no static credentials

### Loki
- SimpleScalable mode (read/write/backend components)
- S3 backend (long-term storage in encrypted bucket)
- 31-day log retention
- Promtail DaemonSet ships logs from all nodes

---

## Updating IRSA Role ARNs Post-Deploy

After `terraform apply`, patch the role ARNs in your Helm values or run `deploy-monitoring.sh` which handles this automatically:

```bash
# Get the role ARN
terraform -chdir=terraform/environments/dev output monitoring_role_arn

# Update prometheus service account annotation
kubectl annotate serviceaccount prometheus \
  -n monitoring \
  eks.amazonaws.com/role-arn=<ARN> \
  --overwrite
```

---

## Cost Estimates (approximate, us-east-1)

| Resource | Dev/month | Staging/month |
|----------|-----------|---------------|
| EKS Control Plane | $73 | $73 |
| EC2 nodes (m5.large ×3) | ~$210 | ~$420 |
| NAT Gateways (×3) | ~$100 | ~$100 |
| VPC Interface Endpoints | ~$70 | ~$70 |
| S3 (state + logs + monitoring) | ~$10 | ~$15 |
| GuardDuty | ~$10 | ~$15 |
| **Total estimate** | **~$473** | **~$693** |

> Costs vary by traffic and storage usage. Enable AWS Cost Explorer for actuals.
