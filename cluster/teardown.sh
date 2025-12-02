#!/bin/bash
# Teardown script - removes the Kind cluster and all resources

set -e

CLUSTER_NAME="qdrant-cluster"

echo "=== Tearing down Kubernetes cluster ==="

# Kill port-forwards
echo "Stopping port-forwards..."
pkill -f "kubectl port-forward" 2>/dev/null || true

# Delete the Kind cluster
echo "Deleting Kind cluster: $CLUSTER_NAME"
kind delete cluster --name $CLUSTER_NAME 2>/dev/null || true

echo ""
echo "Cluster deleted successfully!"
echo ""
echo "Note: Docker volumes may still exist. To clean up:"
echo "  docker volume prune -f"

