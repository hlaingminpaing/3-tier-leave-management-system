# Load Test Monitoring Checklist - 100 Concurrent Users

## Pre-Load Test Checklist (Before Running k6)

### ✓ Infrastructure Ready
- [ ] Kubernetes cluster deployed with `terraform apply`
- [ ] Backend pods running: `kubectl get pods -l app=backend`
- [ ] Monitoring namespace exists: `kubectl get namespace monitoring`
- [ ] Prometheus running: `kubectl get pods -n monitoring | grep prometheus`
- [ ] Grafana running: `kubectl get pods -n monitoring | grep grafana`
- [ ] Loki running: `kubectl get pods -n monitoring | grep loki`
- [ ] Tempo running: `kubectl get pods -n monitoring | grep tempo`

### ✓ Metrics Configured
- [ ] Backend metrics endpoint working: 
  ```bash
  kubectl port-forward svc/backend 9464:9464
  curl http://localhost:9464/metrics | grep leave_requests_total
  ```
- [ ] ServiceMonitor deployed: `kubectl get servicemonitor -n monitoring`
- [ ] Prometheus scraping backend: `kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090`
  - Visit http://localhost:9090/targets and check "backend-metrics" status is UP

### ✓ Load Test Tool Ready
- [ ] k6 installed: `k6 version`
- [ ] Load test scripts present:
  ```bash
  ls -la load-test/
  # Should have: script.js, advanced-scenario.js, pre-populated-users.js
  ```
- [ ] Base URL accessible: `curl http://localhost:3000/health`

### ✓ Database Ready
- [ ] MySQL running: `kubectl get pods -l app=mysql`
- [ ] Tables created: `kubectl exec <mysql-pod> -- mysql -u root -p<password> -e "USE leave_app; SHOW TABLES;"`

---

## Load Test Execution Steps

### Step 1: Start Monitoring Infrastructure (5 minutes)

#### Terminal 1: Grafana Dashboard
```bash
# Port forward to Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Then visit http://localhost:3000
# Username: admin
# Password: (from terraform.tfvars, usually: ChangeMeInProductionEnv123!)
```

#### Terminal 2: Prometheus
```bash
# Port forward to Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Visit http://localhost:9090 to query metrics directly
```

#### Terminal 3: Backend Metrics
```bash
# Port forward to backend
kubectl port-forward svc/backend 9464:9464

# Verify live (will update as test runs):
watch -n 1 'curl -s http://localhost:9464/metrics | grep leave_requests_total'
```

#### Terminal 4: Watch Pod Scaling
```bash
# Watch backend pods in real-time
watch -n 2 'kubectl get pods -l app=backend -o wide'

# In another tab: Watch HPA
watch -n 2 'kubectl get hpa'
```

---

### Step 2: Set Up Grafana Dashboard (5 minutes)

