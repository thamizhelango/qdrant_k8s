#!/bin/bash
# Complete Kubernetes Cluster Setup Script
# This script creates a Kind cluster and deploys Qdrant with observability

set -e

# Configuration
CLUSTER_NAME="qdrant-cluster"
QDRANT_NAMESPACE="qdrant"
MONITORING_NAMESPACE="monitoring"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    command -v docker >/dev/null 2>&1 || error "Docker is required but not installed."
    docker ps >/dev/null 2>&1 || error "Docker is not running."
    
    # Install kind if not present
    if ! command -v kind >/dev/null 2>&1; then
        log "Installing kind..."
        curl -Lo ~/bin/kind https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64
        chmod +x ~/bin/kind
    fi
    
    # Install kubectl if not present
    if ! command -v kubectl >/dev/null 2>&1; then
        log "Installing kubectl..."
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        chmod +x kubectl && mv kubectl ~/bin/
    fi
    
    # Install helm if not present
    if ! command -v helm >/dev/null 2>&1; then
        log "Installing helm..."
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | HELM_INSTALL_DIR=~/bin USE_SUDO=false bash
    fi
    
    export PATH="$HOME/bin:$PATH"
    log "Prerequisites OK"
}

# Create Kind cluster
create_cluster() {
    log "Creating Kind cluster: $CLUSTER_NAME"
    
    # Delete existing cluster if present
    kind delete cluster --name $CLUSTER_NAME 2>/dev/null || true
    
    # Create new cluster
    kind create cluster --config kind-config.yaml
    
    # Wait for cluster to be ready
    kubectl wait --for=condition=Ready nodes --all --timeout=120s
    
    log "Cluster created successfully"
}

# Deploy Qdrant
deploy_qdrant() {
    log "Deploying Qdrant..."
    
    # Add Helm repo
    helm repo add qdrant https://qdrant.to/helm
    helm repo update
    
    # Create namespace
    kubectl create namespace $QDRANT_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy Qdrant using local development values
    helm upgrade --install qdrant qdrant/qdrant \
        --namespace $QDRANT_NAMESPACE \
        --values values-local.yaml \
        --wait --timeout 5m
    
    log "Qdrant deployed successfully"
}

# Deploy observability stack
deploy_observability() {
    log "Deploying observability stack..."
    
    # Add Prometheus Helm repo
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    
    # Create namespace
    kubectl create namespace $MONITORING_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    
    # Apply Qdrant dashboard ConfigMap
    kubectl apply -f ../observability/qdrant-dashboard.yaml
    
    # Deploy Prometheus stack
    helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
        --namespace $MONITORING_NAMESPACE \
        --values ../observability/prometheus-values.yaml \
        --set prometheus.prometheusSpec.resources.requests.memory=256Mi \
        --set grafana.resources.requests.memory=128Mi \
        --timeout 8m
    
    # Apply Qdrant ServiceMonitor
    kubectl apply -f ../observability/qdrant-servicemonitor.yaml
    
    # Patch services for NodePort access
    kubectl patch svc prometheus-grafana -n $MONITORING_NAMESPACE -p '{"spec": {"type": "NodePort"}}'
    kubectl patch svc prometheus-kube-prometheus-prometheus -n $MONITORING_NAMESPACE -p '{"spec": {"type": "NodePort"}}'
    
    log "Observability stack deployed successfully"
}

# Print access information
print_access_info() {
    echo ""
    echo "=============================================="
    echo "  Kubernetes Cluster Setup Complete!"
    echo "=============================================="
    echo ""
    echo "Access URLs:"
    echo "  Qdrant REST API:  http://localhost:16333"
    echo "  Qdrant gRPC:      localhost:16334"
    echo "  Qdrant Dashboard: http://localhost:16333/dashboard"
    echo "  Grafana:          http://localhost:3000"
    echo "  Prometheus:       http://localhost:9090"
    echo ""
    echo "Grafana Credentials:"
    echo "  Username: admin"
    echo "  Password: admin123"
    echo ""
    echo "Useful Commands:"
    echo "  kubectl get pods -A"
    echo "  kubectl logs -n qdrant qdrant-0"
    echo "  kind delete cluster --name $CLUSTER_NAME"
    echo ""
}

# Start port-forwards (for services not exposed via NodePort)
start_port_forwards() {
    log "Starting port-forwards..."
    
    # Kill existing port-forwards
    pkill -f "kubectl port-forward" 2>/dev/null || true
    sleep 2
    
    # Start port-forwards in background
    kubectl port-forward svc/prometheus-grafana -n $MONITORING_NAMESPACE 3000:80 --address 0.0.0.0 &
    kubectl port-forward svc/prometheus-kube-prometheus-prometheus -n $MONITORING_NAMESPACE 9090:9090 --address 0.0.0.0 &
    
    sleep 3
    log "Port-forwards started"
}

# Main execution
main() {
    cd "$(dirname "$0")"
    
    check_prerequisites
    create_cluster
    deploy_qdrant
    deploy_observability
    start_port_forwards
    print_access_info
}

main "$@"

