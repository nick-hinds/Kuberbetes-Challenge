#!/bin/bash

set -e

echo "=========================================="
echo "Multi-Tier K8s Application Deployment"
echo "=========================================="
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed. Please install kubectl first."
    exit 1
fi

# Check if cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster. Please ensure your cluster is running."
    echo ""
    echo "For minikube: minikube start"
    echo "For kind: kind create cluster --name multi-tier-app"
    exit 1
fi

print_info "Connected to Kubernetes cluster"
kubectl cluster-info | head -n 1

echo ""
print_info "Deploying application components..."
echo ""

# Deploy in order
MANIFESTS=(
    "00-namespace.yaml"
    "01-configmap.yaml"
    "02-secrets.yaml"
    "03-redis.yaml"
    "04-backend.yaml"
    "05-frontend.yaml"
    "06-hpa.yaml"
    "07-network-policies.yaml"
    "08-pdb.yaml"
)

for manifest in "${MANIFESTS[@]}"; do
    print_info "Applying $manifest..."
    kubectl apply -f "manifests/$manifest"
    sleep 2
done

echo ""
print_info "Waiting for deployments to be ready..."
echo ""

# Wait for deployments
kubectl wait --for=condition=ready pod -l app=redis -n multi-tier-app --timeout=120s
print_info "✓ Redis is ready"

kubectl wait --for=condition=ready pod -l app=backend -n multi-tier-app --timeout=120s
print_info "✓ Backend is ready"

kubectl wait --for=condition=ready pod -l app=frontend -n multi-tier-app --timeout=120s
print_info "✓ Frontend is ready"

echo ""
print_info "Deployment completed successfully!"
echo ""

# Get service information
echo "=========================================="
echo "Service Information"
echo "=========================================="
echo ""

kubectl get svc -n multi-tier-app

echo ""
echo "=========================================="
echo "Pod Status"
echo "=========================================="
echo ""

kubectl get pods -n multi-tier-app -o wide

echo ""
echo "=========================================="
echo "HPA Status"
echo "=========================================="
echo ""

kubectl get hpa -n multi-tier-app

echo ""
echo "=========================================="
echo "Access Instructions"
echo "=========================================="
echo ""

# Detect cluster type and provide appropriate access instructions
if kubectl config current-context | grep -q "minikube"; then
    print_info "Detected minikube cluster"
    echo ""
    echo "To access the application, run:"
    echo "  minikube service frontend-service -n multi-tier-app"
    echo ""
    echo "Or get the URL with:"
    echo "  minikube service frontend-service -n multi-tier-app --url"
elif kubectl config current-context | grep -q "kind"; then
    print_info "Detected kind cluster"
    echo ""
    echo "To access the application, use port-forward:"
    echo "  kubectl port-forward -n multi-tier-app svc/frontend-service 8080:80"
    echo ""
    echo "Then open: http://localhost:8080"
else
    print_info "For LoadBalancer access, run:"
    echo "  kubectl get svc frontend-service -n multi-tier-app"
    echo ""
    echo "Or use port-forward:"
    echo "  kubectl port-forward -n multi-tier-app svc/frontend-service 8080:80"
fi

echo ""
echo "=========================================="
echo "Useful Commands"
echo "=========================================="
echo ""
echo "View logs:"
echo "  kubectl logs -n multi-tier-app -l app=backend --tail=50 -f"
echo "  kubectl logs -n multi-tier-app -l app=frontend --tail=50 -f"
echo ""
echo "Scale deployments manually:"
echo "  kubectl scale deployment backend -n multi-tier-app --replicas=5"
echo ""
echo "Test autoscaling (generate load):"
echo "  kubectl run -it --rm load-generator --image=busybox -n multi-tier-app -- /bin/sh"
echo "  # Then run: while true; do wget -q -O- http://backend-service:3000/api/data; done"
echo ""
echo "View HPA metrics:"
echo "  kubectl get hpa -n multi-tier-app --watch"
echo ""
echo "Delete deployment:"
echo "  kubectl delete namespace multi-tier-app"
echo ""
