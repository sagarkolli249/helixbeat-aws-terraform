# HelixBeat – Kubernetes Cluster Access Guide

## Cluster Inventory

| Cluster | Region | AWS Region | Purpose |
|---------|--------|------------|---------|
| `helixbeat-dev-in` | India – Dev | `ap-south-1` (Mumbai) | Development workloads (primary) |
| `helixbeat-dev-us` | US – Dev | `us-east-1` (Virginia) | Development workloads (US region) |
| `helixbeat-staging-in` | India – Staging | `ap-south-1` (Mumbai) | Staging / pre-prod (primary) |
| `helixbeat-staging-us` | US – Staging | `us-east-1` (Virginia) | Staging / pre-prod (US region) |

> **Private cluster:** All EKS API endpoints are `endpoint_public_access = false`.
> The Kubernetes API server is reachable **only from within the VPC**.
> Direct `kubectl` from a laptop requires SSM port forwarding (covered below).

---

## Prerequisites

Install the following tools before attempting cluster access.

```bash
# 1. AWS CLI v2
brew install awscli                     # macOS
# or: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html

# 2. kubectl (match or be within 1 minor version of cluster – currently 1.29)
brew install kubectl
kubectl version --client

# 3. AWS Session Manager Plugin (required for SSM port forwarding)
brew install --cask session-manager-plugin
session-manager-plugin --version

# 4. Verify AWS credentials are configured
aws sts get-caller-identity
```

**AWS profile setup** – use a named profile scoped to the HelixBeat account:

```ini
# ~/.aws/config
[profile helixbeat]
sso_start_url  = https://helixbeat.awsapps.com/start
sso_region     = ap-south-1
sso_account_id = <AWS_ACCOUNT_ID>
sso_role_name  = HelixBeatPlatformAccess
region         = ap-south-1
output         = json
```

```bash
aws sso login --profile helixbeat
```

---

## Step 1 – Configure kubeconfig

Run the command below for each cluster you need to access. It writes a context to `~/.kube/config`.

```bash
# India – Dev
aws eks update-kubeconfig \
  --name helixbeat-dev-in \
  --region ap-south-1 \
  --profile helixbeat \
  --alias dev-in

# India – Staging
aws eks update-kubeconfig \
  --name helixbeat-staging-in \
  --region ap-south-1 \
  --profile helixbeat \
  --alias staging-in

# US – Dev
aws eks update-kubeconfig \
  --name helixbeat-dev-us \
  --region us-east-1 \
  --profile helixbeat \
  --alias dev-us

# US – Staging
aws eks update-kubeconfig \
  --name helixbeat-staging-us \
  --region us-east-1 \
  --profile helixbeat \
  --alias staging-us
```

Switch between clusters:

```bash
kubectl config use-context dev-in
kubectl config get-contexts          # list all contexts
kubectl config current-context       # show active context
```

---

## Step 2 – Private Endpoint Access via SSM Port Forwarding

Because the API server is private, `kubectl` will time out unless you tunnel through SSM.

### Option A – SSM port-forward through an EKS node (recommended for local dev)

```bash
# 1. Find a running node in the target cluster
CLUSTER=helixbeat-dev-in
REGION=ap-south-1

NODE_INSTANCE_ID=$(aws ec2 describe-instances \
  --region $REGION \
  --profile helixbeat \
  --filters \
    "Name=tag:aws:eks:cluster-name,Values=${CLUSTER}" \
    "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" \
  --output text)

echo "Node instance: $NODE_INSTANCE_ID"

# 2. Get the private API server hostname
API_SERVER=$(aws eks describe-cluster \
  --name $CLUSTER \
  --region $REGION \
  --profile helixbeat \
  --query "cluster.endpoint" \
  --output text | sed 's|https://||')

echo "API server: $API_SERVER"

# 3. Open the SSM tunnel (keep this terminal open)
aws ssm start-session \
  --target $NODE_INSTANCE_ID \
  --region $REGION \
  --profile helixbeat \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"${API_SERVER}\"],\"portNumber\":[\"443\"],\"localPortNumber\":[\"6443\"]}"
```

```bash
# 4. In a NEW terminal — patch kubeconfig to use the tunnel
kubectl config set-cluster dev-in \
  --server=https://127.0.0.1:6443 \
  --insecure-skip-tls-verify=true

# 5. Test
kubectl get nodes --context dev-in
```

> Restore the original server URL after your session:
> ```bash
> aws eks update-kubeconfig --name helixbeat-dev-in --region ap-south-1 --profile helixbeat --alias dev-in
> ```

### Option B – AWS CloudShell or EC2 jump box inside the VPC

If your team has an EC2 instance or Cloud9 environment inside the VPC, SSH or SSM into it and run `kubectl` directly — no port forwarding needed.

```bash
# On the jump box / Cloud9
aws eks update-kubeconfig --name helixbeat-dev-in --region ap-south-1
kubectl get nodes
```

### Option C – VPN

If a VPN is connected to the VPC (AWS Client VPN or Site-to-Site VPN), `kubectl` works directly once the kubeconfig is configured — no tunnelling required.

---

## Step 3 – Verify Access

```bash
# Nodes (should show 2 node groups: system + app)
kubectl get nodes -o wide --context dev-in

# Example output:
# NAME                         STATUS   ROLES    AGE   VERSION   LABELS
# ip-10-20-x-x.ap-south-1...  Ready    <none>   1d    v1.29.x   role=system,region=india
# ip-10-20-x-x.ap-south-1...  Ready    <none>   1d    v1.29.x   role=app,region=india

# All namespaces
kubectl get namespaces --context dev-in

# System components
kubectl get pods -n kube-system --context dev-in
```

---

## Node Pool Reference

Each cluster has two managed node groups:

