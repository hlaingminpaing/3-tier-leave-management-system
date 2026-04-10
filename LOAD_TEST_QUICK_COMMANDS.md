# Load Test Quick Commands Reference

## 📋 One-Time Setup

```bash
# Make setup script executable
chmod +x load-test/setup-monitoring.sh

# Run setup verification
./load-test/setup-monitoring.sh
```

---

## 🚀 Running The Load Test (Parallel Terminals)

### Terminal 1: Grafana Dashboard
```bash
# Port forward and open dashboard
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Then visit: http://localhost:3000
# Login: admin / password (from terraform.tfvars)
```

### Terminal 2: Prometheus Metrics
```bash
# Port forward for direct metric queries
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Visit: http://localhost:9090
```

### Terminal 3: Backend Metrics Live
```bash
# Watch metrics update in real-time
kubectl port-forward svc/backend 9464:9464
watch -n 1 'curl -s http://localhost:9464/metrics | grep -E "active_users|leave_requests_total|login_attempts"'
```

### Terminal 4: Watch Pod Scaling
```bash
# Monitor pod scaling in real-time
watch -n 2 'kubectl get pods -l app=backend -o wide'

# And in another tab, watch HPA
watch -n 2 'kubectl get hpa backend-hpa'
```

### Terminal 5: Run Load Test
```bash
cd load-test

# Option A: Full 100-user test (25 minutes)
k6 run advanced-scenario.js

# Option B: Pre-populated users (faster)
k6 run pre-populated-users.js

# Option C: Quick test with 50 users
k6 run script.js

# Option D: Save results to file
k6 run advanced-scenario.js --out json=results-$(date +%s).json
```

---

## 📊 Grafana Dashboard Setup (Paste These Queries)

### Panel 1: Active Users
```promql
active_users
```

### Panel 2: Request Rate (Req/Sec)
```promql
rate(http_requests_by_endpoint[1m])
```

### Panel 3: Latency P95 (ms)
```promql
histogram_quantile(0.95, http_request_duration_seconds_bucket) * 1000
```

### Panel 4: Error Rate (%)
```promql
(rate(http_errors_total[5m]) / rate(http_requests_by_endpoint[5m])) * 100
```

### Panel 5: Leave Requests Total
```promql
leave_requests_total
```

### Panel 6: Pod Count
```promql
count(up{job="backend-metrics"})
```

### Panel 7: DB Latency P95 (ms)
```promql
histogram_quantile(0.95, db_query_duration_seconds_bucket) * 1000
```

### Panel 8: Login Success Rate (%)
```promql
(rate(login_attempts_total{result="success"}[5m]) / 
 (rate(login_attempts_total{result="success"}[5m]) + 
  rate(login_attempts_total{result="failure"}[5m]))) * 100
```

---

## 🔍 Monitoring Commands

### Check Prerequisites
```bash
# Is kubectl available?
kubectl version

# Is k6 installed?
k6 version

# Connected to cluster?
kubectl cluster-info

# Monitoring stack running?
kubectl get pods -n monitoring | grep -E "prometheus|grafana|loki|tempo"
```

### Check Metrics Endpoint
```bash
# Port forward
kubectl port-forward svc/backend 9464:9464

# Check if metrics are there
curl http://localhost:9464/metrics | grep "TYPE"

# Count custom metrics
curl -s http://localhost:9464/metrics | grep "^#" | wc -l
```

### Check Prometheus Scraping
```bash
# Port forward
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Then visit http://localhost:9090/targets
# Look for: job="backend-metrics" with status UP (green)
```

### Check Pod Scaling (HPA)
```bash
# View HPA status
kubectl get hpa

# Detailed HPA info
kubectl describe hpa backend-hpa

# View scaling events
kubectl get events | grep -i "hpa\|scale"

# Check current metrics
kubectl get hpa backend-hpa -o yaml

# Manual trigger (set high CPU threshold temporarily)
# Edit HPA and change targetCPUUtilizationPercentage to 10
kubectl edit hpa backend-hpa
```

### Check Pod Logs
```bash
# Stream backend logs
kubectl logs -f -l app=backend

# Get logs from specific pod
kubectl logs <pod-name>

# Get last 50 lines
kubectl logs <pod-name> --tail=50

# Get logs from all backend pods
kubectl logs -l app=backend --all-containers=true
```

### Monitor Resources
```bash
# CPU and Memory per pod (live updates)
watch -n 2 'kubectl top pod -l app=backend'

# Top nodes
kubectl top nodes

# Describe pod for events
kubectl describe pod <pod-name>
```

---

## 📈 During Load Test - What to Watch

### On Metrics Dashboard (Grafana)
```
Every 5-10 seconds during peak load (10-20 min mark):
- Active Users should be near 100
- Request Rate should be 50+ req/sec
- Latency P95 should be under 500ms
- Error Rate should be under 5%
- Pod Count should increase (HPA triggered)
- DB Latency P95 should be under 200ms
```

### In Terminal (Pod Scaling)
```
Watch for status changes:
- Pods from 1 → 2 → 3 → 4 (scaling up)
- Then 4 → 3 → 2 → 1 (scaling down after test ends)
```

