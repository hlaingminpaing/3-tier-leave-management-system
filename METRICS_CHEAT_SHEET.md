# Metrics Cheat Sheet - Quick Reference

## Business Metrics (Track Your App's Business Logic)

### 1. Active Users - See who's using your app right now
```
Query: active_users
Type: Gauge (current count)
Visualization: Number/Stat (big green box)
Alert: active_users > 1000
Example: "Current users: 45"
```

### 2. Leave Requests - How many leave requests?
```
Query: leave_requests_total
Type: Counter (total ever)
Visualization: Time Series (line chart)
Rate: rate(leave_requests_total[1h])
Example: "5 requests in last hour"
```

### 3. Leave by Status - Pending vs Approved vs Rejected
```
Query: leave_requests_by_status
Type: Gauge (by status label)
Visualization: Pie Chart or Bar Chart
Query Variants:
  - leave_requests_by_status{status="PENDING"}
  - leave_requests_by_status{status="APPROVED"}
  - leave_requests_by_status{status="REJECTED"}
Example: "50% pending, 40% approved, 10% rejected"
```

### 4. Leave Approval Rate - What % of requests get approved?
```
Query: leave_approval_rate
Type: Gauge (percentage 0-100)
Visualization: Gauge (speedometer)
Alert: leave_approval_rate < 70
Example: "78% approval rate"
```

### 5. User Registrations - New users joining
```
Query: user_registrations_total
Type: Counter (cumulative)
Visualization: Time Series
Rate: rate(user_registrations_total[1d])
By Role: user_registrations_total{role="EMPLOYEE"}
Example: "3 new registrations today"
```

### 6. Login Attempts - Success vs Failure
```
Queries:
  - login_attempts_total{result="success"}  (successful logins)
  - login_attempts_total{result="failure"}  (failed attempts)
Type: Counter
Visualization: Time Series (dual line)
Success Rate: login_attempts_total{result="success"} / 
              (login_attempts_total{result="success"} + login_attempts_total{result="failure"})
Example: "98% login success rate"
```

### 7. Leave Days Requested - How many days per request?
```
Query: leave_days_requested
Type: Histogram (distribution)
Percentiles:
  - P50: histogram_quantile(0.50, leave_days_requested_bucket)
  - P95: histogram_quantile(0.95, leave_days_requested_bucket)
  - P99: histogram_quantile(0.99, leave_days_requested_bucket)
Average: leave_days_requested_sum / leave_days_requested_count
Example: "Average 3.5 days per request, max 30 days"
```

---

## Performance Metrics (How fast is your app?)

### 8. Request Latency - How slow are my endpoints?
```
Query: http_request_duration_seconds
Type: Histogram (response times)
Percentiles:
  - Median (P50): histogram_quantile(0.50, http_request_duration_seconds_bucket)
  - Fast (P95): histogram_quantile(0.95, http_request_duration_seconds_bucket)
  - Slowest (P99): histogram_quantile(0.99, http_request_duration_seconds_bucket)
By Endpoint: histogram_quantile(0.95, http_request_duration_seconds_bucket) by (endpoint)
Alert: histogram_quantile(0.95, ...) > 0.5  (P95 > 500ms)
Example: "P95 latency: 234ms"
```

### 9. Request Size - How big are requests?
```
Query: http_request_size_bytes
Type: Histogram
Average: http_request_size_bytes_sum / http_request_size_bytes_count
Max: http_request_size_bytes_bucket{le="+Inf"}
Example: "Average request size: 2.3 KB"
```

### 10. Response Size - How big are responses?
```
Query: http_response_size_bytes
Type: Histogram
Average: http_response_size_bytes_sum / http_response_size_bytes_count
P95: histogram_quantile(0.95, http_response_size_bytes_bucket)
Example: "Average response: 5.2 KB"
```

