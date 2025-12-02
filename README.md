# Qdrant on Kubernetes

Complete Kubernetes setup for Qdrant vector database with observability stack (Prometheus + Grafana).

## Directory Structure

```
qdrant/
├── README.md                 # This file
├── values.yaml               # Production Helm values
├── deploy.sh                 # Production deployment script
├── cluster/                  # Local Kind cluster setup
│   ├── kind-config.yaml      # Kind cluster configuration
│   ├── values-local.yaml     # Local development Helm values
│   ├── setup.sh              # Complete cluster setup script
│   └── teardown.sh           # Cluster teardown script
└── observability/            # Monitoring stack
    ├── prometheus-values.yaml    # Prometheus + Grafana config
    ├── qdrant-servicemonitor.yaml # Qdrant scraping config
    └── qdrant-dashboard.yaml      # Grafana dashboard
```

## Quick Start

### Prerequisites

- Docker installed and running
- 8GB+ RAM available
- Ports 16333, 16334, 3000, 9090 available

### Setup Local Cluster

```bash
# Make scripts executable
chmod +x cluster/setup.sh cluster/teardown.sh

# Create cluster and deploy everything
cd cluster
./setup.sh
```

### Manual Setup

```bash
# 1. Install tools (if not present)
mkdir -p ~/bin
export PATH="$HOME/bin:$PATH"

# Install kind
curl -Lo ~/bin/kind https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64
chmod +x ~/bin/kind

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && mv kubectl ~/bin/

# Install helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | HELM_INSTALL_DIR=~/bin USE_SUDO=false bash

# 2. Create Kind cluster
kind create cluster --config cluster/kind-config.yaml

# 3. Deploy Qdrant
helm repo add qdrant https://qdrant.to/helm
helm repo update
kubectl create namespace qdrant
helm install qdrant qdrant/qdrant \
  --namespace qdrant \
  --values cluster/values-local.yaml

# 4. Deploy Observability
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
kubectl create namespace monitoring
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values observability/prometheus-values.yaml

# 5. Apply Qdrant monitoring
kubectl apply -f observability/qdrant-dashboard.yaml
kubectl apply -f observability/qdrant-servicemonitor.yaml
```

## Access URLs

| Service | URL | Credentials |
|---------|-----|-------------|
| Qdrant REST API | http://localhost:16333 | - |
| Qdrant gRPC | localhost:16334 | - |
| Qdrant Dashboard | http://localhost:16333/dashboard | - |
| Grafana | http://localhost:3000 | admin / admin123 |
| Prometheus | http://localhost:9090 | - |

## Port Forwarding (if NodePort not working)

```bash
# Qdrant
kubectl port-forward svc/qdrant -n qdrant 16333:6333 --address 0.0.0.0 &

# Grafana
kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80 --address 0.0.0.0 &

# Prometheus
kubectl port-forward svc/prometheus-kube-prometheus-prometheus -n monitoring 9090:9090 --address 0.0.0.0 &
```

## Usage Examples

### Create a Collection

```bash
curl -X PUT http://localhost:16333/collections/my_collection \
  -H "Content-Type: application/json" \
  -d '{
    "vectors": {
      "size": 384,
      "distance": "Cosine"
    }
  }'
```

### Insert Vectors

```bash
curl -X PUT http://localhost:16333/collections/my_collection/points \
  -H "Content-Type: application/json" \
  -d '{
    "points": [
      {"id": 1, "vector": [0.1, 0.2, ...], "payload": {"name": "item1"}},
      {"id": 2, "vector": [0.3, 0.4, ...], "payload": {"name": "item2"}}
    ]
  }'
```

### Search Vectors

```bash
curl -X POST http://localhost:16333/collections/my_collection/points/search \
  -H "Content-Type: application/json" \
  -d '{
    "vector": [0.1, 0.2, ...],
    "limit": 5,
    "with_payload": true
  }'
```

## Useful Commands

```bash
# Check pods
kubectl get pods -A

# View Qdrant logs
kubectl logs -n qdrant qdrant-0 -f

# Check Qdrant status
curl http://localhost:16333/collections

# Check Prometheus targets
curl http://localhost:9090/api/v1/targets

# Delete cluster
kind delete cluster --name qdrant-cluster
```

## Data Location

Data is stored inside the Kind container at:
```
/var/local-path-provisioner/
```

To access on host:
```bash
docker exec -it qdrant-cluster-control-plane ls /var/local-path-provisioner/
```

## Cleanup

```bash
# Delete cluster
cd cluster
./teardown.sh

# Or manually
kind delete cluster --name qdrant-cluster

# Clean up Docker volumes
docker volume prune -f
```

## Production Deployment

For production, use the files in the root directory:

```bash
# Use production values
helm install qdrant qdrant/qdrant \
  --namespace qdrant \
  --values values.yaml \
  --set apiKey=<your-api-key>
```

## Troubleshooting

### Port already in use
```bash
# Find and kill process using the port
sudo lsof -i :16333
sudo kill <PID>
```

### Pods not starting
```bash
# Check events
kubectl get events -n qdrant --sort-by='.lastTimestamp'

# Check pod details
kubectl describe pod qdrant-0 -n qdrant
```

### No metrics in Grafana
```bash
# Check ServiceMonitor
kubectl get servicemonitor -n monitoring

# Check Prometheus targets
curl http://localhost:9090/api/v1/targets | grep qdrant
```

