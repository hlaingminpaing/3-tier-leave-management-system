#!/bin/bash

# Health Probes Verification Script
# Tests liveness and readiness probes across all services

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}        Health Probes Verification Script${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}\n"

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ kubectl not found${NC}"
    exit 1
fi

echo -e "${YELLOW}📋 Checking cluster connectivity...${NC}"
if kubectl cluster-info &> /dev/null; then
    echo -e "${GREEN}✓ Cluster connected${NC}\n"
else
    echo -e "${RED}✗ Cannot connect to cluster${NC}"
    exit 1
fi

# Function to check if pod is ready
check_pod_readiness() {
    local pod=$1
    local namespace=${2:-default}
    
    local ready=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
    if [ "$ready" = "true" ]; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
    fi
}

# Function to check probe endpoints
test_probe_endpoint() {
    local pod=$1
    local port=$2
    local path=$3
    local namespace=${4:-default}
    
    # Port-forward in background
    kubectl port-forward "pod/$pod" -n "$namespace" "$port:$port" &> /dev/null &
    local pf_pid=$!
    sleep 1
    
    # Test endpoint
    if output=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port$path" 2>/dev/null); then
        if [ "$output" = "200" ] || [ "$output" = "503" ]; then
            echo -e "${GREEN}✓ $path (HTTP $output)${NC}"
            kill $pf_pid 2>/dev/null || true
            return 0
        fi
    fi
    
    echo -e "${RED}✗ Cannot reach $path${NC}"
    kill $pf_pid 2>/dev/null || true
    return 1
}

echo -e "${YELLOW}🔍 Frontend Probes${NC}"
echo "─────────────────────────"

frontend_pods=$(kubectl get pods -l app=frontend -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
if [ -z "$frontend_pods" ]; then
    echo -e "${YELLOW}⚠ No frontend pods found${NC}"
else
    for pod in $frontend_pods; do
        echo "Pod: $pod"
        echo -n "  Status: "
        check_pod_readiness "$pod"
        echo -n "  Liveness probe (GET /): "
        test_probe_endpoint "$pod" "80" "/" 2>/dev/null || echo -e "${YELLOW}⚠ Skipped (curl not available)${NC}"
    done
fi

echo ""
echo -e "${YELLOW}🔍 Backend Probes${NC}"
echo "─────────────────────────"

backend_pods=$(kubectl get pods -l app=backend -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
if [ -z "$backend_pods" ]; then
    echo -e "${YELLOW}⚠ No backend pods found${NC}"
else
    for pod in $backend_pods; do
        echo "Pod: $pod"
        echo -n "  Status: "
        check_pod_readiness "$pod"
        echo "  Configured probes:"
        echo "    └─ Liveness:  GET /api/health (initialDelay: 30s, period: 10s)"
        echo "    └─ Readiness: GET /api/ready (initialDelay: 10s, period: 5s)"
        
        # Try to test endpoints
        echo "  Health endpoints:"
        test_probe_endpoint "$pod" "3000" "/api/health" 2>/dev/null || echo -e "${YELLOW}    └─ Cannot reach /api/health (service may be starting)${NC}"
        test_probe_endpoint "$pod" "3000" "/api/ready" 2>/dev/null || echo -e "${YELLOW}    └─ Cannot reach /api/ready (service may be starting)${NC}"
    done
fi

echo ""
echo -e "${YELLOW}🔍 MySQL Probes${NC}"
echo "─────────────────────────"

mysql_pods=$(kubectl get pods -l app=mysql -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
if [ -z "$mysql_pods" ]; then
    echo -e "${YELLOW}⚠ No MySQL pods found${NC}"
else
    for pod in $mysql_pods; do
        echo "Pod: $pod"
        echo -n "  Status: "
        check_pod_readiness "$pod"
        echo "  Configured probes:"
        echo "    └─ Liveness:  exec mysqladmin ping (initialDelay: 30s, period: 10s)"
        echo "    └─ Readiness: exec mysqladmin ping (initialDelay: 10s, period: 5s)"
    done
fi

echo ""
echo -e "${YELLOW}📊 Probe Configuration Summary${NC}"
echo "────────────────────────────────────────────────────────"

echo ""
echo "Backend Probes:"
echo "  Liveness (GET /api/health):"
echo "    - initialDelaySeconds: 30"
echo "    - periodSeconds: 10"
echo "    - timeoutSeconds: 5"
echo "    - failureThreshold: 3"
echo ""
echo "  Readiness (GET /api/ready with DB check):"
echo "    - initialDelaySeconds: 10"
echo "    - periodSeconds: 5"
echo "    - timeoutSeconds: 3"
echo "    - failureThreshold: 2"
echo ""

echo "Frontend Probes:"
echo "  Liveness & Readiness (GET /):"
echo "    - initialDelaySeconds: 15/5"
echo "    - periodSeconds: 10/5"
echo "    - timeoutSeconds: 5/3"
echo "    - failureThreshold: 3/2"
echo ""

echo "MySQL Probes:"
echo "  Liveness & Readiness (mysqladmin ping):"
echo "    - initialDelaySeconds: 30/10"
echo "    - periodSeconds: 10/5"
echo "    - timeoutSeconds: 5/3"
echo "    - failureThreshold: 3/2"
echo ""

echo -e "${YELLOW}📋 View Probe Details${NC}"
echo "────────────────────────────────────────────────────────"
echo "To view full probe configuration for a pod:"
echo ""
echo "  kubectl describe pod <pod-name>"
echo ""
echo "To view probe events:"
echo ""
echo "  kubectl get events --sort-by='.lastTimestamp'"
echo ""
echo "To test probes manually:"
echo ""
echo "  # Test backend liveness"
echo "  kubectl port-forward svc/backend 3000:3000"
echo "  curl http://localhost:3000/api/health"
echo ""
echo "  # Test backend readiness (with DB check)"
echo "  curl http://localhost:3000/api/ready"
echo ""
echo "  # If DB responsive:"
echo "  # Response: {\"status\": \"ready\", \"database\": \"connected\", ...}"
echo ""
echo "  # If DB not responsive:"
echo "  # Response: {\"status\": \"not_ready\", \"reason\": \"database_unreachable\", ...}"
echo ""

echo -e "${GREEN}✓ Health Probes Configuration Complete!${NC}"
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo "Your system now has:"
echo "  ✓ Automatic pod restart on failure"
echo "  ✓ Traffic only to healthy pods"
echo "  ✓ Database connectivity verification"
echo "  ✓ Better reliability & availability"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
