# HelixBeat GitHub Actions – Required Secrets

Set these in **GitHub → Settings → Secrets and variables → Actions → Repository secrets**.

## AWS (OIDC / Passwordless)

| Secret | Description |
|--------|-------------|
| `AWS_ACCOUNT_ID` | AWS Account ID (12-digit) |
| `AWS_REGION` | Default region (e.g. `us-east-1`) |
| `AWS_CI_ROLE_ARN` | IAM role for CI (build/scan/push to ECR) |
| `AWS_DEPLOY_ROLE_ARN` | IAM role for staging deployments |
| `AWS_DEPLOY_ROLE_ARN_PROD` | IAM role for production deployments |
| `AWS_TF_ROLE_ARN` | IAM role for Terraform plan/apply |
| `TF_STATE_BUCKET` | S3 bucket name for Terraform state + plans |
| `ALB_ARN_PROD` | ALB full ARN for CloudWatch 5xx error metric |

## ArgoCD

| Secret | Description |
|--------|-------------|
| `ARGOCD_SERVER` | ArgoCD server URL (staging, e.g. `argocd.internal.helixbeat.com`) |
| `ARGOCD_SERVER_PROD` | ArgoCD server URL (prod) |
| `ARGOCD_TOKEN` | ArgoCD API token (staging) |
| `ARGOCD_TOKEN_PROD` | ArgoCD API token (prod) |

## Jira

| Secret | Description |
|--------|-------------|
| `JIRA_BASE_URL` | e.g. `https://helixbeat.atlassian.net` |
| `JIRA_API_TOKEN` | Jira API token (generate at id.atlassian.com) |
| `JIRA_USER_EMAIL` | Email of the Jira service account |

## Security Scanning

| Secret | Description |
|--------|-------------|
| `SNYK_TOKEN` | Snyk API token |
| `INFRACOST_API_KEY` | Infracost API key (free at infracost.io) |

## Confluence / Documentation

| Secret | Description |
|--------|-------------|
| `CONFLUENCE_BASE_URL` | e.g. `https://helixbeat.atlassian.net/wiki` |
| `CONFLUENCE_API_TOKEN` | Confluence API token |
| `CONFLUENCE_USER_EMAIL` | Email of the Confluence service account |

## Notifications

| Secret | Description |
|--------|-------------|
| `TEAMS_WEBHOOK` | Microsoft Teams webhook for general alerts |
| `TEAMS_RELEASES_WEBHOOK` | Teams webhook for the #releases channel |

## GitHub Environments

Create these in **Settings → Environments** with required reviewers:

| Environment | Required Reviewers | Purpose |
|-------------|-------------------|---------|
| `staging` | Platform team | Auto-approve staging deploys |
| `production` | 2× Platform leads | Manual gate before prod deploy |
| `terraform-dev-us` | Platform lead | TF apply gate for dev-us |
| `terraform-dev-in` | Platform lead | TF apply gate for dev-in |
| `terraform-staging-us` | 2× reviewers | TF apply gate for staging-us |
| `terraform-staging-in` | 2× reviewers | TF apply gate for staging-in |

## AWS OIDC Setup (one-time)

```bash
# Create OIDC identity provider for GitHub Actions
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

# Then create IAM roles with trust policy:
# Principal: { "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com" }
# Condition: StringEquals "token.actions.githubusercontent.com:sub": "repo:helixbeat/*:ref:refs/heads/main"
```
