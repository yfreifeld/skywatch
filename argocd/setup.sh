#!/usr/bin/env bash
# Week 3: Install ArgoCD and configure the SkyWatch application.
# Run from your laptop with KUBECONFIG pointing at the cluster.
set -euo pipefail

ARGOCD_VERSION="v2.11.2"
ARGOCD_NAMESPACE="argocd"
APP_MANIFEST="$(dirname "$0")/application.yaml"

echo "==> Installing ArgoCD ${ARGOCD_VERSION}..."
kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n "${ARGOCD_NAMESPACE}" \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "==> Waiting for ArgoCD server to be ready..."
kubectl rollout status deployment/argocd-server -n "${ARGOCD_NAMESPACE}" --timeout=180s

echo "==> Patching ArgoCD service to NodePort 30081..."
kubectl patch svc argocd-server -n "${ARGOCD_NAMESPACE}" \
  --type='json' \
  -p='[{"op":"replace","path":"/spec/type","value":"NodePort"},
       {"op":"add","path":"/spec/ports/0/nodePort","value":30081}]'

echo "==> Getting initial admin password..."
ARGOCD_PASSWORD=$(kubectl -n "${ARGOCD_NAMESPACE}" \
  get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
echo "    Username: admin"
echo "    Password: ${ARGOCD_PASSWORD}"

echo "==> Applying SkyWatch Application manifest..."
# Replace placeholder with actual repo URL first
if grep -q "GITHUB_USERNAME" "${APP_MANIFEST}"; then
  echo "ERROR: Edit argocd/application.yaml and replace GITHUB_USERNAME with your GitHub username."
  exit 1
fi
kubectl apply -f "${APP_MANIFEST}"

echo ""
echo "Done! ArgoCD is running."
echo "Access at: http://<MASTER_IP>:30081"
echo "Login: admin / ${ARGOCD_PASSWORD}"
