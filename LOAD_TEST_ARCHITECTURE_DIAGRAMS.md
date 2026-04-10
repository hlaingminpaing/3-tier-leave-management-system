# Load Testing Architecture & Flow Diagrams

## System Architecture During Load Test

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Load Test Execution (k6)                            │
│  (Your laptop/EC2)                                                           │
│  ├─ 100 Virtual Users (VUs)                                                │
│  ├─ Each: Register → Login → Apply Leave → View Leaves                    │
│  └─ Duration: 23 minutes (Ramp: 2m, Ramp: 5m, Peak: 10m, Maintain: 5m)   │
└────────────────────────┬────────────────────────────────────────────────────┘
                         │ HTTP Requests (Thousands of requests)
                         ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│                    AWS EKS Cluster (Kubernetes 1.35)                        │
│                    ap-southeast-1 Region                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────┐        │
│  │  Default Namespace                                              │        │
│  ├────────────────────────────────────────────────────────────────┤        │
│  │                                                                 │        │
│  │  ┌─ Pod 1 (backend) ─┐   ┌─ Pod 2 (backend) ─┐   ┌─ Pod 3 (backend) ─┐ │
│  │  │ :3000 (API)       │   │ :3000 (API)       │   │ :3000 (API)       │ │
│  │  │ :9464 (Metrics)   │   │ :9464 (Metrics)   │   │ :9464 (Metrics)   │ │
│  │  └───────────────────┘   └───────────────────┘   └───────────────────┘ │
│  │                                                                 │        │
│  │  ┌─ MySQL Pod ──────────┐ ← All pods query here              │        │
│  │  │ :3306 (Database)     │                                     │        │
│  │  └───────────────────────┘                                    │        │
│  │                                                                 │        │
│  │  ┌─ HPA Controller ──────┐                                     │        │
│  │  │ Monitors CPU/Memory   │ → Scales pods: 1 → 3 → 5          │        │
│  │  └───────────────────────┘                                    │        │
│  │                                                                 │        │
│  └────────────────────────────────────────────────────────────────┘        │
│                         │         │         │                              │
│                         ↓         ↓         ↓                              │
│  ┌────────────────────────────────────────────────────────────────┐        │
│  │  Monitoring Namespace                                           │        │
│  ├────────────────────────────────────────────────────────────────┤        │
│  │                                                                 │        │
│  │  ┌─ Prometheus ──────────────┐   (Scrapes :9464/metrics)      │        │
│  │  │ • Stores time series data │ ← 20 custom metrics collected  │        │
│  │  │ • 50Gi storage            │                                 │        │
│  │  └───────────────────────────┘                                │        │
│  │            │                                                   │        │
│  │            ↓                                                   │        │
│  │  ┌─ Grafana ─────────────────┐   (Visualizes data)            │        │
│  │  │ • 8 dashboards panels     │ ← Every metric visible         │        │
│  │  │ • Live metrics: :3000     │                                 │        │
│  │  └───────────────────────────┘                                │        │
│  │                                                                 │        │
│  │  ┌─ Loki ────────────────────┐   (Collects logs)              │        │
│  │  │ • Pod logs aggregation    │ ← All output captured          │        │
│  │  │ • 10Gi storage            │                                 │        │
│  │  └───────────────────────────┘                                │        │
│  │                                                                 │        │
│  │  ┌─ Tempo ───────────────────┐   (Traces)                     │        │
│  │  │ • Distributed tracing     │ ← Request flows captured       │        │
│  │  │ • OTLP endpoint :4318     │                                 │        │
│  │  └───────────────────────────┘                                │        │
│  │                                                                 │        │
│  └────────────────────────────────────────────────────────────────┘        │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
                                         │
                                         ↓
                    ┌──────────────────────────────┐
                    │  AWS Load Balancer (ALB)     │
                    │  health checks + routing     │
                    └──────────────────────────────┘
