# Load Testing with 100 Concurrent Users - Complete Guide

## Overview

This guide walks you through running a load test with **100 concurrent users** and monitoring metrics in Grafana to verify:
- ✅ Metrics are collected correctly
- ✅ Application scales (HPA triggers new pods)
- ✅ Performance degradation is minimal
- ✅ System handles high concurrency

---

## 📋 What You'll Test

### User Stories Tested:
1. **User Registration** - 100 new users registering
2. **User Login** - 100 users logging in (authentication metrics)
3. **Apply Leave Request** - 100 users submitting leave requests
4. **View Leave History** - 100 users checking their leave requests
5. **Bonus**: Some users apply multiple leaves (realistic behavior)

### Metrics You'll Observe:
- ✅ Active users count (business metric)
- ✅ Request latency (performance)
- ✅ Database query latency
- ✅ Error rates
- ✅ Pod scaling (HPA)
- ✅ Pod CPU/Memory usage
- ✅ Database connection pool

---

## 🚀 Quick Start (5 Steps)

### Step 1: Ensure Backend Metrics are Working

```bash
# Port forward to backend metrics
kubectl port-forward svc/backend 9464:9464

# In another terminal, verify metrics are exposed
curl http://localhost:9464/metrics | head -20

# Should see: 
# TYPE active_users gauge
# active_users 0
# TYPE leave_requests_total counter
```

### Step 2: Set Up Grafana Dashboard

```bash
# Port forward to Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Login: http://localhost:3000
# User: admin
# Password: (from terraform.tfvars)

# Create dashboard or use provided templates
```

### Step 3: Deploy Load Test

```bash
# Method 1: Run k6 locally (if k6 installed)
cd load-test
k6 run script.js --vus 100 --duration 30s

# Method 2: Run advanced scenario (recommended for 100 users)
k6 run advanced-scenario.js

# Method 3: Create Kubernetes job (recommended for production)
# See "Run in Kubernetes" section below
```

### Step 4: Watch Metrics in Grafana

While load test is running:

```bash
# Open Grafana dashboard
http://localhost:3000

# Watch these metrics:
- Active users (should climb to 100)
- Request rate (should spike)
- Error rate (should stay low)
- Pod count (should increase due to HPA)
- Memory/CPU usage
```

### Step 5: Verify Results

After test completes:
- ✅ Check if pods scaled (HPA worked)
- ✅ Verify latency stayed acceptable
- ✅ Confirm error rate was low
- ✅ Review Prometheus for data retention

---

## 📊 Setting Up Grafana Dashboard for Load Testing

### Pre-requisite: Create New Dashboard

1. Open Grafana: http://localhost:3000
2. **Dashboards** → **Create** → **New Dashboard**
3. Add panels with queries below

### Panel 1: Active Users (Business Metric)

```
Title: Active Users
Query: active_users
Visualization: Gauge
Thresholds: 
  - Green: 0-50
  - Yellow: 50-100
  - Red: 100+
```

**What to watch**: Should climb during load test from 0 → 100

### Panel 2: Request Rate (Throughput)

```
Title: Requests Per Second
Query: rate(http_requests_by_endpoint[1m])
Visualization: Time Series
Legend: By endpoint
```

**What to watch**: Should spike when load test starts

### Panel 3: Latency (P95)

```
Title: Response Latency P95 (ms)
Query: histogram_quantile(0.95, http_request_duration_seconds_bucket) * 1000
Visualization: Time Series
Alert: > 500ms
```

**What to watch**: Should stay under 500ms even at 100 users

### Panel 4: Error Rate (%)

```
Title: Error Rate
Query: (rate(http_errors_total[5m]) / rate(http_requests_by_endpoint[5m])) * 100
Visualization: Time Series
Alert: > 5%
```

**What to watch**: Should stay < 5% (allows some auth failures during registration race)

### Panel 5: Pod Count (Scaling)

```
Title: Backend Pod Count
Query: count(up{job="kubernetes-pods",pod=~"backend.*"})
Visualization: Stat (big number)
```

**What to watch**: Should increase when HPA triggers (usually at 70% CPU)

### Panel 6: Database Query Latency

```
Title: DB Query Latency P95 (ms)
Query: histogram_quantile(0.95, db_query_duration_seconds_bucket) * 1000
Visualization: Time Series
Legend: By operation
```

**What to watch**: SELECT <100ms, INSERT <200ms

### Panel 7: Leave Requests Submitted

```
Title: Leave Requests (Total)
Query: leave_requests_total
Visualization: Stat
```

**What to watch**: Should increase to ~100 during test

