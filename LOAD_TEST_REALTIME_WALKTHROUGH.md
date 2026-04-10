# Real-Time Load Test Walkthrough - What You'll See

## 📊 Exact Sequence of Events (Minute by Minute)

### **MINUTE 0-2: Starting Up (Warm-up begins)**

```bash
# Terminal 5: k6 running
starting slow ramp-up...
     vus: 1,   duration: 2m0s, remaining: 22m0s, rate: 0.50VU/15s

# Terminal 4: kubectl watching pods
NAME                      READY   STATUS    RESTARTS   AGE
backend-7c6d9f4d94-xt5zp   1/1     Running   0          3h

# Terminal 1: Grafana Dashboard
Active Users: 1 ⟵ (needle just moved)
Request Rate: 0.5 req/sec
Latency P95: 120ms
Error Rate: 0%
Leave Requests: 0
Pod Count: 1
```

**What's happening:**
- k6 starting its first user
- Grafana showing first blip
- Single pod handling everything
- Database gets first query

---

### **MINUTE 2-5: Ramping Up (Warm-up continues)**

```bash
# Terminal 5: k6
     vus: 8,   duration: 2m0s, remaining: 19m0s, rate: 4VU/15s
     iterations: 2, ✓: 2, ✗: 0

# Terminal 4: kubectl watching
NAME                      READY   STATUS    RESTARTS   AGE
backend-7c6d9f4d94-xt5zp   1/1     Running   0          3h

# Terminal 1: Grafana Dashboard  
Active Users: 8 ↗️
Request Rate: 3-5 req/sec ↗️
Latency P95: 150ms
Error Rate: 0%
Leave Requests: 2 ↗️  (Users registered successfully!)
Pod Count: 1
```

**What's happening:**
- More users arriving
- Request rate increasing
- First leave requests appearing (users registered + logged in)
- Still 1 pod
- Latency still good

---

### **MINUTE 5-8: Heavy Ramp-Up (Peak ramp begins)**

```bash
# Terminal 5: k6
     vus: 25,  duration: 5m0s, remaining: 17m0s, rate: 2.5VU/s
     iterations: 12, ✓: 12, ✗: 0

# Terminal 4: kubectl watching ...
NAME                      READY   STATUS    RESTARTS   AGE
backend-7c6d9f4d94-xt5zp   1/1     Running   0          3h
backend-7c6d9f4d94-9k2lm   1/1     Running   0          1m ← NEW POD!

# Terminal 1: Grafana Dashboard
Active Users: 25 ↗️↗️
Request Rate: 12-18 req/sec ↗️↗️
Latency P95: 220ms
Error Rate: 1%
Leave Requests: 24 ↗️↗️
Pod Count: 2 ↗️  (HPA detected load!)
CPU: Pod1=65%, Pod2=45%
```

**What's happening:**
- 25 users now active
- HPA detected CPU spike
- Second pod automatically created! ✓
- Latency creeping up but still good
- Leave requests climbing

---

### **MINUTE 8-10: Approaching Peak (Getting intense)**

```bash
# Terminal 5: k6
     vus: 50,  duration: 5m0s, remaining: 13m0s, rate: 5VU/s
     iterations: 28, ✓: 28, ✗: 0

# Terminal 4: kubectl watching ...
NAME                      READY   STATUS    RESTARTS   AGE
backend-7c6d9f4d94-xt5zp   1/1     Running   0          3h
backend-7c6d9f4d94-9k2lm   1/1     Running   0          3m
backend-7c6d9f4d94-4m8np   1/1     Running   0          45s ← NEW POD!

# Terminal 1: Grafana Dashboard
Active Users: 50 ↗️↗️↗️
Request Rate: 28-35 req/sec ↗️↗️↗️
Latency P95: 320ms
Error Rate: 2-3%
Leave Requests: 48 ↗️↗️↗️
Pod Count: 3 ↗️↗️
CPU: Pod1=75%, Pod2=68%, Pod3=52%
Memory: 320MB each
```

**What's happening:**
- 50 users active
- Third pod created automatically
- Request rate climbing
- Latency increasing but still under 500ms ✓
- 48 leave requests submitted

---

### **MINUTE 10-12: PEAK LOAD BEGINS! 🚀 (THIS IS IT!)**

