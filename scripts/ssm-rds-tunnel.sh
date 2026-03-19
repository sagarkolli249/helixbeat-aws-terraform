#!/usr/bin/env bash
###############################################################################
# HelixBeat – Secure RDS / DocumentDB Access via SSM Port Forwarding
#
# Slide 5: No SSH keys, no open ports — all access via AWS SSM Session Manager
#
# Usage:
#   ./scripts/ssm-rds-tunnel.sh [env] [db] [local-port]
#
# Examples:
#   ./scripts/ssm-rds-tunnel.sh dev-us docdb 27017
#   ./scripts/ssm-rds-tunnel.sh staging-us postgres 5432
#   ./scripts/ssm-rds-tunnel.sh dev-in mysql 3306
#
# Pre-requisites (install once):
#   brew install awscli session-manager-plugin   # macOS
#   # Or: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html
###############################################################################
set -euo pipefail

ENVIRONMENT="${1:-dev-us}"
DB_TYPE="${2:-docdb}"
LOCAL_PORT="${3:-}"
AWS_PROFILE="${AWS_PROFILE:-helixbeat}"

# ── Resolve region from environment name ──────────────────────────────────────
case "$ENVIRONMENT" in
  *-us)   REGION="us-east-1" ;;
  *-in)   REGION="ap-south-1" ;;
  *-ca)   REGION="ca-central-1" ;;
  *-uk)   REGION="eu-west-2" ;;
  *-au)   REGION="ap-southeast-2" ;;
  *)      echo "Unknown environment: $ENVIRONMENT"; exit 1 ;;
esac

COUNTRY="${ENVIRONMENT##*-}"
ENV_NAME="${ENVIRONMENT%-*}"
NAME_PREFIX="helixbeat-${ENV_NAME}-${COUNTRY}"

# ── Resolve DB endpoint and port ──────────────────────────────────────────────
case "$DB_TYPE" in
  docdb|documentdb|mongo)
    REMOTE_PORT=27017
    LOCAL_PORT="${LOCAL_PORT:-27017}"
    ENDPOINT=$(aws ssm get-parameter \
      --name "/helixbeat/${ENVIRONMENT}/documentdb/endpoint" \
      --with-decryption \
      --query "Parameter.Value" \
      --output text \
      --region "$REGION" \
      --profile "$AWS_PROFILE" 2>/dev/null || echo "")
    if [[ -z "$ENDPOINT" ]]; then
      # Fall back to Terraform output
      ENDPOINT=$(cd terraform/environments/"$ENVIRONMENT" && \
        terraform output -raw documentdb_endpoint 2>/dev/null || echo "")
    fi
    DB_LABEL="DocumentDB (MongoDB 5.0)"
    CONNECTION_STRING="mongodb://helixbeat:<password>@localhost:${LOCAL_PORT}/helixbeat?tls=true&tlsCAFile=rds-combined-ca-bundle.pem"
    ;;
  postgres|postgresql|rds-pg)
    REMOTE_PORT=5432
    LOCAL_PORT="${LOCAL_PORT:-5432}"
    ENDPOINT=$(aws rds describe-db-instances \
      --filters "Name=tag:Name,Values=${NAME_PREFIX}-postgres" \
      --query "DBInstances[0].Endpoint.Address" \
      --output text \
      --region "$REGION" \
      --profile "$AWS_PROFILE" 2>/dev/null || echo "")
    DB_LABEL="RDS PostgreSQL"
    CONNECTION_STRING="postgresql://helixbeat:<password>@localhost:${LOCAL_PORT}/helixbeat"
    ;;
  mysql|rds-mysql)
    REMOTE_PORT=3306
    LOCAL_PORT="${LOCAL_PORT:-3306}"
    ENDPOINT=$(aws rds describe-db-instances \
      --filters "Name=tag:Name,Values=${NAME_PREFIX}-mysql" \
      --query "DBInstances[0].Endpoint.Address" \
      --output text \
      --region "$REGION" \
      --profile "$AWS_PROFILE" 2>/dev/null || echo "")
    DB_LABEL="RDS MySQL"
    CONNECTION_STRING="mysql://helixbeat:<password>@localhost:${LOCAL_PORT}/helixbeat"
    ;;
  *)
    echo "Unknown db type: $DB_TYPE (use: docdb | postgres | mysql)"
    exit 1
    ;;
