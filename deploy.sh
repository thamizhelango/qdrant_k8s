#!/bin/bash
# Qdrant Kubernetes Deployment Script
# Production-ready setup with Helm

set -e

NAMESPACE="qdrant"
RELEASE_NAME="qdrant"
API_KEY="${QDRANT_API_KEY:-$(openssl rand -base64 32)}"

echo "=== Qdrant Kubernetes Deployment ==="
echo ""

# Create namespace if it doesn't exist
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Add Qdrant Helm repository
echo "[1/4] Adding Qdrant Helm repository..."
helm repo add qdrant https://qdrant.to/helm
helm repo update

# Create secret for API key
echo "[2/4] Creating API key secret..."
kubectl create secret generic qdrant-api-key \
  --from-literal=api-key="$API_KEY" \
  --namespace $NAMESPACE \
  --dry-run=client -o yaml | kubectl apply -f -

# Deploy Qdrant
echo "[3/4] Deploying Qdrant cluster..."
helm upgrade --install $RELEASE_NAME qdrant/qdrant \
  --namespace $NAMESPACE \
  --values values.yaml \
  --set apiKey="$API_KEY" \
  --wait \
  --timeout 10m

# Wait for pods to be ready
echo "[4/4] Waiting for pods to be ready..."
kubectl rollout status statefulset/$RELEASE_NAME -n $NAMESPACE --timeout=5m

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Qdrant cluster deployed successfully!"
echo ""
echo "API Key: $API_KEY"
echo "(Save this key securely - you'll need it to access Qdrant)"
echo ""
echo "To access Qdrant locally:"
echo "  kubectl port-forward svc/$RELEASE_NAME 6333:6333 6334:6334 -n $NAMESPACE"
echo ""
echo "Then connect to:"
echo "  REST API: http://localhost:6333"
echo "  gRPC:     localhost:6334"
echo ""
echo "Health check:"
echo "  curl http://localhost:6333/healthz"
echo ""