```bash
# Terminal 5: k6
     vus: 75,  duration: 10m0s, remaining: 11m0s, rate: 2.5VU/s
     iterations: 45, ✓: 44, ✗: 1

# Terminal 4: kubectl watching ...
NAME                      READY   STATUS    RESTARTS   AGE
backend-7c6d9f4d94-xt5zp   1/1     Running   0          3h
backend-7c6d9f4d94-9k2lm   1/1     Running   0          5m
backend-7c6d9f4d94-4m8np   1/1     Running   0          2m
backend-7c6d9f4d94-kh3xs   1/1     Running   0          30s ← NEW POD!
backend-7c6d9f4d94-jq9rt   0/1     Pending  0          5s  ← ANOTHER COMING!

# Terminal 1: Grafana Dashboard
Active Users: 75 ⟶ 85 ⟶ 95 ↗️↗️↗️
Request Rate: 40-48 req/sec ↗️↗️↗️
Latency P95: 380ms (Still under 500! ✓)
Error Rate: 2-4%
Leave Requests: 72 ↗️↗️↗️
Pod Count: 4 ↗️↗️↗️ (and more coming!)
CPU: Distributed across 4 pods now
Memory: Stable at 350MB each
DB P95: 145ms (Database handling it!)
```

**What's happening:**
- 75 users active now, racing to 100
- 4 pods running, 5th pod being scheduled
- Request rate is intense: 40+ req/sec
- **LATENCY HOLDING UNDER 500ms DESPITE 75+ USERS!** ✓✓✓
- Database not overwhelmed
- **SCALING IS WORKING PERFECTLY!** 🎯

---

### **MINUTE 12-15: FULL PEAK LOAD (100 concurrent users!)**

```bash
# Terminal 5: k6
     vus: 100, duration: 10m0s, remaining: 8m0s
     iterations: 58, ✓: 57, ✗: 1

# Terminal 4: kubectl watching ...
NAME                      READY   STATUS    RESTARTS   AGE
backend-7c6d9f4d94-xt5zp   1/1     Running   0          3h
backend-7c6d9f4d94-9k2lm   1/1     Running   0          8m
backend-7c6d9f4d94-4m8np   1/1     Running   0          5m
backend-7c6d9f4d94-kh3xs   1/1     Running   0          3m
backend-7c6d9f4d94-jq9rt   1/1     Running   0          2m ← NOW RUNNING

# Terminal 1: Grafana Dashboard
Active Users: 100 ← 100% PEAK! 🎯✓
Request Rate: 52-58 req/sec ← MAXIMUM THROUGHPUT! 🎯✓
Latency P50: 180ms
Latency P95: 420ms ← STILL UNDER 500ms! 🎯✓
Latency P99: 750ms ← Acceptable for peak
Error Rate: 3-4% ← Low error rate at peak! 🎯✓
Leave Requests: 98-100 ← ALL USERS SUBMITTED LEAVES! 🎯✓
Pod Count: 5 ← MAXIMUM SCALE REACHED! 🎯✓
CPU per Pod: 60-75% ← Distributed load
Memory per Pod: 350-380MB ← Stable (no leaks)
DB P95: 155ms ← Database keeping up!
Login Success: 98% ← Auth working great!
Registration Time: 250ms avg ← Fast
Leave Request Time: 180ms avg ← Very fast
View Leaves Time: 150ms avg ← Fast
```

**Terminal 3 Metrics Output:**
```
active_users 100
leave_requests_total 100
latency_histogram_bucket{le="100"} 25
latency_histogram_bucket{le="200"} 45
latency_histogram_bucket{le="500"} 95
latency_histogram_bucket{le="1000"} 98
login_attempts_total 100
login_duration_seconds 0.25
error_rate 0.034
register_duration_seconds 0.35
http_request_duration_seconds_bucket 97
```

**What's happening:**
- **✅ 100 CONCURRENT USERS ACTIVE!**
- **✅ 5 PODS RUNNING (scaled from 1)!**
- **✅ LATENCY UNDER 500ms P95!**
- **✅ 100 LEAVE REQUESTS SUBMITTED!**
- **✅ ERROR RATE UNDER 5%!**
- **✅ DATABASE NOT OVERWHELMED!**
- **✅ NO POD CRASHES OR RESTARTS!**
- **✅ METRICS FLOWING TO GRAFANA!**

```
THIS IS THE SUCCESS POINT! 🎉
Everything is working together perfectly!
```

---

### **MINUTE 15-18: SUSTAINED PEAK (Still at 100 users)**