### In Prometheus
```
Query during peak load:
http://localhost:9090

Try:
- active_users
- rate(http_requests_by_endpoint[1m])
- histogram_quantile(0.95, http_request_duration_seconds_bucket)
```

---

## ✅ Post-Load Test Verification

```bash
# Metrics collected?
curl -s http://localhost:9464/metrics | \
  grep -E "active_users|leave_requests_total|login_attempts" | head -5

# Peak values in Prometheus
# Visit: http://localhost:9090?tab=graph
# Query: max(active_users)
# Query: max(leave_requests_total)

# Performance metrics
# Query: histogram_quantile(0.95, http_request_duration_seconds_bucket)
# Query: histogram_quantile(0.99, http_request_duration_seconds_bucket)

# Pod scaling verification
kubectl get pods -l app=backend
# All should be Running, RESTARTS = 0

# Check HPA events
kubectl describe hpa backend-hpa
# Look for: ScaledUpReplicas and ScaledDownReplicas events
```

---

## 🎯 Expected Values at Peak Load (10-20 min mark)

| Metric | Expected Value |
|--------|-----------------|
| Active Users | ~100 |
| Request Rate | 50+ req/sec |
| Latency P95 | < 500ms |
| Latency P99 | < 1000ms |
| Error Rate | < 5% |
| Success Rate | > 95% |
| DB Query P95 | < 200ms |
| Leave Requests | ~100 total |
| Pod Count | 3-5 pods |
| Pod CPU | 30-60% |
| Pod Memory | 300-400 MB |

---

## 🚨 Troubleshooting Quick Fixes

### Metrics not showing?
```bash
# Restart Prometheus
kubectl rollout restart deployment/kube-prometheus-stack-operator -n monitoring

# Restart backend
kubectl rollout restart deployment/backend

# Wait 30 seconds
sleep 30

# Check metrics
curl http://localhost:9464/metrics | grep leave_requests
```

### Error rate too high?
```bash
# Check logs
kubectl logs -l app=backend | grep -i error | tail -20

# Check database
kubectl exec -it <mysql-pod> -- mysql -u root -p<password>
SHOW PROCESSLIST;
```

### Pods not scaling?
```bash
# Check HPA
kubectl get hpa
kubectl describe hpa backend-hpa

# Check metrics being used
kubectl get hpa backend-hpa -o yaml | grep metric

# Manual scale to test
kubectl scale deployment backend --replicas=3
```

### k6 not installed?
```bash
# macOS
brew install k6

# Windows (Chocolatey)
choco install k6

# Linux
sudo apt-get install k6

# Or download from https://k6.io/docs/getting-started/installation/
```

---

## 💾 Saving Results

```bash
# Save k6 output to file
k6 run advanced-scenario.js > load-test-results-$(date +%Y%m%d-%H%M%S).log 2>&1

# Export k6 results to JSON
k6 run advanced-scenario.js --out json=results-$(date +%s).json

# Take Grafana dashboard screenshot
# Use browser: Right-click → Screenshot

# Export Prometheus data
# Visit http://localhost:9090 → Graph → Export Data

# Save pod scaling timeline
kubectl describe hpa backend-hpa > hpa-report-$(date +%s).txt
```

---

## 📚 File Reference

| File | Purpose |
|------|---------|
| `load-test/script.js` | Basic 50-user test |
| `load-test/advanced-scenario.js` | Full 100-user test (recommended) |
| `load-test/pre-populated-users.js` | 100-user test with pre-created users |
| `LOAD_TEST_COMPLETE_GUIDE.md` | Comprehensive guide with all details |
| `LOAD_TEST_MONITORING_CHECKLIST.md` | Step-by-step checklist |
| `LOAD_TEST_QUICK_COMMANDS.md` | This file - quick command reference |

---

## 🎬 Complete Workflow (Copy & Paste)

### Setup (One time)
```bash
cd ~/projects/3tier-leave-system
chmod +x load-test/setup-monitoring.sh
./load-test/setup-monitoring.sh
```

### Run Test Session
```bash
# Terminal 1
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Terminal 2
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Terminal 3
kubectl port-forward svc/backend 9464:9464

# Terminal 4
watch -n 2 'kubectl get pods -l app=backend -o wide'

# Terminal 5
cd load-test && k6 run advanced-scenario.js
```

### After Test
```bash
# Check results
curl -s http://localhost:9464/metrics | grep -E "active_users|leave_requests"

# View HPA scaling events
kubectl describe hpa backend-hpa

# Save results
kubectl describe hpa backend-hpa > results/hpa-$(date +%s).txt
```

---

## 🎉 Quick Start (3 Min Video Script)

1. **Setup (30 sec)**: Run setup script
2. **Start Monitoring (1 min)**: Open 4 terminals, run port-forwards
3. **Run Test (10 sec)**: `k6 run advanced-scenario.js`
4. **Observe (2 min)**: Watch metrics climb in Grafana
5. **Verify (30 sec)**: Check results

**Total Time**: ~15 minutes for full test + observations

---

**Ready to load test? Copy the parallel terminal commands above into your terminal tabs and go!** 🚀