```

---

## Request Flow During Load Test

```
k6 Virtual User (×100)
        │
        ├─ Create Http Request
        │  ├─ POST /api/register
        │  ├─ POST /api/login  
        │  ├─ POST /api/leave  
        │  └─ GET /api/leave   
        │
        ↓
    ALB (Application Load Balancer)
        │ Distributes traffic
        │
        ├─→ Backend Pod 1 (:3000 API Port)     ← Scales from 1 to 5
        │   │
        │   ├─ Process request
        │   ├─ Query MySQL
        │   ├─ Emit metrics (:9464)
        │   ├─ Send traces to Tempo
        │   └─ Log to stdout → Loki
        │
        ├─→ Backend Pod 2
        │   └─ (Same as Pod 1)
        │
        ├─→ Backend Pod 3  ← Scaled by HPA during peak
        │   └─ (Same as Pod 1)
        │
        ├─→ Backend Pod 4  ← More pods created as load increases
        │   └─ (Same as Pod 1)
        │
        └─→ Backend Pod 5  ← Peak scaling (if needed)
            └─ (Same as Pod 1)

    ↓ (All pods)
    
    MySQL Database (:3306)
        │ Shared by all pods
        │ Connection Pool: 10-20 connections
        │
        ├─ Store users
        ├─ Store leave requests
        └─ Serve queries

    ↓ (Metrics, Logs, Traces)
    
    ┌─ Prometheus ──────────────────────────────┐
    │ Stores: active_users, leave_requests_total│
    │ Updates every 30s (ServiceMonitor)        │
    └──────────────────────────────────────────┘
           │ (Queried for visualization)
           ↓
    ┌─ Grafana Dashboard ───────────────────────┐
    │ Displays: Active Users, Latency, Errors   │
    │ Updated every 5-10 seconds (live)        │
    └──────────────────────────────────────────┘
```

---

## Metrics Collection During Test

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Metrics Timeline (23 minutes)                         │
└─────────────────────────────────────────────────────────────────────────┘

│
│ 120 ┤                                                               ┏━━━━━━
│ 100 ┤                                                        ┏━━━━━━┛
│  80 ┤                                                 ┏━━━━━━┛
│  60 ┤                                          ┏━━━━━━┛
│  40 ┤                                   ┏━━━━━━┛
│  20 ┤ ┌─────────────────────────────────┛            Ramp Down
│   0 ├─┴──────────────────────────────────────────────────────────
│     └──────────────────────────────────────────────────────────────
│     0   5   10   15   20   25 (minutes)
│
│     ├ Warm-up  ├ Ramp-up ├ Peak Load   ├ Cool-down ┤
│     │ (0-5m)   │ (5-10m) │ (10-20m)    │ (20-25m)  │
│     │          │         │ ← 100 users │           │
│
└─────────────────────────────────────────────────────────────────────────┘

    Active Users Metric (What you see in Grafana):
    ┌─────────────────────────────────────────────────────────────┐
    │ 120 │                                                      ▲ │
    │ 100 │                                              ▲   ▲ │ │ │
    │  80 │                                        ▲ ▲ │ │ │ │ │ │
    │  60 │                                  ▲ ▲ │ │ │ │ │ │ │ │ │
    │  40 │                            ▲ ▲ │ │ │ │ │ │ │ │ │ │ │ │
    │  20 │ ▲ ▲ ▲ ▲ ▲ ▲ ▲ ▲ ▲ ▲ ▲▲ │ │ │ │ ││ │├┘ └┘ └┘
    │   0 └─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─
    │     0   5  10  15  20  25 (minutes)
    └─────────────────────────────────────────────────────────────┘
    
    Pod Count (HPA Scaling):
    ┌─────────────────────────────────────────────────────────────┐
    │ 6 │                                                         │
    │ 5 │                                              ─────      │
    │ 4 │                                        ─────┘           │
    │ 3 │                                  ─────┘                 │
    │ 2 │                            ─────┘                       │
    │ 1 │ ─────────────────────────┘                             │
    │ 0 └─────────────────────────────────────────────────────────
    │   0   5  10  15  20  25 (minutes)
    └─────────────────────────────────────────────────────────────┘
    
    Latency P95 (ms):
    ┌─────────────────────────────────────────────────────────────┐
    │ 800ms────────────────────────────────┐                      │
    │ 600ms                          ┌─────┘                      │
    │ 400ms                  ┌───────┘                            │
    │ 200ms ┌────────────────┘                                    │
    │   0ms └─────────────────────────────────────────────────────
    │      0   5  10  15  20  25 (minutes)
    │      └Target: < 500ms ✓
    └─────────────────────────────────────────────────────────────┘
```

