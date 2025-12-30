# Multi-Tier Kubernetes Application

A production-grade, multi-tier Kubernetes application demonstrating DevOps best practices including auto-scaling, self-healing, observability, and comprehensive security controls.

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Detailed Deployment Instructions](#detailed-deployment-instructions)
- [Scaling Capabilities](#scaling-capabilities)
- [Self-Healing Capabilities](#self-healing-capabilities)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)
- [Project Structure](#project-structure)

---

## 🎯 Overview

This project deploys a **three-tier web application** on Kubernetes:

- **Frontend**: NGINX reverse proxy (2-6 replicas, auto-scaled)
- **Backend**: Node.js API with Redis caching (3-10 replicas, auto-scaled)
- **Cache**: Redis StatefulSet with persistent storage (1 replica)

### Key Features

✅ **Horizontal Pod Autoscaling** - Automatic scaling based on CPU/memory  
✅ **Self-Healing** - Automatic recovery from failures  
✅ **High Availability** - Pod Disruption Budgets, anti-affinity  
✅ **Security** - Network policies, pod security contexts  
✅ **Observability** - Health checks, Prometheus metrics  
✅ **Zero Downtime** - Rolling updates with readiness probes

---

## 🏗️ Architecture

```
Internet → LoadBalancer → NGINX (2-6 pods) → Node.js API (3-10 pods) → Redis (1 pod)
                              ↓ Auto-scales        ↓ Auto-scales        ↓ Persistent
```

---

## 🚀 Quick Start

```bash
# 1. Start Kubernetes cluster
minikube start --cpus=4 --memory=8192
minikube addons enable metrics-server

# 2. Deploy application
kubectl apply -f manifests/

# 3. Wait for pods (2-5 minutes)
kubectl wait --for=condition=ready pod --all -n multi-tier-app --timeout=300s

# 4. Access application
minikube service frontend-service -n multi-tier-app
# Or: kubectl port-forward -n multi-tier-app svc/frontend-service 8080:80
```

---

## 📖 Detailed Deployment Instructions

### Prerequisites

- **Docker Desktop** installed
- **kubectl** installed
- **Kubernetes cluster**: minikube, kind, or Docker Desktop
- **4+ CPU cores, 8GB+ RAM** recommended

### Option 1: Deploy on Minikube

**Step 1: Start Minikube**
```bash
minikube start --cpus=4 --memory=8192 --driver=docker
minikube addons enable metrics-server
```

**Step 2: Verify Cluster**
```bash
kubectl cluster-info
kubectl get nodes
```

**Step 3: Deploy Application**
```bash
cd kubernetes-multi-tier-app
kubectl apply -f manifests/
```

**Step 4: Wait for Pods**
```bash
kubectl get pods -n multi-tier-app --watch
# Press Ctrl+C when all show "Running" and "1/1"
```

**Step 5: Access Application**
```bash
minikube service frontend-service -n multi-tier-app
# Opens browser automatically
```

### Option 2: Deploy on kind

**Step 1: Create Cluster**
```bash
cat <<EOF | kind create cluster --name multi-tier-app --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 80
    hostPort: 8080
- role: worker
- role: worker
EOF
```

**Step 2: Install Metrics Server**
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

kubectl patch -n kube-system deployment metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

**Step 3: Deploy Application**
```bash
kubectl apply -f manifests/
kubectl wait --for=condition=ready pod --all -n multi-tier-app --timeout=300s
```

**Step 4: Access Application**
```bash
kubectl port-forward -n multi-tier-app svc/frontend-service 8080:80
# Open browser to http://localhost:8080
```

### Option 3: Deploy on Docker Desktop

**Step 1: Enable Kubernetes**
- Docker Desktop → Settings → Kubernetes → Enable Kubernetes → Apply

**Step 2: Install Metrics Server**
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

kubectl patch -n kube-system deployment metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

**Step 3: Deploy & Access**
```bash
kubectl apply -f manifests/
kubectl port-forward -n multi-tier-app svc/frontend-service 8080:80
# Open http://localhost:8080
```

---

## 📈 Scaling Capabilities

### How Horizontal Pod Autoscaling Works

The HPA controller monitors pod metrics every 15 seconds and automatically adjusts replica count:

```
Current CPU: 85% | Target: 70%
→ Desired replicas = ceil(3 × (85/70)) = 4 pods
→ HPA scales from 3 to 4 pods
```

### Configuration

**Backend HPA:**
- Min: 3 replicas, Max: 10 replicas
- CPU target: 70%, Memory target: 80%
- Scale-up: Fast (add 4 pods or 100% every 30s)
- Scale-down: Slow (remove 2 pods or 50% every 60s, 5min stabilization)

**Frontend HPA:**
- Min: 2 replicas, Max: 6 replicas  
- CPU target: 75%, Memory target: 85%

### Demonstrating Auto-Scaling

**Generate Load:**
```bash
# Create load generators
for i in {1..5}; do
  kubectl run load-$i --image=busybox -n multi-tier-app --restart=Never -- \
    /bin/sh -c "while true; do wget -q -O- http://backend-service:3000/api/data; done" &
done
```

**Watch Scaling:**
```bash
# Terminal 1: Watch HPA
kubectl get hpa -n multi-tier-app --watch

# Terminal 2: Watch pods
kubectl get pods -n multi-tier-app --watch

# You'll see pods scale from 3 → 4 → 5 → more as CPU increases
```

**Cleanup:**
```bash
kubectl delete pod -n multi-tier-app -l run^=load-
# Pods will scale back down after ~5 minutes
```

### Why These Settings?

**Aggressive Scale-Up (30s):**
- Responds quickly to traffic spikes
- Prevents request queuing and timeouts
- Better user experience during load

**Conservative Scale-Down (5min):**
- Prevents thrashing from variable traffic
- Avoids constant pod creation/deletion
- Reduces overhead and cost

---

## 🔧 Self-Healing Capabilities

Kubernetes provides multiple automatic recovery mechanisms:

### 1. Automatic Pod Restart

**What:** Restarts containers that crash or fail

**How:** kubelet monitors processes and restarts on exit

**Demo:**
```bash
# Kill a backend pod's main process
POD=$(kubectl get pod -n multi-tier-app -l app=backend -o name | head -n1)
kubectl exec -n multi-tier-app $POD -- kill 1

# Watch it restart automatically
kubectl get pods -n multi-tier-app --watch
# You'll see: Running → Error → CrashLoopBackOff → Running
```

### 2. Liveness Probes

**What:** Detects "stuck" containers (not crashed but not functioning)

**Config:**
```yaml
livenessProbe:
  httpGet:
    path: /health/live
    port: 3000
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 3
```

**How It Works:**
- kubelet checks `/health/live` every 10 seconds
- After 3 failures (30 seconds), container is killed and restarted
- Backend returns `{"status":"alive"}`

### 3. Readiness Probes

**What:** Removes unhealthy pods from service endpoints (doesn't restart them)

**Config:**
```yaml
readinessProbe:
  httpGet:
    path: /health/ready
    port: 3000
  initialDelaySeconds: 10
  periodSeconds: 5
  failureThreshold: 3
```

**How It Works:**
- Backend checks Redis connectivity: `/health/ready`
- If Redis is down: returns 503 → pod removed from service
- Once Redis reconnects: returns 200 → pod added back to service
- **No restart** - just temporarily out of rotation

**Key Difference:**

| Probe | Failure Action | Use Case |
|-------|---------------|----------|
| **Liveness** | Restart container | Deadlock, infinite loop |
| **Readiness** | Remove from endpoints | Dependency failure, startup delay |

### 4. Automatic Pod Recreation

**What:** Maintains desired replica count

**Demo:**
```bash
# Delete a pod
kubectl delete pod -n multi-tier-app -l app=backend | head -n1

# Watch replacement created immediately
kubectl get pods -n multi-tier-app -l app=backend --watch
# backend-abc Terminating → backend-xyz Pending → Running
```

### 5. Rolling Updates (Zero Downtime)

**What:** Updates application without service interruption

**Config:**
```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1          # Create 1 extra pod
    maxUnavailable: 1    # Max 1 unavailable (backend)
    maxUnavailable: 0    # Zero downtime (frontend)
```

**Demo:**
```bash
# Trigger update
kubectl set image deployment/backend backend=node:22-alpine -n multi-tier-app

# Watch rolling update
kubectl rollout status deployment/backend -n multi-tier-app

# Pods update one at a time:
# 1. Create new pod
# 2. Wait for readiness probe
# 3. Terminate old pod
# 4. Repeat
```

Service remains available throughout!

### 6. Pod Disruption Budgets

**What:** Ensures minimum availability during voluntary disruptions

**Config:**
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: backend-pdb
spec:
  minAvailable: 2    # Always keep 2 pods running
  selector:
    matchLabels:
      app: backend
```

**Protects Against:**
- Node drains during maintenance
- Cluster upgrades
- Manual evictions

**Demo:**
```bash
kubectl get pdb -n multi-tier-app
# Shows: ALLOWED DISRUPTIONS: 1 (can evict 1 pod safely)
```

### 7. Pod Anti-Affinity

**What:** Spreads pods across nodes for fault tolerance

**Config:**
```yaml
podAntiAffinity:
  preferredDuringSchedulingIgnoredDuringExecution:
  - podAffinityTerm:
      labelSelector:
        matchLabels:
          app: backend
      topologyKey: kubernetes.io/hostname
```

**Result:** In multi-node clusters, pods spread across different nodes so one node failure doesn't take down all pods

### Self-Healing Summary

| Mechanism | Detects | Recovery Time |
|-----------|---------|---------------|
| Container Restart | Process crash | ~10 seconds |
| Liveness Probe | App deadlock | ~30 seconds |
| Readiness Probe | Dependency failure | ~15 seconds |
| Pod Recreation | Pod deletion | ~30-60 seconds |
| Rolling Update | Config change | ~5 minutes |
| PDB | Node drain | Immediate (blocks drain) |

---

## 🧪 Testing

### Test Web UI

```bash
# Access application
kubectl port-forward -n multi-tier-app svc/frontend-service 8080:80

# Open http://localhost:8080
# Click "Test Backend API" button
```

### Test API Endpoints

```bash
# Health checks
curl http://localhost:8080/api/health/live    # {"status":"alive"}
curl http://localhost:8080/api/health/ready   # {"status":"ready","redis":"connected"}

# API endpoint
curl http://localhost:8080/api/data           # Returns JSON with pod info

# Metrics
curl http://localhost:8080/api/metrics        # Prometheus metrics
```

### Test Redis Caching

```bash
# First request (cache MISS)
curl -i http://localhost:8080/api/data 2>&1 | grep X-Cache
# X-Cache: MISS

# Second request (cache HIT)
curl -i http://localhost:8080/api/data 2>&1 | grep X-Cache
# X-Cache: HIT
```

### Test from Inside Cluster

```bash
# Test backend directly
kubectl run test --image=curlimages/curl -n multi-tier-app --rm -it --restart=Never -- \
  curl -s http://backend-service:3000/api/data
```

---

## 🔧 Troubleshooting

### Pods Stuck in Pending

```bash
# Check events
kubectl describe pod -n multi-tier-app <pod-name>

# Common causes:
# - Insufficient resources → Increase cluster size
# - PVC not bound → Check storage class
# - Image pull error → Check image name
```

### Pods in CrashLoopBackOff

```bash
# Check logs
kubectl logs -n multi-tier-app <pod-name>
kubectl logs -n multi-tier-app <pod-name> --previous

# Common causes:
# - Application error → Check logs for stack trace
# - Missing dependencies → Ensure Redis is running
# - Permission errors → Remove securityContext temporarily
```

### HPA Shows `<unknown>`

```bash
# Metrics server not ready
kubectl get deployment metrics-server -n kube-system

# Solution: Install and patch metrics server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

kubectl patch -n kube-system deployment metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

### Can't Access Application

```bash
# Ensure port-forward is running
kubectl port-forward -n multi-tier-app svc/frontend-service 8080:80

# Check pods are ready
kubectl get pods -n multi-tier-app

# Check service has endpoints
kubectl get endpoints frontend-service -n multi-tier-app
```

---

## 📁 Project Structure

```
kubernetes-multi-tier-app/
├── manifests/                   # Kubernetes YAML files
│   ├── 00-namespace.yaml       # Namespace
│   ├── 01-configmap.yaml       # Configuration
│   ├── 02-secrets.yaml         # Credentials
│   ├── 03-redis.yaml           # Redis StatefulSet
│   ├── 04-backend.yaml         # Backend Deployment
│   ├── 05-frontend.yaml        # Frontend Deployment
│   ├── 06-hpa.yaml             # Autoscalers
│   ├── 07-network-policies.yaml # Security
│   ├── 08-pdb.yaml             # Disruption Budgets
│   └── 09-monitoring.yaml      # Prometheus
│
├── deploy.sh                    # Deployment script
└── README.md                    # This file
```

---

## 🧹 Cleanup

```bash
# Delete application
kubectl delete namespace multi-tier-app

# Delete cluster
minikube delete
# OR
kind delete cluster --name multi-tier-app
```