### 11. Database Query Latency - How slow is my database?
```
Query: db_query_duration_seconds
Type: Histogram
By Operation:
  - SELECT: histogram_quantile(0.95, db_query_duration_seconds_bucket{operation="SELECT"})
  - INSERT: histogram_quantile(0.95, db_query_duration_seconds_bucket{operation="INSERT"})
  - UPDATE: histogram_quantile(0.95, db_query_duration_seconds_bucket{operation="UPDATE"})
Average: db_query_duration_seconds_sum / db_query_duration_seconds_count
Alert: histogram_quantile(0.95, ...) > 0.1  (P95 > 100ms)
Example: "SELECT P95: 45ms, INSERT P95: 67ms"
```

### 12. DB Connection Pool - How many connections?
```
Query: db_pool_connections
Type: Gauge (with labels: current, max)
Current: db_pool_connections{pool_type="current"}
Max: db_pool_connections{pool_type="max"}
Utilization %: (current / max) * 100
Available: max - current
Alert: (current / max) > 0.8  (using 80%+ of pool)
Example: "10 connections used of 20 available"
```

### 13. System Memory - How much RAM?
```
Query: process_resident_memory_bytes / 1024 / 1024  (in MB)
Query: process_resident_memory_bytes / 1024 / 1024 / 1024  (in GB)
Type: Gauge
Alert: ... > 512  (over 512 MB)
Example: "Using 287 MB"
```

### 14. System CPU - How hard working?
```
Query: rate(process_cpu_seconds_total[5m]) * 100  (percentage)
Type: Rate
Alert: ... > 80  (over 80%)
Example: "CPU: 45%"
```

### 15. Event Loop Lag - App responsiveness
```
Query: nodejs_eventloop_lag_p99_seconds  (worst case latency)
Type: Gauge
Alert: ... > 0.1  (over 100ms lag)
Example: "Event loop P99: 23ms"
```

---

## Error Metrics (Things Gone Wrong)

### 16. HTTP Errors - API breakdown?
```
Query: http_errors_total
Type: Counter
By Status: http_errors_total{status="500"}
By Endpoint: http_errors_total by (endpoint)
Rate: rate(http_errors_total[5m])
Error Rate %: (rate(http_errors_total[5m])) * 100
Alert: rate(...) > 0.01  (more than 1 error per 100 requests)
Example: "5 errors in last 5 minutes (3 x 500, 2 x 429)"
```

### 17. Auth Errors - Login/Permission failures
```
Query: auth_errors_total
Type: Counter
Rate: rate(auth_errors_total[5m])
Example: "2 auth errors in last 5 minutes"
```

### 18. Database Errors - DB connection issues
```
Query: db_errors_total
Type: Counter
By Operation: db_errors_total by (operation)
Example: "1 database error (connection refused)"
```

---

## Throughput Metrics (How much traffic?)

### 19. Requests by Endpoint - Which endpoints get traffic?
```
Query: http_requests_by_endpoint
Type: Counter
By Endpoint: http_requests_by_endpoint by (endpoint)
Per Second: rate(http_requests_by_endpoint[1m]) by (endpoint)
Successful: http_requests_by_endpoint{status=~"2.."}
Failed: http_requests_by_endpoint{status=~"[45].."}
Example: "100 total requests to /api/leave, 98 successful"
```

### 20. Requests by Method - GET vs POST vs etc
```
Query: http_requests_by_method
Type: Counter
Breakdown: http_requests_by_method by (method)
Rate: rate(http_requests_by_method[1m]) by (method)
Example: "GET: 50/sec, POST: 12/sec, PUT: 2/sec"
```

---

## 🎯 Common Queries (Copy & Paste Ready)

### Dashboard: Service Health at a Glance
```promql
# Panel 1: Is it up?
up{job="backend-metrics"}

# Panel 2: Requests per second
rate(http_requests_by_endpoint[1m])

# Panel 3: Error rate (%)
(rate(http_errors_total[5m]) / rate(http_requests_by_endpoint[5m])) * 100

# Panel 4: P95 latency (ms)
histogram_quantile(0.95, http_request_duration_seconds_bucket) * 1000

# Panel 5: Memory usage (MB)
process_resident_memory_bytes / 1024 / 1024

# Panel 6: Active users
active_users
```