---

## Dashboard Layout (What You'll See)

```
┌───────────────────────────────────────────────────────────────────────────────┐
│                    Load Test - 100 Users Dashboard                            │
│                          (Grafana Dashboard)                                   │
├───────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│  ┌─ Active Users ─────────┐  ┌─ Request Rate ──────────┐  ┌─ Pod Count ────┐│
│  │     Gauge               │  │   Time Series            │  │     Stat       ││
│  │      100/120            │  │   req/sec                │  │      5/5       ││
│  │                         │  │   ▁▂▃▄▅▆▇█▆▇▅▄▃▂▁      │  │                ││
│  │     (GREEN)             │  │                         │  │  (Pods scaled) ││
│  └─────────────────────────┘  └─────────────────────────┘  └────────────────┘│
│                                                                                │
│  ┌─ Latency P95 (ms) ────────┐  ┌─ Error Rate (%) ──────────┐               │
│  │   Time Series              │  │   Time Series              │               │
│  │   420ms ━━━╮               │  │   3.2% ┌╮                  │               │
│  │   300ms    ╰╮┌╮            │  │   2.0% │╰╮                 │               │
│  │   200ms     ╰╯ (below 500) │  │   0.0% └──(below 5%) ✓    │               │
│  │                            │  │                            │               │
│  └────────────────────────────┘  └────────────────────────────┘               │
│                                                                                │
│  ┌─ Leave Requests Total ────────┐  ┌─ DB Query P95 (ms) ────┐              │
│  │   Stat (Big Number)            │  │   Time Series            │              │
│  │     100                        │  │   180ms ─────            │              │
│  │   (Leave requests submitted)  │  │   100ms      ──          │              │
│  │                                │  │    50ms        ─         │              │
│  └────────────────────────────────┘  └────────────────────────┘              │
│                                                                                │
└───────────────────────────────────────────────────────────────────────────────┘

All metrics update live as load test runs!
```

---

## Terminal Monitoring Setup

```
┌─── Terminal 1 ────────────────────────────────┐
│ kubectl port-forward -n monitoring svc/...grafana 3000:80
│ → Grafana Dashboard: http://localhost:3000
│ → Watch all metrics live in real-time
└────────────────────────────────────────────────┘

┌─── Terminal 2 ────────────────────────────────┐
│ kubectl port-forward -n monitoring svc/...prometheus 9090:9090
│ → Prometheus Query Engine: http://localhost:9090
│ → Test queries directly: active_users, leave_requests_total
└────────────────────────────────────────────────┘

┌─── Terminal 3 ────────────────────────────────┐
│ kubectl port-forward svc/backend 9464:9464
│ watch 'curl -s http://localhost:9464/metrics | grep TYPE | head'
│ → See live metrics from backend
└────────────────────────────────────────────────┘

┌─── Terminal 4 ────────────────────────────────┐
│ watch -n 2 'kubectl get pods -l app=backend'
│ → See pods scaling in real-time:
│   NAME              READY   STATUS    RESTARTS   AGE
│   backend-0         1/1     Running   0          5m
│   backend-1         1/1     Running   0          4m  ← Added by HPA
│   backend-2         1/1     Running   0          3m  ← Added by HPA
│   backend-3         1/1     Running   0          2m  ← Added by HPA
│   backend-4         1/1     Running   0          1m  ← Added by HPA
└────────────────────────────────────────────────┘

┌─── Terminal 5 ────────────────────────────────┐
│ cd load-test && k6 run advanced-scenario.js
│ → Starts load test with 100 concurrent users
│ → Shows live progress, final results
│ → Test runs for ~23 minutes
└────────────────────────────────────────────────┘
```

---

## Test Stages & Expected Behavior

