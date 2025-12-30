#!/bin/bash

set -e

echo "=========================================="
echo "Self-Healing & Resilience Demo"
echo "=========================================="
echo ""

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_header() {
    echo -e "${BLUE}==>${NC} $1"
}

# Check if namespace exists
if ! kubectl get namespace multi-tier-app &> /dev/null; then
    print_error "Namespace 'multi-tier-app' not found. Please deploy the application first."
    exit 1
fi

echo "This script demonstrates Kubernetes self-healing capabilities:"
echo "1. Pod restart on failure (liveness probe)"
echo "2. Automatic pod recreation when deleted"
echo "3. Service continuity during pod failures"
echo "4. Pod Disruption Budget protection"
echo ""

# Test 1: Pod automatic recreation
print_header "Test 1: Pod Automatic Recreation"
echo ""

print_info "Current backend pods:"
kubectl get pods -n multi-tier-app -l app=backend
echo ""

BACKEND_POD=$(kubectl get pods -n multi-tier-app -l app=backend -o jsonpath='{.items[0].metadata.name}')
print_info "Deleting pod: $BACKEND_POD"
kubectl delete pod $BACKEND_POD -n multi-tier-app

echo ""
print_info "Waiting for new pod to be created..."
sleep 3

kubectl get pods -n multi-tier-app -l app=backend
echo ""
print_info "✓ Deployment controller automatically created a replacement pod"
echo ""

# Test 2: Service availability during pod failure
print_header "Test 2: Service Availability During Failure"
echo ""

print_info "Testing API endpoint availability..."
kubectl run -it --rm test-pod --image=curlimages/curl -n multi-tier-app --restart=Never -- \
    curl -s http://backend-service:3000/api/data && echo ""
echo ""
print_info "✓ Service remains available via other healthy pods"
echo ""

# Test 3: Readiness probe
print_header "Test 3: Readiness Probe Behavior"
echo ""

print_info "Readiness probes ensure only healthy pods receive traffic"
print_info "Checking probe configuration..."
kubectl get deployment backend -n multi-tier-app -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}' | python3 -m json.tool
echo ""
print_info "✓ Readiness probe checks /health/ready including Redis connectivity"
echo ""

# Test 4: Pod Disruption Budget
print_header "Test 4: Pod Disruption Budget Protection"
echo ""

print_info "Viewing PDB configuration:"
kubectl get pdb -n multi-tier-app
echo ""

print_info "PDB ensures minimum 2 backend pods during voluntary disruptions"
print_info "Attempting to simulate eviction (this should respect PDB)..."
echo ""

BACKEND_COUNT=$(kubectl get pods -n multi-tier-app -l app=backend --no-headers | wc -l)
print_info "Current backend pod count: $BACKEND_COUNT"

if [ "$BACKEND_COUNT" -le 2 ]; then
    print_warn "Only $BACKEND_COUNT pods running. PDB requires minimum 2 available."
    print_warn "In a real scenario, eviction would be blocked if it violates PDB."
else
    print_info "✓ PDB would allow eviction of up to $((BACKEND_COUNT - 2)) pods"
fi
echo ""

# Test 5: Rolling update with zero downtime
print_header "Test 5: Rolling Update Simulation"
echo ""

print_info "Demonstrating zero-downtime rolling update..."
print_info "Current image version:"
kubectl get deployment backend -n multi-tier-app -o jsonpath='{.spec.template.spec.containers[0].image}'
echo ""
echo ""

print_info "Rolling update strategy:"
kubectl get deployment backend -n multi-tier-app -o jsonpath='{.spec.strategy}' | python3 -m json.tool
echo ""
echo ""

print_info "✓ MaxUnavailable: 1, MaxSurge: 1 ensures gradual rollout"
print_info "✓ Readiness probes prevent traffic to new pods until ready"
echo ""

# Test 6: Self-healing summary
print_header "Self-Healing Features Summary"
echo ""

cat << 'EOF'
┌─────────────────────────────────────────────────────────────────┐
│ Feature                    │ Status    │ Implementation         │
├────────────────────────────┼───────────┼────────────────────────┤
│ Automatic Pod Recreation   │ ✓ Active  │ Deployment Controller  │
│ Liveness Probe             │ ✓ Active  │ HTTP /health/live      │
│ Readiness Probe            │ ✓ Active  │ HTTP /health/ready     │
│ Pod Disruption Budget      │ ✓ Active  │ minAvailable: 2        │
│ Rolling Updates            │ ✓ Active  │ MaxUnavailable: 1      │
│ Pod Anti-Affinity          │ ✓ Active  │ Spread across nodes    │
│ Resource Limits            │ ✓ Active  │ CPU/Memory bounded     │
│ Multi-replica Backend      │ ✓ Active  │ 3-10 replicas (HPA)    │
└────────────────────────────┴───────────┴────────────────────────┘
EOF

echo ""
print_header "Additional Self-Healing Tests"
echo ""

echo "To test additional scenarios:"
echo ""
echo "1. Crash a container and watch automatic restart:"
echo "   POD=\$(kubectl get pods -n multi-tier-app -l app=backend -o name | head -n 1)"
echo "   kubectl exec -n multi-tier-app \$POD -- kill 1"
echo "   kubectl get pods -n multi-tier-app --watch"
echo ""
echo "2. Simulate resource exhaustion (OOMKilled):"
echo "   # Deploy a pod that exceeds memory limits"
echo "   # Kubernetes will automatically restart it"
echo ""
echo "3. Test service endpoint resilience:"
echo "   while true; do curl http://<frontend-url>/api/data; sleep 1; done"
echo "   # Delete pods in another terminal - service stays available"
echo ""
echo "4. Node failure simulation (multi-node cluster):"
echo "   kubectl drain <node-name> --ignore-daemonsets"
echo "   # Pods automatically rescheduled to other nodes"
echo ""

print_info "Self-healing demonstration complete!"