| Node Group | Label | Taint | Purpose |
|------------|-------|-------|---------|
| `{cluster}-system` | `role=system`, `region=india\|us` | `dedicated=system:NoSchedule` | CoreDNS, monitoring, ALB controller, cluster-internal services |
| `{cluster}-app` | `role=app`, `region=india\|us` | — | Application workloads |

### Scheduling workloads on specific node pools

```yaml
# Schedule on app nodes (most workloads)
spec:
  nodeSelector:
    role: app
    region: india      # or: region: us

# Schedule on system nodes (cluster infrastructure only)
spec:
  nodeSelector:
    role: system
    region: india
  tolerations:
    - key: dedicated
      value: system
      effect: NoSchedule
```

### Node sizes by environment

| Environment | System Nodes | App Nodes |
|-------------|-------------|-----------|
| dev-in | `m5.large` × 2 | `m5.large` × 1 (scales to 5) |
| dev-us | `m5.large` × 2 | `m5.large` × 1 (scales to 5) |
| staging-in | `m5.large` × 2–4 | `m5.xlarge` × 2 (scales to 8) |
| staging-us | `m5.large` × 2–4 | `m5.xlarge` × 2 (scales to 8) |

---

## IAM Access Control

EKS uses **IAM → Kubernetes RBAC** mapping via the `aws-auth` ConfigMap.

### View current IAM mappings

```bash
kubectl get configmap aws-auth -n kube-system -o yaml --context dev-in
```

### Add a new IAM user or role

```bash
kubectl edit configmap aws-auth -n kube-system --context dev-in
```

```yaml
# Add under mapRoles:
- rolearn: arn:aws:iam::<ACCOUNT_ID>:role/HelixBeatDeveloper
  username: developer
  groups:
    - system:masters          # full admin — use sparingly
    # or: helixbeat-developers  # custom group with limited RBAC
```

### Common IAM roles that need cluster access

| Role | Access Level | Usage |
|------|-------------|-------|
| `AWS_TF_ROLE_ARN` | `system:masters` | Terraform pipeline — creates cluster resources |
| `AWS_CI_ROLE_ARN` | `system:masters` | Product release pipeline — deploys app |
| `HelixBeatPlatformAccess` | `system:masters` | Platform engineers |
| `HelixBeatDeveloper` | Custom RBAC | Developers — read-only or namespace-scoped |

---

## Useful kubectl Commands

```bash
# --- Cluster health ---
kubectl get componentstatuses --context dev-in
kubectl top nodes --context dev-in
kubectl top pods -A --context dev-in

# --- Workloads ---
kubectl get deployments -A --context dev-in
kubectl get pods -A --context dev-in
kubectl describe pod <pod-name> -n <namespace> --context dev-in

# --- Logs ---
kubectl logs <pod-name> -n <namespace> --context dev-in
kubectl logs <pod-name> -n <namespace> --context dev-in --previous   # crashed container
kubectl logs -l app=helixbeat -n helixbeat --context dev-in --tail=100

# --- Exec into a pod ---
kubectl exec -it <pod-name> -n <namespace> --context dev-in -- /bin/sh

# --- Helm releases ---
helm list -A --kube-context dev-in

# --- Events (useful for debugging) ---
kubectl get events -A --sort-by='.lastTimestamp' --context dev-in

# --- Scale a deployment ---
kubectl scale deployment <name> --replicas=0 -n <namespace> --context dev-in
```

---

## ECR – Container Registry Access

Each cluster has its own ECR repositories under the cluster prefix.

```bash
# Login to ECR (India)
aws ecr get-login-password --region ap-south-1 --profile helixbeat | \
  docker login --username AWS --password-stdin \
  <ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com

# List repositories for dev-in cluster
aws ecr describe-repositories \
  --region ap-south-1 \
  --profile helixbeat \
  --query "repositories[?starts_with(repositoryName, 'helixbeat-dev-in')].repositoryName"
```

Default repositories per cluster:
- `{cluster}/helixbeat-api`
- `{cluster}/helixbeat-worker`
- `{cluster}/helixbeat-frontend`

---

## Cluster Logs – CloudWatch

All control-plane logs (API server, audit, scheduler, etc.) are shipped to CloudWatch.

```
Log group: /aws/eks/{cluster-name}/cluster
Retention:  90 days
```

```bash
# Tail API server logs for dev-in
aws logs tail /aws/eks/helixbeat-dev-in/cluster \
  --filter-pattern "{ $.kind = \"Event\" }" \
  --follow \
  --region ap-south-1 \
  --profile helixbeat
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `kubectl` times out | Private endpoint — no VPN/tunnel | Set up SSM port-forward (Step 2) |
| `error: You must be logged in to the server (Unauthorized)` | AWS credentials expired or wrong profile | `aws sso login --profile helixbeat` |
| `error: the server doesn't have a resource type "nodes"` | Wrong context active | `kubectl config use-context dev-in` |
| Node in `NotReady` state | Node may be bootstrapping or unhealthy | `kubectl describe node <name>` → check Events |
| `exec /bin/sh: exec format error` | Wrong container architecture | Check image arch matches `AL2_x86_64` nodes |
| Pod stuck in `Pending` | No schedulable nodes / taint mismatch | Check `kubectl describe pod` → Events section |

---

## Quick Reference – Terraform Outputs

After `terraform apply`, get cluster details directly:

```bash
# India – Dev
cd terraform/environments/dev-in
terraform output cluster_name          # helixbeat-dev-in
terraform output kubeconfig_command    # full aws eks update-kubeconfig command
terraform output -json ecr_repository_urls

# India – Staging
cd terraform/environments/staging-in
terraform output cluster_name          # helixbeat-staging-in
terraform output kubeconfig_command
```
