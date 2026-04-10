#!/bin/bash
# load-test/setup-monitoring.sh
# Quick setup script to prepare for load testing
# Ensures metrics, Prometheus, and Grafana are ready

set -e

COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
COLOR_BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${COLOR_BLUE}=================================${NC}"
echo -e "${COLOR_BLUE}Load Test Monitoring Setup${NC}"
echo -e "${COLOR_BLUE}=================================${NC}\n"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo -e "${COLOR_YELLOW}[1/6] Checking Prerequisites...${NC}"

if ! command_exists kubectl; then
    echo -e "${COLOR_RED}✗ kubectl not found. Please install kubectl.${NC}"
    exit 1
fi
echo -e "${COLOR_GREEN}✓ kubectl found${NC}"

if ! command_exists k6; then
    echo -e "${COLOR_YELLOW}⚠ k6 not found. Install from: https://k6.io/docs/getting-started/installation/${NC}"
fi

# Check Kubernetes connectivity
echo -e "\n${COLOR_YELLOW}[2/6] Checking Kubernetes Cluster...${NC}"
if kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${COLOR_GREEN}✓ Connected to Kubernetes cluster${NC}"
    kubectl cluster-info | grep 'Kubernetes master'
else
    echo -e "${COLOR_RED}✗ Cannot connect to Kubernetes cluster${NC}"
    exit 1
fi

# Check monitoring namespace
echo -e "\n${COLOR_YELLOW}[3/6] Checking Monitoring Stack...${NC}"
if kubectl get namespace monitoring >/dev/null 2>&1; then
    echo -e "${COLOR_GREEN}✓ Monitoring namespace exists${NC}"
    POD_COUNT=$(kubectl get pods -n monitoring | wc -l)
    echo -e "  Pods in monitoring: $(($POD_COUNT - 1))"
else
    echo -e "${COLOR_RED}✗ Monitoring namespace not found. Run: terraform apply${NC}"
    exit 1
fi

# Check Prometheus
echo -e "\n${COLOR_YELLOW}[4/6] Checking Prometheus...${NC}"
if kubectl get pod -n monitoring -l app=prometheus >/dev/null 2>&1; then
    echo -e "${COLOR_GREEN}✓ Prometheus is running${NC}"
else
    echo -e "${COLOR_YELLOW}⚠ Prometheus pods not found. Checking kube-prometheus-stack...${NC}"
    kubectl get pods -n monitoring | grep -i prometheus || echo "No Prometheus pods"
fi

# Check Grafana
echo -e "\n${COLOR_YELLOW}[5/6] Checking Grafana...${NC}"
if kubectl get pod -n monitoring -l app.kubernetes.io/name=grafana >/dev/null 2>&1; then
    echo -e "${COLOR_GREEN}✓ Grafana is running${NC}"
else
    echo -e "${COLOR_YELLOW}⚠ Grafana pods not found${NC}"
fi

# Check backend metrics
echo -e "\n${COLOR_YELLOW}[6/6] Checking Backend Metrics Endpoint...${NC}"
BACKEND_POD=$(kubectl get pod -l app=backend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -z "$BACKEND_POD" ]; then
    echo -e "${COLOR_YELLOW}⚠ No backend pods found. Deploy application first.${NC}"
else
    echo -e "${COLOR_GREEN}✓ Backend pod found: ${BACKEND_POD}${NC}"
    
    # Try to check metrics endpoint
    METRICS=$(kubectl exec $BACKEND_POD -- curl -s http://localhost:9464/metrics 2>/dev/null | grep "leave_requests_total" | head -1 || echo "")
    if [ -z "$METRICS" ]; then
        echo -e "${COLOR_YELLOW}⚠ Could not verify metrics endpoint${NC}"
    else
        echo -e "${COLOR_GREEN}✓ Metrics endpoint is responding${NC}"
    fi
fi

echo -e "\n${COLOR_BLUE}=================================${NC}"
echo -e "${COLOR_BLUE}Setup Complete!${NC}"
echo -e "${COLOR_BLUE}=================================${NC}\n"

echo -e "${COLOR_YELLOW}Next Steps:${NC}"
echo "1. Port forward to Grafana:"
echo -e "   ${COLOR_GREEN}kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80${NC}"
echo ""
echo "2. Access Grafana at http://localhost:3000"
echo "   Username: admin"
echo "   Password: (from terraform.tfvars)"
echo ""
echo "3. In a new terminal, run load test:"
echo -e "   ${COLOR_GREEN}cd load-test${NC}"
echo -e "   ${COLOR_GREEN}k6 run advanced-scenario.js${NC}"
echo ""
echo "4. Watch metrics dashboard during test"
echo -e "   ${COLOR_YELLOW}See LOAD_TEST_COMPLETE_GUIDE.md for dashboard setup${NC}"
echo ""
echo -e "${COLOR_YELLOW}Useful Commands:${NC}"
echo "  # Port forward Prometheus"
echo -e "  ${COLOR_GREEN}kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090${NC}"
echo ""
echo "  # Port forward backend metrics"
echo -e "  ${COLOR_GREEN}kubectl port-forward svc/backend 9464:9464${NC}"
echo ""
echo "  # Watch backend logs"
echo -e "  ${COLOR_GREEN}kubectl logs -f -l app=backend${NC}"
echo ""
echo "  # View HPA status"
echo -e "  ${COLOR_GREEN}kubectl get hpa${NC}"
echo ""
echo "  # View pod scaling"
echo -e "  ${COLOR_GREEN}kubectl get pods -l app=backend${NC}"
echo ""
echo -e "${COLOR_GREEN}Ready to load test! 🚀${NC}\n"