```bash
# Terminal 5: k6
     vus: 100, duration: 10m0s, remaining: 5m0s
     iterations: 102, ✓: 100, ✗: 2

# Terminal 4: kubectl watching ...
NAME                      READY   STATUS    RESTARTS   AGE
backend-7c6d9f4d94-xt5zp   1/1     Running   0          3h
backend-7c6d9f4d94-9k2lm   1/1     Running   0          11m
backend-7c6d9f4d94-4m8np   1/1     Running   0          8m
backend-7c6d9f4d94-kh3xs   1/1     Running   0          6m
backend-7c6d9f4d94-jq9rt   1/1     Running   0          5m

# Terminal 1: Grafana Dashboard
Active Users: 100 (steady)
Request Rate: 54 req/sec (steady)
Latency P95: 430ms (stable)
Error Rate: 3% (stable)
Leave Requests: 102 (some users making multiple requests)
Pod Count: 5 (stable, no more scaling)
Database: Performing well, P95: 140ms
```

**What's happening:**
- System is now in **steady state**
- All 5 pods handling load evenly
- Latency stable (no degradation)
- Error rate stable (acceptable)
- **System is SUSTAINABLE at 100 concurrent!** ✓

---

### **MINUTE 18-20: End of Peak (Cooling down begins)**

```bash
# Terminal 5: k6
     vus: 50,  duration: 5m0s, remaining: 3m0s
     iterations: 108, ✓: 106, ✗: 2

# Terminal 4: kubectl watching ...
NAME                      READY   STATUS    RESTARTS   AGE
backend-7c6d9f4d94-xt5zp   1/1     Running   0          3h
backend-7c6d9f4d94-9k2lm   1/1     Running   0          13m
backend-7c6d9f4d94-4m8np   1/1     Running   0          10m
backend-7c6d9f4d94-kh3xs   1/1     Running   0          8m
(backend-7c6d9f4d94-jq9rt will be removed by HPA)

# Terminal 1: Grafana Dashboard
Active Users: 50 ↘️
Request Rate: 28 req/sec ↘️
Latency P95: 250ms ↘️
Error Rate: 1% ↘️
Leave Requests: 108 (final)
Pod Count: 4 ↘️ (HPA removing one pod)
```

**What's happening:**
- Load decreasing
- HPA detecting lower CPU
- Removing extra pods automatically
- Latency improving with lower load
- System returning to baseline

---

### **MINUTE 20-23: Test Completion (Final cooldown)**

```bash
# Terminal 5: k6
FINAL RESULTS:
✓ 110 iterations in 23m
✓ Success rate: 98.2%
✓ Errors: 2 (auth race conditions - acceptable)
✓ Requests: 5,280 total
✓ Data transferred: 2.1 GB
✓ Request rate: avg 3.8 req/sec

# Thresholds:
✓ P95 < 500ms? YES (avg 380ms)
✓ P99 < 1000ms? YES (avg 720ms)
✓ Error rate < 10%? YES (1.8%)
✓ Http requests > 50? YES (5,280)

# Terminal 4: kubectl watching ...
NAME                      READY   STATUS    RESTARTS   AGE
backend-7c6d9f4d94-xt5zp   1/1     Running   0          3h
backend-7c6d9f4d94-9k2lm   1/1     Running   0          15m
backend-7c6d9f4d94-4m8np   1/1     Running   0          12m
(Other pods have terminated)

# Terminal 1: Grafana Dashboard
Active Users: 0 (test complete)
Request Rate: 0 req/sec
Leave Requests: 110 (final count)
Pod Count: 2 ↘️ (scaled back)
```

**What's happening:**
- **✅ TEST COMPLETED SUCCESSFULLY!**
- **✅ 110 ITERATIONS EXECUTED!**
- **✅ 5,280 REQUESTS PROCESSED!**
- **✅ PODS SCALED DOWN AUTOMATICALLY!**
- **✅ ALL THRESHOLDS MET!**

---

## 🎯 Expected Results Summary

