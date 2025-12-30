#!/bin/bash

set -e

echo "=========================================="
echo "Load Testing & Autoscaling Demo"
echo "=========================================="
echo ""

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_header() {
    echo -e "${BLUE}==>${NC} $1"
}

# Check if namespace exists
if ! kubectl get namespace multi-tier-app &> /dev/null; then
    echo "Error: Namespace 'multi-tier-app' not found. Please deploy the application first."
    exit 1
fi

echo "This script will demonstrate Kubernetes autoscaling capabilities."
echo "It will generate load on the backend API and show how HPA responds."
echo ""
print_warn "Make sure metrics-server is installed and running!"
echo ""

# Check metrics server
if ! kubectl get deployment metrics-server -n kube-system &> /dev/null; then
    print_warn "Metrics server not found. HPA may not work correctly."
    echo "Install with: kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
    echo ""
fi

# Show current state
print_header "Current Pod Count"
kubectl get pods -n multi-tier-app -l app=backend
echo ""

print_header "Current HPA Status"
kubectl get hpa -n multi-tier-app
echo ""

# Start load test
print_info "Starting load test..."
print_info "This will create 5 concurrent load generators"
echo ""

# Create load generator pods
for i in {1..5}; do
    kubectl run load-generator-$i \
        --image=busybox \
        --restart=Never \
        --namespace=multi-tier-app \
        -- /bin/sh -c "while true; do wget -q -O- http://backend-service:3000/api/data; done" \
        &> /dev/null &
    
    print_info "Started load-generator-$i"
done

echo ""
print_info "Load generators started successfully!"
echo ""
print_info "Monitoring HPA and Pod scaling for 5 minutes..."
print_info "Press Ctrl+C to stop monitoring (load generators will continue)"
echo ""

# Monitor for 5 minutes
SECONDS=0
while [ $SECONDS -lt 300 ]; do
    clear
    echo "=========================================="
    echo "Autoscaling Monitor (${SECONDS}s / 300s)"
    echo "=========================================="
    echo ""
    
    print_header "HPA Status"
    kubectl get hpa -n multi-tier-app backend-hpa 2>/dev/null || echo "HPA metrics loading..."
    echo ""
    
    print_header "Pod Count"
    kubectl get pods -n multi-tier-app -l app=backend --no-headers | wc -l | xargs echo "Backend Pods:"
    echo ""
    
    print_header "Pod Details"
    kubectl get pods -n multi-tier-app -l app=backend -o wide
    echo ""
    
    print_header "Resource Usage (if available)"
    kubectl top pods -n multi-tier-app -l app=backend 2>/dev/null || echo "Metrics not yet available..."
    echo ""
    
    sleep 10
done

echo ""
print_info "Monitoring complete!"
echo ""
print_header "Final State"
kubectl get hpa -n multi-tier-app
echo ""
kubectl get pods -n multi-tier-app -l app=backend
echo ""

print_info "Cleaning up load generators..."
for i in {1..5}; do
    kubectl delete pod load-generator-$i -n multi-tier-app --force --grace-period=0 &> /dev/null || true
done

echo ""
print_info "Load test complete!"
echo ""
echo "The pods will scale down automatically after load decreases."
echo "This may take 5-10 minutes due to stabilization windows."
echo ""
echo "To watch scale-down, run:"
echo "  kubectl get hpa -n multi-tier-app --watch"
echo ""