```
┌──────────────────────────────────────────────────────────────────────────┐
│ STAGE 1: WARM-UP (Minutes 0-5)                                         │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  k6 Actions:                                                            │
│  • Start with 0 users, ramp to 10 users                               │
│  • Each user: Register → attempt to register (may fail if duplicate)   │
│                                                                          │
│  Expected Metrics:                                                      │
│  • active_users: 0 → 10                                                │
│  • Request rate: 1-5 req/sec                                           │
│  • Latency: 100-200ms ✓                                                │
│  • Error rate: ~0%                                                      │
│  • Pod count: 1                                                         │
│                                                                          │
│  What to Watch:                                                         │
│  ✓ Grafana active_users gauge starts climbing                          │
│  ✓ Prometheus scraping working                                         │
│  ✓ No pod restarts                                                      │
│  ✓ Database connection successful                                       │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│ STAGE 2: RAMP-UP (Minutes 5-10)                                        │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  k6 Actions:                                                            │
│  • Ramp from 10 to 50 users                                            │
│  • Users: Register → Login → Apply Leave → View Leaves                │
│                                                                          │
│  Expected Metrics:                                                      │
│  • active_users: 10 → 50                                               │
│  • Request rate: 5-25 req/sec                                          │
│  • Latency: 200-300ms ✓                                                │
│  • Error rate: 1-3%                                                    │
│  • Pod count: 2-3 (HPA may trigger)                                    │
│  • leave_requests_total: ~50                                           │
│                                                                          │
│  What to Watch:                                                         │
│  ✓ Active users climbing                                               │
│  ✓ Latency creeping up (but still acceptable)                          │
│  ✓ Leave requests counter increasing                                   │
│  ✓ HPA potentially scaling pods                                        │
│  ✓ Database queries staying fast                                       │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│ STAGE 3: PEAK LOAD (Minutes 10-20) ← CRITICAL OBSERVATION POINT       │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  k6 Actions:                                                            │
│  • Ramp from 50 to 100 users rapidly                                   │
│  • Maintain 100 concurrent users for 10 minutes                        │
│  • This is the stress test!                                            │
│                                                                          │
│  Expected Metrics:                                                      │
│  • active_users: ~100 ✓✓✓ (Main objective!)                           │
│  • Request rate: 50+ req/sec ✓✓✓ (High throughput!)                   │
│  • Latency P95: 300-500ms ✓ (Still acceptable)                        │
│  • Error rate: 3-5% (Auth race conditions ok)                          │
│  • Pod count: 3-5 (HPA definitely triggered!) ✓✓✓                     │
│  • leave_requests_total: ~100 (All users submitted)                   │
│  • CPU per pod: 60-80% (Under load but stable)                        │
│  • Memory per pod: 300-400MB (Stable)                                  │
│                                                                          │
│  What to Watch:                                                         │
│  ✓✓✓ Active users gauge maxes out near 100                             │
│  ✓✓✓ Pod count increases 1 → 2 → 3 → 4 → 5                            │
│  ✓ Latency stays below 500ms (watch P95)                               │
│  ✓ Error rate stays below 10%                                          │
│  ✓ Database not overwhelmed (P95 < 200ms)                              │
│  ✓ No pods crashing or restarting                                      │
│  ✓ Logs show requests being processed                                  │
│  ✓ Tempo receiving trace data                                          │
│  ✓ Loki collecting pod logs                                            │
│                                                                          │
│  This is where EVERYTHING comes together!                              │
│  You'll see: Metrics ↗️ Pods ↗️ Load ↗️                                  │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│ STAGE 4: COOL-DOWN (Minutes 20-23)                                     │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  k6 Actions:                                                            │
│  • Stop adding new users                                               │
│  • Ramp down: 100 → 50 → 0                                            │
│  • Test completes                                                       │
│                                                                          │
│  Expected Metrics:                                                      │
│  • active_users: 100 → 0 (Declining)                                   │
│  • Request rate: 50+ → 0 (Declining)                                   │
│  • Latency: Normalizing                                                │
│  • Pod count: 5 → 3 → 2 → 1 (HPA scaling down) ✓                     │
│  • All metrics return to baseline                                       │
│                                                                          │
│  What to Watch:                                                         │
│  ✓ Active users declining                                              │
│  ✓ Pods scaling down (HPA removing extras)                             │
│  ✓ Metrics returning to normal                                         │
│  ✓ Test completes with summary                                         │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Success Verification Flow

```
Test Completes
      │
      ├─→ Check k6 Output
      │   ├─ Success rate > 95%? ✓
      │   ├─ P95 latency < 500ms? ✓
      │   └─ Error rate < 5%? ✓
      │
      ├─→ Check Grafana Dashboard
      │   ├─ Active users hit 100? ✓
      │   ├─ Leave requests ~100? ✓
      │   ├─ Latency acceptable? ✓
      │   └─ Error rate low? ✓
      │
      ├─→ Check Kubernetes
      │   ├─ Pods scaled? (1 → 5 → 1) ✓
      │   ├─ No pod restarts? ✓
      │   └─ HPA events present? ✓
      │
      ├─→ Check Metrics Collection
      │   ├─ Prometheus has data? ✓
      │   ├─ Custom metrics present? ✓
      │   └─ Queries working? ✓
      │
      ├─→ Check Logs & Traces
      │   ├─ Loki has logs? ✓
      │   ├─ Tempo has traces? ✓
      │   └─ Can find requests? ✓
      │
      └─→ LOAD TEST SUCCESSFUL! 🎉
          All systems working end-to-end
          100 concurrent users handled
          Metrics, scaling, observability all verified