### Panel 8: Pod CPU Usage

```
Title: Backend Pod CPU Usage
Query: rate(process_cpu_seconds_total[1m]) * 100
Visualization: Time Series
```

**What to watch**: Should spike during load, then cool down

---

## 🏃 Running the Load Test

### Option 1: Local k6 Execution (Quick Test)

```bash
# Install k6 (if not already installed)
# Windows: choco install k6
# Mac: brew install k6
# Linux: see https://k6.io/docs/getting-started/installation/

# Navigate to load-test folder
cd load-test

# Run basic script (20-50 users)
k6 run script.js

# Run advanced scenario (100 users - recommended)
k6 run advanced-scenario.js

# Specify API endpoint if not localhost
k6 run advanced-scenario.js --env API_URL=http://your-alb-dns/api

# Collect metrics to JSON file
k6 run advanced-scenario.js --out json=results.json
```

**Expected Output:**
```
    ✓ Register status is 200 or 409
    ✓ Login status is 200
    ✓ Apply leave status is 200
    ✓ Get leaves status is 200

  █ 100 VUs max duration exceeded
    0 failed out of 100 total

  avg=245ms min=45ms med=150ms max=2500ms p(90)=380ms p(95)=420ms
```

### Option 2: Kubernetes Job (Production-Grade)

Create a k6 Kubernetes job:

```bash
# Create namespace if needed
kubectl create namespace load-testing

# Create ConfigMap with script
kubectl create configmap k6-script --from-file=advanced-scenario.js -n load-testing

# Run as Kubernetes Job
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: k6-load-test
  namespace: load-testing
spec:
  template:
    spec:
      containers:
      - name: k6
        image: grafana/k6:latest
        command: ["k6", "run", "/scripts/advanced-scenario.js", 
                  "--env", "API_URL=http://backend.default:3000"]
        volumeMounts:
        - name: scripts
          mountPath: /scripts
      volumes:
      - name: scripts
        configMap:
          name: k6-script
      restartPolicy: Never
  backoffLimit: 1
EOF

# Monitor job
kubectl logs -f job/k6-load-test -n load-testing

# Watch metrics in Grafana simultaneously
```

### Option 3: Simple Curl Loop (Manual Test)

```bash
# For quick manual testing without k6
cd load-test
chmod +x run-manual-test.sh
./run-manual-test.sh 100  # Run with 100 concurrent users
```

---

## 📈 Expected Results During Load Test

### Timeline: How metrics should change

**Phase 1: Warm-up (First 5 minutes)**
- Active users: 0 → 10
- Request rate: Low
- Latency: ~100-200ms
- Error rate: ~0% (any registration failures)
- Pod count: Should remain 1-2

**Phase 2: Ramp-up (Next 5 minutes)**
- Active users: 10 → 50
- Request rate: Increases
- Latency: ~200-300ms
- Error rate: ~1-2%
- Pod count: May increase to 2-3

**Phase 3: Peak Load (10 minutes at 100 users) ← KEY OBSERVATION POINT
- Active users: ~100
- Request rate: HIGH (50+ req/sec)
- Latency: ~300-500ms (acceptable)
- Error rate: ~3-5% (some auth conflicts during registration)
- Pod count: Should increase to 3-5 (HPA triggered!)
- CPU usage: ~60-80%
- Memory usage: ~300-400MB per pod

**Phase 4: Cool-down (Last 5 minutes)**
- Metrics return to baseline
- Pods scale down (HPA removes unnecessary pods)
- Latency returns to normal

---

## ✅ Verification Checklist

After running load test, verify:

### Metrics Collected ✓
- [ ] `active_users` shows peak of ~100
- [ ] `leave_requests_total` increases by ~100
- [ ] `login_attempts_total` shows both successes and failures
- [ ] `http_request_duration_seconds` has histogram data
- [ ] `db_query_duration_seconds` shows database latency

### Performance ✓
- [ ] P95 latency: < 500ms
- [ ] P99 latency: < 1000ms
- [ ] Error rate: < 5%
- [ ] Database P95: < 200ms

### Scaling ✓
- [ ] Pods scaled from 1 → 3-5 during peak
- [ ] HPA events visible: `kubectl describe hpa`
- [ ] CPU/Memory increase observed
- [ ] Pods returned to original count after load stopped

### Application ✓
- [ ] No crashes or restarts: `kubectl get pods`
- [ ] Logs show requests processed: `kubectl logs <pod-name>`
- [ ] Database connections remained stable
- [ ] Errors are acceptable (auth race conditions only)

---

## 🔍 Debugging Issues

### Issue: Metrics not showing in Grafana