```
┌─────────────────────────────────────────────────────────────────┐
│ LOAD TEST RESULTS - 100 Concurrent Users (23 minutes)          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ Test Iterations:              110                              │
│ Total Requests:               5,280                            │
│ Data Transferred:             2.1 GB                           │
│ Test Duration:                23 minutes                       │
│ Peak Concurrent Users:        100                              │
│                                                                 │
│ ✅ SUCCESS RATE:              98.2%                            │
│ ✅ ERROR RATE:                1.8% (2 errors)                 │
│ ✅ LATENCY P50:               180ms                            │
│ ✅ LATENCY P95:               380ms (< 500ms ✓)               │
│ ✅ LATENCY P99:               720ms (< 1000ms ✓)              │
│                                                                 │
│ ✅ POD SCALING:               1 → 5 → 1                        │
│ ✅ CPU EFFICIENCY:            60-75% per pod                   │
│ ✅ MEMORY STABILITY:          350MB per pod (no leaks)         │
│ ✅ DATABASE P95:              155ms                            │
│ ✅ LEAVE REQUESTS:            110 submitted                    │
│                                                                 │
│ 🎯 ALL OBJECTIVES MET! 🎉                                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📈 The Four Key Graphs You'll See

### Graph 1: Active Users (Should look like this)
```
│120├─────────────────────
│100├──────────────┏━━━━━━
│ 80├────────┏━━━━━┛
│ 60├────┏━━━┛
│ 40├──┏━┛
│ 20├┏━┘
│  0└┴──────────────────────→ Time (minutes)
```

### Graph 2: Pod Count (Should look like this)
```
│  6├─────────────────────
│  5├──────────────┏━━━━━━
│  4├────────┏━━━━━┛
│  3├────┏━━━┛
│  2├──┏━┛
│  1├┏━┛
│  0└┴──────────────────────→ Time (minutes)
```

### Graph 3: Latency P95 (Should look like this)
```
│800├────────────────────
│600├──────────┏━━━━━━━━━
│400├──────┏━━━┛
│200├──┏━━━┛
│  0└┴─────────────────────→ Time (minutes)
     └ Target: < 500ms
```

### Graph 4: Error Rate (Should look like this)
```
│ 10├────────────────────
│  8├──────────┏━━━━━━
│  6├────┏━━━━━┛
│  4├──┏━┛
│  2├┏━┘
│  0└┴──────────────────────→ Time (minutes)
    └ Target: < 10%
```

---

## ✅ Final Verification Checklist

After test completes, verify these in order:

```
k6 Results:
  ☐ Success rate > 95%
  ☐ P95 latency < 500ms
  ☐ Error rate < 10%
  ☐ Total iterations > 100

Kubernetes:
  ☐ Pods scaled from 1 to 3+ (check "Age")
  ☐ No pod restarts (check "RESTARTS")
  ☐ No failed pods (all "1/1 Running")
  ☐ HPA events present (kubectl describe hpa -n default)

Grafana Dashboard:
  ☐ Active users maxed at ~100
  ☐ Request rate reached 50+ req/sec
  ☐ Latency P95 stayed under 500ms
  ☐ Error rate stayed under 5%
  ☐ Leave requests reached ~100
  ☐ Pod count shows: 1→5→1 timeline

Metrics:
  ☐ active_users = 100 at peak
  ☐ leave_requests_total = 110
  ☐ login_attempts_total = 110
  ☐ error_rate < 0.05
  ☐ latency_histogram has data

Logs & Traces:
  ☐ Loki has pod logs from test period
  ☐ Tempo has trace data visible
  ☐ No error spikes in logs
  ☐ Pods show successful request processing

Database:
  ☐ MySQL pod still running
  ☐ Leave requests in database = 110
  ☐ Users in database = 110+
  ☐ No connection errors in logs
```

---

## 🎉 SUCCESS! What This Proves

When everything checks out, you've proven:

✅ **Performance**: System handles 100 concurrent users with latency < 500ms
✅ **Reliability**: 98%+ success rate, error handling working
✅ **Scalability**: Pod autoscaling triggered automatically (1 → 5)
✅ **Stability**: No crashes, memory stable, database not overwhelmed
✅ **Observability**: All metrics collected and visualized in Grafana
✅ **Realistic Testing**: Actual user workflows tested (register, login, leave requests)

---

## 🚨 If Something Goes Wrong

```
Problem: Active users don't reach 100
  → Check: k6 running? Check error logs in terminal 5
  → Solution: Might be network connectivity to backend

Problem: Pods don't scale
  → Check: metrics-server installed? (kubectl get deployment -n kube-system)
  → Check: HPA thresholds correct? (kubectl get hpa)
  → Solution: May need to adjust CPU usage in HPA

Problem: Latency exceeds 500ms
  → Check: Database query time in Prometheus
  → Check: Pod CPU at 100%? May need more resources
  → Solution: May need to tune application or database indexes

Problem: Error rate > 10%
  → Check: k6 logs in terminal 5
  → Solution: Check backend logs (kubectl logs -l app=backend)

Problem: No metrics in Grafana
  → Check: Prometheus scraping? (http://localhost:9090)
  → Check: Backend pod metrics endpoint? (port-forward and curl)
  → Solution: Verify ServiceMonitor configured correctly

All resolved? Restart from beginning. If still issues, check docs.
```

---

You're now ready to witness your system handle 100 concurrent users! Run those 5 terminals and enjoy watching everything work together. 🚀