```

---

## Performance Expectations at Peak Load (100 VUs)

```
Metric                      Expected Value        What It Means
─────────────────────────────────────────────────────────────────────────
Active Users                ~100                  100 people accessing app
Concurrent Requests/Sec     50+                   High throughput
Latency P50                 100-150ms             Half requests this fast
Latency P95                 300-450ms             95% this fast (target <500)
Latency P99                 600-900ms             Slowest 1% this slow
Error Rate                  3-5%                  Low errors
Success Rate                95-97%                Most requests succeed
Login Success %             98%+                  Auth working
Leave Requests              ~100                  All users submitted
Database P95 Latency        100-150ms             DB responding fast
Pod Count                   3-5                   Scaled from 1
CPU per Pod                 60-80%                Working hard but stable
Memory per Pod              300-400MB             Stable, no leaks visible
Requests Total              5,000+                Total requests processed
Data Transferred            2-3 GB                Network usage
Test Duration               23 mins               Full test cycle
```

---

## Key Observations You'll Make

1. **Warming up (0-5 min)**
   - "Metrics starting to show in Prometheus"
   - "First users registered and logged in"

2. **Ramping up (5-10 min)**
   - "Active users climbing - now at 30, 40, 50"
   - "Latency starting to increase but still ok"

3. **Peak load (10-20 min) ← THE BEST PART!**
   - "Active users at 100! 🎯"
   - "Request rate spiked to 55 req/sec!"
   - "Pods scaling: backend-1, backend-2, backend-3 appearing!"
   - "HPA triggered at the right time!"
   - "Latency holding under 500ms despite 100 users!"
   - "100 leave requests submitted!"
   - "Database keeping up!"

4. **Cool down (20-23 min)**
   - "Load decreasing as test wraps up"
   - "Pods scaling back down"
   - "Metrics normalizing"
   - "Test completed successfully!"

---

## Real-World Analogy

```
Your Leave System Under Load is like:

🏪 Retail Store Black Friday:
  - k6 = 100 customers entering the store simultaneously
  - Backend Pod = Cashier
  - HPA = Manager hiring more cashiers as lines get long
  - Metrics = Queue length, checkout time, customer count
  - Database = Inventory system
  - Grafana = Manager dashboard showing live stats

Before:  1 cashier, 10 customers max → Slow ❌
Now:     5 cashiers, 100 customers → Fast & Smooth ✓

Your metrics show exactly this happening in real-time!
```

---

All ready! Start your load test and watch everything work together. 🚀