esac

if [[ -z "$ENDPOINT" || "$ENDPOINT" == "None" ]]; then
  echo "ERROR: Could not resolve endpoint for ${DB_TYPE} in ${ENVIRONMENT}"
  echo "Ensure you are logged into AWS and the environment is deployed."
  exit 1
fi

# ── Find a bastion/jump EC2 instance with SSM agent ──────────────────────────
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters \
    "Name=tag:Name,Values=${NAME_PREFIX}-bastion" \
    "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" \
  --output text \
  --region "$REGION" \
  --profile "$AWS_PROFILE" 2>/dev/null || echo "")

if [[ -z "$INSTANCE_ID" || "$INSTANCE_ID" == "None" ]]; then
  # Try any running instance in the private subnet
  INSTANCE_ID=$(aws ec2 describe-instances \
    --filters \
      "Name=tag:Project,Values=helixbeat" \
      "Name=tag:Environment,Values=${ENV_NAME}" \
      "Name=instance-state-name,Values=running" \
    --query "Reservations[0].Instances[0].InstanceId" \
    --output text \
    --region "$REGION" \
    --profile "$AWS_PROFILE" 2>/dev/null || echo "")
fi

if [[ -z "$INSTANCE_ID" || "$INSTANCE_ID" == "None" ]]; then
  echo "ERROR: No running EC2 instance found in ${ENVIRONMENT} with SSM agent."
  echo "Ensure at least one EC2 instance is running with the SSM agent installed."
  exit 1
fi

# ── Retrieve DB credentials from Secrets Manager ─────────────────────────────
echo ""
echo "🔐 Fetching credentials from Secrets Manager..."
SECRET_ARN=$(aws ssm get-parameter \
  --name "/helixbeat/${ENVIRONMENT}/documentdb/secret-arn" \
  --query "Parameter.Value" --output text \
  --region "$REGION" --profile "$AWS_PROFILE" 2>/dev/null || \
  cd terraform/environments/"$ENVIRONMENT" && \
  terraform output -raw documentdb_secret_arn 2>/dev/null || echo "")

if [[ -n "$SECRET_ARN" && "$SECRET_ARN" != "None" ]]; then
  SECRET=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_ARN" \
    --query "SecretString" --output text \
    --region "$REGION" --profile "$AWS_PROFILE" 2>/dev/null || echo "{}")
  DB_USER=$(echo "$SECRET" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('username','helixbeat'))" 2>/dev/null || echo "helixbeat")
  DB_PASS=$(echo "$SECRET" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('password','<retrieve-from-secrets-manager>'))" 2>/dev/null || echo "<retrieve-from-secrets-manager>")
else
  DB_USER="helixbeat"
  DB_PASS="<retrieve-from-secrets-manager>"
fi

# ── Start SSM port-forwarding session ─────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════"
echo "  HelixBeat Secure DB Tunnel"
echo "────────────────────────────────────────────────────────────"
echo "  Environment : $ENVIRONMENT"
echo "  Database    : $DB_LABEL"
echo "  Remote host : $ENDPOINT:$REMOTE_PORT"
echo "  Local port  : localhost:$LOCAL_PORT"
echo "  Jump host   : $INSTANCE_ID ($REGION)"
echo "  Username    : $DB_USER"
echo "────────────────────────────────────────────────────────────"
echo "  Connect with:"
echo "  ${CONNECTION_STRING//<password>/${DB_PASS}}"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Starting SSM port-forwarding session... (Ctrl+C to stop)"
echo ""

aws ssm start-session \
  --target "$INSTANCE_ID" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"${ENDPOINT}\"],\"portNumber\":[\"${REMOTE_PORT}\"],\"localPortNumber\":[\"${LOCAL_PORT}\"]}" \
  --region "$REGION" \
  --profile "$AWS_PROFILE"