**Solution:**
```bash
# 1. Verify Prometheus is scraping
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Visit http://localhost:9090/targets
# Look for job "backend-metrics" with status UP

# 2. Check ServiceMonitor
kubectl get servicemonitor -n monitoring
kubectl describe servicemonitor backend-metrics -n monitoring

# 3. Verify metrics endpoint
kubectl port-forward svc/backend 9464:9464
curl http://localhost:9464/metrics | grep leave_requests_total
```

### Issue: Error rate too high (>10%)

**Solution:**
```bash
# Check application logs
kubectl logs <backend-pod-name>

# Look for:
- Database connection errors
- Authentication errors
- Memory/resource exhaustion

# If database issue:
kubectl get pvc
kubectl top pod  # Check resource usage
```

### Issue: Pods not scaling

**Solution:**
```bash
# Check HPA status
kubectl get hpa backend-hpa
kubectl describe hpa backend-hpa

# Check current resources
kubectl top pod

# Manual trigger if needed (requires setting CPU threshold lower)
```

---

## 📊 Grafana Query Reference

### Latency Queries
```promql
# Response time percentiles
- P50: histogram_quantile(0.50, http_request_duration_seconds_bucket)
- P95: histogram_quantile(0.95, http_request_duration_seconds_bucket)
- P99: histogram_quantile(0.99, http_request_duration_seconds_bucket)

# Convert to milliseconds
histogram_quantile(0.95, http_request_duration_seconds_bucket) * 1000

# By endpoint
histogram_quantile(0.95, http_request_duration_seconds_bucket) by (endpoint)
```

### Business Logic Queries
```promql
# Active users
active_users

# Leave requests
rate(leave_requests_total[1m])          # Per second
leave_requests_total                     # Total

# Login success rate
rate(login_attempts_total{result="success"}[1m]) / 
(rate(login_attempts_total{result="success"}[1m]) + 
 rate(login_attempts_total{result="failure"}[1m]))
```

### Error Queries
```promql
# Error rate percentage
(rate(http_errors_total[5m]) / rate(http_requests_by_endpoint[5m])) * 100

# Errors by status
http_errors_total{status="500"}
http_errors_total{status="401"}
```

---

## 🎯 Success Criteria

Your load test is **SUCCESSFUL** if:

| Criteria | Target | Result |
|----------|--------|--------|
| **Peak Users** | 100 users | ✓ |
| **P95 Latency** | <500ms | ✓ |
| **Error Rate** | <5% | ✓ |
| **Pod Scaling** | 1→3-5 pods | ✓ |
| **Pod Stability** | No crashes/restarts | ✓ |
| **Metrics Collected** | All metrics present | ✓ |
| **Database Latency** | <200ms P95 | ✓ |
| **Success Rate** | >95% | ✓ |

---

## 📚 Load Test Files

| File | Purpose |
|------|---------|
| `script.js` | Basic load test (up to 50 users) |
| `advanced-scenario.js` | Full scenario with 100 users |
| `LOAD_TEST_GUIDE.md` | This file |

---

## 🚀 Next Steps

1. **Run local test first**: `k6 run script.js` (quick validation)
2. **Deploy to EKS**: Terraform should be applied
3. **Set up Grafana dashboard**: Use panel queries above
4. **Run full 100-user test**: `k6 run advanced-scenario.js`
5. **Monitor metrics**: Watch Grafana during test
6. **Verify HPA**: Check if pods scaled
7. **Analyze results**: Review latency, errors, throughput
8. **Document findings**: Keep metrics snapshots

---

## 📞 Troubleshooting

**K6 not installed?**
```bash
# Download and install k6
# Windows: https://dl.k6.io/msi/k6-latest-amd64.msi
# Mac: brew install k6
# Linux: sudo apt-get install k6
```

**k6 command not found?**
```bash
# Try full path
/usr/local/bin/k6 run script.js

# Or run with Docker
docker run -i --network=host grafana/k6 run - < script.js
```

**Backend metrics not updating?**
```bash
# Restart backend to trigger metrics collection
kubectl rollout restart deployment/backend

# Wait 30 seconds for Prometheus to start scraping
sleep 30
```

---

## 🎉 You're All Set!

Everything is ready to test 100 concurrent users. The test will:
- ✅ Create 100 realistic user journeys
- ✅ Execute registration, login, leave request operations
- ✅ Collect detailed performance metrics
- ✅ Show scaling in action (HPA)
- ✅ Display all metrics in Grafana dashboard

**Run the test**: `k6 run load-test/advanced-scenario.js`

Good luck! 🚀