### Dashboard: Business Metrics
```promql
# Panel 1: Pending approvals
leave_requests_by_status{status="PENDING"}

# Panel 2: Approval rate (%)
leave_approval_rate

# Panel 3: Leave requests/hour
rate(leave_requests_total[1h])

# Panel 4: Failed login attempts/minute
rate(login_attempts_total{result="failure"}[1m])

# Panel 5: Active users
active_users
```

### Dashboard: Performance Deep Dive
```promql
# Panel 1: Latency percentiles
- P50: histogram_quantile(0.50, http_request_duration_seconds_bucket)
- P95: histogram_quantile(0.95, http_request_duration_seconds_bucket)
- P99: histogram_quantile(0.99, http_request_duration_seconds_bucket)

# Panel 2: DB latency (P95)
histogram_quantile(0.95, db_query_duration_seconds_bucket)

# Panel 3: Memory trend
process_resident_memory_bytes / 1024 / 1024

# Panel 4: CPU usage
rate(process_cpu_seconds_total[5m]) * 100
```

### Dashboard: Errors & Alerts
```promql
# Panel 1: Error rate
rate(http_errors_total[5m])

# Panel 2: Errors by code
http_errors_total by (status)

# Panel 3: Auth failures
rate(login_attempts_total{result="failure"}[5m])

# Panel 4: DB errors
rate(db_errors_total[5m])
```

---

## 📊 Recommended Alert Thresholds

| Alert Name | Condition | Severity |
|-----------|-----------|----------|
| High P95 Latency | `histogram_quantile(0.95, ...) > 0.5` | Warning |
| High Error Rate | `rate(http_errors_total[5m]) > 0.01` | Warning |
| High Memory | `process_resident_memory_bytes > 536870912` | Warning |
| High CPU | `rate(process_cpu_seconds_total[5m]) > 0.8` | Warning |
| Many Auth Failures | `rate(login_attempts_total{result="failure"}[5m]) > 1` | Info |
| DB Connection Pool Full | `db_pool_connections{pool_type="current"} / db_pool_connections{pool_type="max"} > 0.9` | Critical |
| Too Many Pending Leaves | `leave_requests_by_status{status="PENDING"} > 100` | Info |

---

## 🚀 Implementation Checklist

- [ ] Copy `instrumentation-enhanced.js` → `instrumentation.js`
- [ ] Add `import metrics-middleware` in app.js
- [ ] Add `app.use(metricsMiddleware)`
- [ ] Add `trackLoginAttempt()` in login route
- [ ] Add `trackRegistration()` in register route
- [ ] Add `trackLeaveRequest()` in leave POST route
- [ ] Add `trackLeaveStatusUpdate()` in leave approval route
- [ ] Deploy with `terraform apply`
- [ ] Check metrics at `http://localhost:9464/metrics`
- [ ] Query in Prometheus at `http://localhost:9090`
- [ ] Create dashboards in Grafana
- [ ] Set up alerts
- [ ] Monitor KPIs

---

## ✨ You Now Have

✅ **20 metrics** tracking business logic, performance, errors, and throughput  
✅ **Distributed tracing** with automatic spans  
✅ **77+ ready-to-use PromQL queries**  
✅ **Dashboard templates** for Grafana  
✅ **Alert rules** for production  
✅ **Complete documentation** for integration  

**All production-ready!** 🎉

---

## 📖 Full Documentation

- [METRICS_QUERY_GUIDE.md](../METRICS_QUERY_GUIDE.md) - Detailed queries & dashboards
- [METRICS_IMPLEMENTATION_GUIDE.md](../METRICS_IMPLEMENTATION_GUIDE.md) - Step-by-step integration
- Files: instrumentation-enhanced.js, metrics-middleware.js, app-enhanced.js
