#!/usr/bin/env bash
###############################################################################
# HelixBeat – Deploy Monitoring Stack
# Deploys kube-prometheus-stack, Loki, Promtail, and Grafana to EKS.
#
# Usage:
#   ./scripts/deploy-monitoring.sh <environment> <country> <aws_region>
#
# Examples:
#   ./scripts/deploy-monitoring.sh dev  us us-east-1
#   ./scripts/deploy-monitoring.sh dev  in ap-south-1
###############################################################################

set -euo pipefail

ENVIRONMENT="${1:?Usage: $0 <environment> <country> <aws_region>}"
COUNTRY="${2:?Usage: $0 <environment> <country> <aws_region>}"
AWS_REGION="${3:?Usage: $0 <environment> <country> <aws_region>}"

ENV_DIR="terraform/environments/${ENVIRONMENT}-${COUNTRY}"

echo "==================================================================="
echo " HelixBeat Monitoring Deploy"
echo " Environment : ${ENVIRONMENT}-${COUNTRY}"
echo " Region      : ${AWS_REGION}"
echo "==================================================================="

# ── Kubeconfig ────────────────────────────────────────────────────────────────
CLUSTER_NAME="helixbeat-${ENVIRONMENT}-${COUNTRY}"
echo "[1/6] Updating kubeconfig for cluster ${CLUSTER_NAME}..."
AWS_PROFILE=helixbeat aws eks update-kubeconfig \
  --name "${CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --profile helixbeat
echo "  ✓ kubeconfig updated"

# ── Read Terraform outputs ────────────────────────────────────────────────────
echo "[2/6] Reading Terraform outputs..."
MONITORING_ROLE_ARN=$(cd "${ENV_DIR}" && \
  AWS_PROFILE=helixbeat terraform output -raw monitoring_role_arn 2>/dev/null || \
  echo "arn:aws:iam::PLACEHOLDER:role/placeholder")
LOKI_BUCKET=$(cd "${ENV_DIR}" && \
  AWS_PROFILE=helixbeat terraform output -raw monitoring_bucket_name 2>/dev/null || \
  echo "helixbeat-${ENVIRONMENT}-${COUNTRY}-monitoring")
echo "  ✓ monitoring_role_arn = ${MONITORING_ROLE_ARN}"
echo "  ✓ loki_bucket         = ${LOKI_BUCKET}"

# ── Helm repos ────────────────────────────────────────────────────────────────
echo "[3/6] Adding Helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo add grafana              https://grafana.github.io/helm-charts 2>/dev/null || true
helm repo update
echo "  ✓ Helm repos updated"

# ── kube-prometheus-stack ─────────────────────────────────────────────────────
echo "[4/6] Deploying kube-prometheus-stack..."
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --version ">=55.0.0" \
  --values kubernetes/monitoring/prometheus-values.yaml \
  --set prometheus.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${MONITORING_ROLE_ARN}" \
  --wait --timeout 10m
echo "  ✓ kube-prometheus-stack deployed"

# ── Loki ──────────────────────────────────────────────────────────────────────
echo "[5/6] Deploying Loki + Promtail..."
helm upgrade --install loki grafana/loki \
  --namespace monitoring \
  --values kubernetes/monitoring/loki-values.yaml \
  --set loki.storage.s3.region="${AWS_REGION}" \
  --set loki.storage.bucketNames.chunks="${LOKI_BUCKET}" \
  --set loki.storage.bucketNames.ruler="${LOKI_BUCKET}" \
  --set loki.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${MONITORING_ROLE_ARN}" \
  --wait --timeout 10m

kubectl apply -f kubernetes/monitoring/promtail-daemonset.yaml
echo "  ✓ Loki + Promtail deployed"

# ── Kafka dashboards ──────────────────────────────────────────────────────────
echo "[6/6] Applying Kafka Grafana dashboard..."
kubectl apply -f kubernetes/kafka/grafana-dashboard-kafka.yaml -n monitoring
echo "  ✓ Kafka dashboard applied"

echo ""
echo "==================================================================="
echo " Monitoring deployed!"
echo ""
echo " Get Grafana admin password:"
echo "  kubectl get secret --namespace monitoring kube-prometheus-stack-grafana \\"
echo "    -o jsonpath='{.data.admin-password}' | base64 -d"
echo ""
echo " Port-forward Grafana:"
echo "  kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring"
echo "==================================================================="