With Grafana open (http://localhost:3000):

1. **Create New Dashboard**
   - Click **Dashboards** → **Create** → **New Dashboard**
   - Add the panels listed below

2. **Add Panel: Active Users**
   ```promql
   active_users
   ```
   - Visualization: **Gauge**
   - Title: "Active Users (Concurrent)"
   - Min: 0, Max: 120

3. **Add Panel: Request Rate**
   ```promql
   rate(http_requests_by_endpoint[1m])
   ```
   - Visualization: **Time Series**
   - Title: "Requests Per Second"
   - Legend: Show

4. **Add Panel: Latency P95 (ms)**
   ```promql
   histogram_quantile(0.95, http_request_duration_seconds_bucket) * 1000
   ```
   - Visualization: **Time Series**
   - Title: "Latency P95 (ms)"
   - Alert Threshold: 500ms (red line)

5. **Add Panel: Error Rate (%)**
   ```promql
   (rate(http_errors_total[5m]) / rate(http_requests_by_endpoint[5m])) * 100
   ```
   - Visualization: **Time Series**
   - Title: "Error Rate (%)"
   - Alert Threshold: 5%

6. **Add Panel: Leave Requests Total**
   ```promql
   leave_requests_total
   ```
   - Visualization: **Stat**
   - Title: "Leave Requests Submitted"
   - Units: short

7. **Add Panel: Pod Count**
   ```
   count(up{job="backend-metrics"})
   ```
   - Visualization: **Stat**
   - Title: "Active Backend Pods"

8. **Add Panel: DB Query Latency P95**
   ```promql
   histogram_quantile(0.95, db_query_duration_seconds_bucket) * 1000
   ```
   - Visualization: **Time Series**
   - Title: "DB Query P95 (ms)"

9. **Save Dashboard**
   - Click **Save**
   - Name: "Load Test - 100 Users"

---

### Step 3: Run Load Test (25 minutes)

#### Option A: Advanced Scenario (Recommended for 100 users)
```bash
cd load-test
k6 run advanced-scenario.js
```
- Duration: ~23 minutes (5m warmup + 5m rampup + 10m peak + 3m cooldown)
- Expected to create 100 concurrent users

#### Option B: Pre-Populated Users (If you have pre-created users)
```bash
cd load-test
k6 run pre-populated-users.js
```

#### Option C: Basic Script (Quick test, up to 50 users)
```bash
cd load-test
k6 run script.js
```

**While running, observe in Grafana:**
- [ ] Active users climb toward 100
- [ ] Request rate increases
- [ ] Latency remains acceptable (<500ms)
- [ ] Error rate stays low (<5%)
- [ ] Pod count increases (HPA)

---

### Step 4: Monitor During Test

**Key Observations Timeline:**

**0-5 min (Warm-up):**
- [ ] Active users: 0 → 10
- [ ] Request rate: ~1-5 req/sec
- [ ] Latency: 100-200ms
- [ ] Error rate: ~0%
- [ ] Pods: 1-2

**5-10 min (Ramp-up):**
- [ ] Active users: 10 → 50
- [ ] Request rate: ~10-25 req/sec
- [ ] Latency: 200-300ms
- [ ] Error rate: 1-3%
- [ ] Pods: 2-3

**10-20 min (Peak Load - CRITICAL OBSERVATION):**
- [ ] Active users: ~100
- [ ] Request rate: ~50+ req/sec ← THIS IS KEY!
- [ ] Latency: 300-500ms (acceptable)
- [ ] Error rate: 3-5% (registration/auth conflicts ok)
- [ ] Pods: 3-5 (HPA should trigger!) ← VERIFY THIS!
- [ ] CPU increase visible
- [ ] Memory stable

**20-25 min (Cool-down):**
- [ ] Active users: 100 → 0
- [ ] Metrics return to baseline
- [ ] Pods scale down (HPA removes extras)

---

### Step 5: Collect Results

#### From k6 Terminal Output
```
✓ Login status is 200
✓ Apply leave status is 200
✓ Get leaves status is 200

█ 100 VUs finished
  avg=245ms ← Response time average
  min=45ms
  med=150ms
  max=2500ms
  p(90)=380ms
  p(95)=420ms ← Target: < 500ms
  p(99)=850ms ← Target: < 1000ms
```

#### From Grafana Screenshots
- Capture dashboard during peak load
- Export as PNG for documentation
- Note max active users
- Note latency percentiles
- Verify pods scaled

#### From Prometheus
```
# Query to verify data collected:
- active_users (peak value)
- leave_requests_total (final count)
- http_requests_by_endpoint (peak RPS)
- histogram_quantile(0.95, http_request_duration_seconds_bucket) (latency)
```

---

## Verification Checklist

### ✓ Metrics Collected Successfully
- [ ] `active_users` gauge exists and shows peak count near 100
- [ ] `leave_requests_total` counter exists and increased by ~100
- [ ] `login_attempts_total` shows both success and failure
- [ ] `http_requests_by_endpoint` has request count data
- [ ] `http_request_duration_seconds` has histogram data
- [ ] `leave_approval_rate` has data
- [ ] `db_query_duration_seconds` has data

**Verify with:**
```bash
kubectl port-forward svc/backend 9464:9464
curl -s http://localhost:9464/metrics | grep -E "active_users|leave_requests_total|login_attempts"
```

### ✓ Performance Met Requirements
- [ ] P95 latency: **< 500ms** ✓
- [ ] P99 latency: **< 1000ms** ✓
- [ ] Error rate: **< 5%** ✓
- [ ] Success rate: **> 95%** ✓
- [ ] Min throughput: **> 50 req/sec at peak** ✓

### ✓ Application Scaled Correctly
- [ ] Pod count increased: `kubectl get pods -l app=backend`
  - Before: 1 pod
  - Peak: Should be 3-5 pods
  - After: Back to 1 pod
- [ ] HPA events visible: `kubectl describe hpa backend-hpa`
- [ ] Pods completed requests: `kubectl logs <pod-name> | grep "requests"`
- [ ] No pod crashes: `kubectl get pods -l app=backend` (all Running)
- [ ] No restarts: Check RESTARTS column = 0

**Verify with:**
```bash
kubectl get hpa
kubectl describe hpa backend-hpa
kubectl get events | grep -i scale
```

### ✓ Database Handled Load
- [ ] No connection pool exhaustion
- [ ] Query latency acceptable: < 200ms P95
- [ ] No persistent connection errors
- [ ] MySQL pod stable: `kubectl logs -l app=mysql`

### ✓ Tracing Captured Requests
- [ ] Tempo has trace data
- [ ] Can query by service: "leave-backend"
- [ ] Traces include all operations (login, leave request)

**Verify in Grafana:**
- Go to Explore tab
- Select Tempo datasource
- Service: "leave-backend"
- Click Run Query → Should see traces

---

## Troubleshooting During Load Test

### Issue: Metrics not updating in Grafana

**Check 1: Prometheus scraping**
```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Visit http://localhost:9090/targets
# Look for job="backend-metrics" with status UP (green)
```

**Check 2: Backend pod metrics**
```bash
kubectl port-forward svc/backend 9464:9464
curl http://localhost:9464/metrics | head -20
```

**Check 3: Restart Prometheus scraping**
```bash
kubectl rollout restart deployment/kube-prometheus-stack-operator -n monitoring
sleep 30
```

### Issue: Error rate too high (>10%)

**Check application logs:**
```bash
kubectl logs -f -l app=backend

# Look for patterns:
# - "Database error" → Check MySQL
# - "JWT" → Authorization issue
# - "ECONNREFUSED" → Service connectivity
```

**Check database:**
```bash
kubectl exec -it <mysql-pod> -- mysql -u root -p
SHOW PROCESSLIST;
SHOW STATUS LIKE 'Threads%';
```

### Issue: Pods not scaling

**Check HPA:**
```bash
kubectl get hpa backend-hpa
kubectl describe hpa backend-hpa

# Look for:
# - Current: CPU percentage
# - Events: Any errors?
```

**Check resource requests:**
```bash
kubectl describe pod <backend-pod> | grep -A 5 "Requests"
# Should have CPU/Memory requests set
```

### Issue: Latency spikes above 500ms

**Check pod resources:**
```bash
kubectl top pod -l app=backend
# CPU and Memory usage high?
```

**Check database latency:**
```promql
# In Prometheus:
histogram_quantile(0.95, db_query_duration_seconds_bucket)
```

---

## Post-Load Test Analysis

### Generate Report
```bash
# Save k6 results to JSON
k6 run advanced-scenario.js --out json=results.json

# Parse results
cat results.json | jq '.metrics' | head -50
```

### Key Metrics to Document
```
Document these values for your report:
- Peak concurrent users achieved: ___
- Total requests made: ___
- Average latency (ms): ___
- P95 latency (ms): ___
- P99 latency (ms): ___
- Error rate (%): ___
- Peak pods: ___
- Peak CPU per pod: ___
- Peak Memory per pod: ___
- Total leave requests submitted: ___
- HPA scaling time: ___s (time to scale from 1→5 pods)
```

### Screenshots to Keep
1. Grafana dashboard at peak load
2. Pod scaling in real time
3. Prometheus queries during test
4. HPA events showing scaling

---

## Success Criteria Summary

Your load test is **SUCCESSFUL** if ALL of these are true:

| Item | Requirement | Status |
|------|-------------|--------|
| **Peak Users** | ≥ 100 concurrent | ☐ |
| **Latency P95** | < 500ms | ☐ |
| **Latency P99** | < 1000ms | ☐ |
| **Error Rate** | < 5% | ☐ |
| **Success Rate** | > 95% | ☐ |
| **Pod Scaling** | 1 pod → 3-5 pods | ☐ |
| **Pod Stability** | No crashes, 0 restarts | ☐ |
| **Metrics Collected** | All 20 metrics present | ☐ |
| **DB Latency P95** | < 200ms | ☐ |
| **Leave Requests** | ~100 requests submitted | ☐ |

---

## Output Examples

### Successful k6 Run Output
```
  ✓ Login status is 200
  ✓ Apply leave status is 200
  ✓ Get leaves status is 200
  ✓ Leave response has message
  ✓ Get leaves returns array

  █ 100 VUs max duration exceeded
    5000 requests out of 5000 completed
    0 failed out of 5000 total
    
  checks...................: 98.50% ✓ 4925 ✗ 75
  data_received............: 2.3 MB 51 kB/s
  data_sent................: 1.8 MB 40 kB/s
  http_req_blocked.........: avg=1.2ms   min=100µs  med=400µs  max=125ms p(90)=2ms   p(95)=3ms   p(99)=12ms
  http_req_connecting......: avg=800µs   min=0s     med=0s     max=95ms p(90)=0s     p(95)=0s     p(99)=4ms
  http_req_duration........: avg=245ms   min=45ms   med=150ms  max=2.5s p(90)=380ms  p(95)=420ms  p(99)=850ms
  http_req_receiving.......: avg=1.5ms   min=100µs  med=1ms    max=25ms p(90)=2ms    p(95)=3ms    p(99)=8ms
  http_req_sending.........: avg=350µs   min=100µs  med=300µs  max=12ms p(90)=600µs  p(95)=800µs  p(99)=2ms
  http_req_tls_handshaking: avg=0s       min=0s     med=0s     max=0s   p(90)=0s     p(95)=0s     p(99)=0s
  http_reqs................: 5000    111.111111/s
  http_req_wait............: avg=242ms   min=40ms   med=148ms  max=2.5s p(90)=378ms  p(95)=418ms  p(99)=848ms
  leave_request_duration...: avg=325ms   min=50ms   med=200ms  max=1.8s p(90)=520ms  p(95)=680ms  p(99)=1.1s
  login_duration...........: avg=198ms   min=35ms   med=120ms  max=980ms p(90)=320ms  p(95)=380ms  p(99)=720ms
  active_leave_requests....: 100
  iteration_duration.......: avg=2.3s    min=1.2s   med=2.1s   max=8.4s p(90)=3.2s   p(95)=3.8s   p(99)=5.2s
  iterations..............: 100      2.222222/s
  vus........................: 1       max=100
```

### Successful Grafana Dashboard at Peak
```
Dashboard shows:
- Active Users: 100 (gauge full)
- Request Rate: 55 req/sec
- Latency P95: 420ms (green, below 500ms threshold)
- Error Rate: 3.2%
- Pod Count: 4 pods
- DB Query P95: 145ms
```

---

## Next Steps After Successful Load Test

1. **Document Results**: Keep screenshots and metrics values
2. **Adjust HPA if needed**: If pods scaled too early/late, adjust thresholds
3. **Performance Tune**: If latency high, consider optimization
4. **Production Readiness**: Results indicate system is production-ready
5. **Set Up Alerts**: Configure Grafana alerts based on observed baselines
6. **Schedule Regular Tests**: Retest after deployments

---

## References

- k6 documentation: https://k6.io/docs/
- Load test scripts: See [load-test/](../load-test/) directory
- Metrics guide: See [METRICS_QUERY_GUIDE.md](../METRICS_QUERY_GUIDE.md)
- Monitoring setup: See [LOAD_TEST_COMPLETE_GUIDE.md](../LOAD_TEST_COMPLETE_GUIDE.md)

---

**Ready to test? Start with Step 1! 🚀**
