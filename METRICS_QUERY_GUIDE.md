# Leave Management System - Comprehensive Metrics Guide

## Overview

Your leave management system now has complete observability with **17 custom metrics** plus **automatic system metrics** from OpenTelemetry auto-instrumentation. This guide explains:

1. **What metrics are available**
2. **How to query them** (PromQL for Prometheus)
3. **Business insights** you can extract
4. **How to implement them** in your code

---

## 📊 Available Metrics by Category

### 1. BUSINESS METRICS (User & Leave Management)

#### A. Active Users
```
Metric Name: active_users
Type: Gauge
Description: Number of currently logged-in/active users
Unit: count

PromQL Queries:
- Current active users: active_users
- Peak active users (5m): max_over_time(active_users[5m])
- Average active users per hour: avg_over_time(active_users[1h])
```

#### B. Leave Requests Tracking
```
Metric Name: leave_requests_total
Type: Counter
Description: Total leave requests submitted
Unit: count
Labels: reason (e.g., sick, vacation, personal)

PromQL Queries:
- Total leave requests: leave_requests_total
- Leave requests by reason: leave_requests_total{reason!=""}
- Leave requests per minute: rate(leave_requests_total[1m])
- Requests by one reason: leave_requests_total{reason="sick"}
```

#### C. Leave Requests by Status
```
Metric Name: leave_requests_by_status
Type: Gauge
Description: Current count of leave requests by status (PENDING, APPROVED, REJECTED)
Unit: count
Labels: status

PromQL Queries:
- Pending leave requests: leave_requests_by_status{status="PENDING"}
- Approved requests: leave_requests_by_status{status="APPROVED"}
- Rejected requests: leave_requests_by_status{status="REJECTED"}
- Total pending vs approved: leave_requests_by_status{status="PENDING"} / leave_requests_by_status{status="APPROVED"}
```

#### D. User Registrations
```
Metric Name: user_registrations_total
Type: Counter
Description: Total user registrations
Unit: count
Labels: role (EMPLOYEE, ADMIN)

PromQL Queries:
- Total registrations: user_registrations_total
- Registrations by role: user_registrations_total{role!=""}
- Registration rate per hour: rate(user_registrations_total[1h])
- Employee registrations: user_registrations_total{role="EMPLOYEE"}
```

#### E. Login Attempts
```
Metric Name: login_attempts_total
Type: Counter
Description: Login attempts (success and failure)
Unit: count
Labels: result (success, failure), username

PromQL Queries:
- Successful logins: login_attempts_total{result="success"}
- Failed logins: login_attempts_total{result="failure"}
- Failed login rate: rate(login_attempts_total{result="failure"}[5m])
- Login success rate: login_attempts_total{result="success"} / (login_attempts_total{result="success"} + login_attempts_total{result="failure"})
```

#### F. Leave Days Analysis
```
Metric Name: leave_days_requested
Type: Histogram
Description: Number of days requested in leave applications
Unit: days
Buckets: Auto-configured for distribution analysis

PromQL Queries:
- Average days requested per leave: leave_days_requested_sum / leave_days_requested_count
- Max days requested: leave_days_requested_bucket{le="+Inf"}
- Days requested p95 (95th percentile): histogram_quantile(0.95, leave_days_requested_bucket)
- Days requested p99 (99th percentile): histogram_quantile(0.99, leave_days_requested_bucket)
```

#### G. Leave Approval Rate
```
Metric Name: leave_approval_rate
Type: Gauge
Description: Percentage of approved leave requests (0-100)
Unit: percentage

PromQL Queries:
- Current approval rate: leave_approval_rate
- Average approval rate (24h): avg_over_time(leave_approval_rate[24h])
```

---

### 2. PERFORMANCE METRICS (Latency, Throughput, Size)

#### A. HTTP Request Latency
```
Metric Name: http_request_duration_seconds
Type: Histogram
Description: Response time for HTTP requests
Unit: seconds
Labels: method, endpoint, status
Buckets: [.005, .01, .025, .05, .075, .1, .25, .5, .75, 1, 2.5, 5, 7.5, 10]

PromQL Queries:
- Average latency: http_request_duration_seconds_sum / http_request_duration_seconds_count
- Average latency by endpoint: avg(http_request_duration_seconds_sum{endpoint=~"/api/.*"}) by (endpoint) / avg(http_request_duration_seconds_count) by (endpoint)
- P50 latency (median): histogram_quantile(0.50, http_request_duration_seconds_bucket)
- P95 latency: histogram_quantile(0.95, http_request_duration_seconds_bucket)
- P99 latency: histogram_quantile(0.99, http_request_duration_seconds_bucket)
- Latency by method: histogram_quantile(0.95, http_request_duration_seconds_bucket) by (method)
- Login endpoint latency (p99): histogram_quantile(0.99, http_request_duration_seconds_bucket{endpoint="/api/login"})
```

#### B. HTTP Request Size
```
Metric Name: http_request_size_bytes
Type: Histogram
Description: Request payload size
Unit: bytes
Labels: method, endpoint

PromQL Queries:
- Average request size: http_request_size_bytes_sum / http_request_size_bytes_count
- Max request size: http_request_size_bytes_bucket{le="+Inf"}
- Request size by endpoint: avg(http_request_size_bytes_sum) by (endpoint)
```

#### C. HTTP Response Size
```
Metric Name: http_response_size_bytes
Type: Histogram
Description: Response payload size
Unit: bytes
Labels: method, endpoint

PromQL Queries:
- Average response size: http_response_size_bytes_sum / http_response_size_bytes_count
- Response size p95: histogram_quantile(0.95, http_response_size_bytes_bucket)
- Large responses (>1MB): http_response_size_bytes_bucket{le="+Inf"} > 1000000
```

#### D. Database Query Latency
```
Metric Name: db_query_duration_seconds
Type: Histogram
Description: Time to execute database queries
Unit: seconds
Labels: operation (SELECT, INSERT, UPDATE, DELETE), query

PromQL Queries:
- Average DB latency: db_query_duration_seconds_sum / db_query_duration_seconds_count
- SELECT query latency (p95): histogram_quantile(0.95, db_query_duration_seconds_bucket{operation="SELECT"})
- INSERT query latency: histogram_quantile(0.99, db_query_duration_seconds_bucket{operation="INSERT"})
- Slowest queries: db_query_duration_seconds_bucket{le="+Inf"} > 1
- Query latency by operation: avg(db_query_duration_seconds_sum) by (operation)
```

#### E. Database Connection Pool
```
Metric Name: db_pool_connections
Type: Gauge
Description: Database connection pool statistics
Unit: connections
Labels: pool_type (current, max)

PromQL Queries:
- Current connections: db_pool_connections{pool_type="current"}
- Max connections: db_pool_connections{pool_type="max"}
- Connection utilization %: (db_pool_connections{pool_type="current"} / db_pool_connections{pool_type="max"}) * 100
- Connection availability: db_pool_connections{pool_type="max"} - db_pool_connections{pool_type="current"}
```

---

### 3. ERROR METRICS (Errors & Failures)

#### A. HTTP Errors
```
Metric Name: http_errors_total
Type: Counter
Description: Total HTTP errors (4xx, 5xx)
Unit: count
Labels: method, endpoint, status

PromQL Queries:
- Total errors: http_errors_total
- 5xx errors: http_errors_total{status=~"5.."}
- 4xx errors: http_errors_total{status=~"4.."}
- Error rate: rate(http_errors_total[5m])
- Errors by endpoint: http_errors_total by (endpoint)
- 401 (unauthorized) errors: http_errors_total{status="401"}
```

#### B. Authentication Errors
```
Metric Name: auth_errors_total
Type: Counter
Description: Authentication and authorization failures
Unit: count
Labels: type, username

PromQL Queries:
- Total auth errors: auth_errors_total
- Login failures: auth_errors_total{type="login_failure"}
- Auth error rate: rate(auth_errors_total[5m])
```

#### C. Database Errors
```
Metric Name: db_errors_total
Type: Counter
Description: Database operation errors
Unit: count
Labels: operation, error_type

PromQL Queries:
- Total DB errors: db_errors_total
- Connection errors: db_errors_total{error_type="ECONNREFUSED"}
- Timeout errors: db_errors_total{error_type="TIMEOUT"}
- Errors by operation: db_errors_total by (operation)
```

---

### 4. THROUGHPUT METRICS (Request Volume)

#### A. Requests by Endpoint
```
Metric Name: http_requests_by_endpoint
Type: Counter
Description: Total HTTP requests per endpoint
Unit: count
Labels: method, endpoint, status

PromQL Queries:
- Total requests: http_requests_by_endpoint
- Requests per endpoint: http_requests_by_endpoint by (endpoint)
- GET requests: http_requests_by_endpoint{method="GET"}
- POST requests: http_requests_by_endpoint{method="POST"}
- Login requests: http_requests_by_endpoint{endpoint="/api/login"}
- Requests per second: rate(http_requests_by_endpoint[1m])
- Successful requests: http_requests_by_endpoint{status=~"2.."}
```

#### B. Requests by Method
```
Metric Name: http_requests_by_method
Type: Counter
Description: Total HTTP requests by method
Unit: count
Labels: method

PromQL Queries:
- POST requests: http_requests_by_method{method="POST"}
- GET requests: http_requests_by_method{method="GET"}
- Request method distribution: http_requests_by_method
- Requests per second by method: rate(http_requests_by_method[1m]) by (method)
```

---

### 5. AUTOMATIC SYSTEM METRICS (Auto-instrumented)

These are collected automatically by OpenTelemetry Node.js auto-instrumentation:

#### A. Process Metrics
```
Metric Name: process_resident_memory_bytes
Type: Gauge
Description: Process memory usage
Unit: bytes

PromQL Queries:
- Memory in MB: process_resident_memory_bytes / 1024 / 1024
- Memory in GB: process_resident_memory_bytes / 1024 / 1024 / 1024
- Memory growth rate: rate(process_resident_memory_bytes[5m])
- Memory alert if >500MB: process_resident_memory_bytes / 1024 / 1024 > 500
```

#### B. CPU Metrics
```
Metric Name: process_cpu_seconds_total
Type: Counter
Description: CPU time used

PromQL Queries:
- CPU usage %: rate(process_cpu_seconds_total[5m]) * 100
- CPU alert if >80%: rate(process_cpu_seconds_total[5m]) * 100 > 80
```

#### C. Node.js Event Loop
```
Metric Names: nodejs_eventloop_lag_p50_seconds, nodejs_eventloop_lag_p99_seconds
Type: Gauge
Description: Event loop lag/delay

PromQL Queries:
- Event loop lag p50: nodejs_eventloop_lag_p50_seconds
- Event loop lag p99: nodejs_eventloop_lag_p99_seconds
- Alert if p99 > 100ms: nodejs_eventloop_lag_p99_seconds > 0.1
```

#### D. HTTP Connections
```
Metric Name: http_server_connections_total
Type: Counter
Description: Total HTTP connections

PromQL Queries:
- Connection rate: rate(http_server_connections_total[1m])
```

---

## 🎯 Recommended Dashboard Queries for Grafana

### Dashboard 1: Service Health
```
1. Up Status
   Query: up{job="backend-metrics"}
   Visualization: Stat (green/red)

2. Request Rate (RPS)
   Query: rate(http_requests_by_endpoint[1m])
   Visualization: Time series

3. Error Rate
   Query: rate(http_errors_total[1m])
   Visualization: Time series

4. Active Users
   Query: active_users
   Visualization: Gauge
```

### Dashboard 2: Performance
```
1. Latency P50/P95/P99
   Query: 
   - histogram_quantile(0.50, http_request_duration_seconds_bucket)
   - histogram_quantile(0.95, http_request_duration_seconds_bucket)
   - histogram_quantile(0.99, http_request_duration_seconds_bucket)
   Visualization: Time series

2. Database Query Latency
   Query: histogram_quantile(0.95, db_query_duration_seconds_bucket) by (operation)
   Visualization: Time series

3. Memory Usage
   Query: process_resident_memory_bytes / 1024 / 1024
   Visualization: Time series with Alert threshold

4. CPU Usage
   Query: rate(process_cpu_seconds_total[5m]) * 100
   Visualization: Time series
```

### Dashboard 3: Business Metrics
```
1. Leave Requests Trend
   Query: rate(leave_requests_total[1h])
   Visualization: Time series

2. Approval Rate
   Query: leave_approval_rate
   Visualization: Gauge

3. Leave Requests by Status
   Query: leave_requests_by_status
   Visualization: Pie chart

4. Pending Approvals
   Query: leave_requests_by_status{status="PENDING"}
   Visualization: Stat (big number)
```

### Dashboard 4: Availability & Errors
```
1. Success Rate
   Query: (1 - (rate(http_errors_total[5m]) / rate(http_requests_by_endpoint[5m]))) * 100
   Visualization: Gauge (target: 99%+)

2. Errors by Endpoint
   Query: rate(http_errors_total[1m]) by (endpoint)
   Visualization: Bar chart

3. 401 Unauthorized
   Query: rate(http_errors_total{status="401"}[5m])
   Visualization: Stat

4. Failed Logins
   Query: rate(login_attempts_total{result="failure"}[5m])
   Visualization: Stat
```

---

## 🚀 Implementation Guide

### Step 1: Use Enhanced Instrumentation

Replace `require("./instrumentation")` with the enhanced version:

```javascript
// In app.js
require("./instrumentation-enhanced");  // This has all custom metrics
```

### Step 2: Import Metrics Middleware

```javascript
const {
    metricsMiddleware,
    trackLoginAttempt,
    trackRegistration,
    trackLeaveRequest,
    trackLeaveStatusUpdate,
    createDatabaseSpan,
} = require("./metrics-middleware");

// Apply middleware
app.use(metricsMiddleware);
```

### Step 3: Track Events in Your Routes

```javascript
// Track login attempt
apiRouter.post("/login", (req, res) => {
    // ... your login code ...
    trackLoginAttempt(true, username);  // On success
    trackLoginAttempt(false, username); // On failure
});

// Track leave request
apiRouter.post("/leave", auth(), (req, res) => {
    // ... your code ...
    tradLeaveRequest(userId, startDate, endDate, reason);
});

// Track registration
apiRouter.post("/register", (req, res) => {
    // ... your code ...
    trackRegistration(username, role);
});
```

### Step 4: Track Database Operations

```javascript
// Wrap DB calls with spans
const dbSpan = createDatabaseSpan('SELECT', 'SELECT * FROM users WHERE id=?');
const startTime = Date.now();

db.query('SELECT * FROM users WHERE id=?', [id], (err, rows) => {
    const duration = Date.now() - startTime;
    
    if (err) {
        dbSpan.recordError(err);
    } else {
        dbSpan.recordDuration(duration);
    }
    
    dbSpan.span.end();
    // ... handle response ...
});
```

### Step 5: Deploy & Query

```bash
# Port forward to Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Visit http://localhost:9090
# Try some queries from the sections above
```

---

## 📈 Key Performance Indicators (KPIs)

Track these KPIs for production:

| KPI | Target | Query |
|-----|--------|-------|
| **Availability** | >99.9% | (1 - rate(http_errors_total[5m]) / rate(http_requests_by_endpoint[5m])) * 100 |
| **Latency (p95)** | <500ms | histogram_quantile(0.95, http_request_duration_seconds_bucket) |
| **Error Rate** | <0.1% | rate(http_errors_total[5m]) |
| **Active Users** | Monitor | active_users |
| **Request Rate** | Monitor | rate(http_requests_by_endpoint[1m]) |
| **Database Latency** | <100ms | histogram_quantile(0.95, db_query_duration_seconds_bucket) |
| **Memory Usage** | <512MB | process_resident_memory_bytes / 1024 / 1024 |
| **CPU Usage** | <80% | rate(process_cpu_seconds_total[5m]) * 100 |
| **Leave Approval Rate** | Monitor | leave_approval_rate |
| **Failed Logins** | <1/min | rate(login_attempts_total{result="failure"}[1m]) |

---

## ✅ Traces Available via Tempo

Your application automatically creates traces for:

1. **HTTP Requests**: `HTTP GET /api/leave` 
2. **Database Operations**: `db.SELECT`, `db.INSERT`, `db.UPDATE`
3. **Authentication**: `login_attempt`, `authentication_error`
4. **Business Logic**: `leave_request_submitted`, `leave_request_status_updated`, `user_registration`

### View Traces in Grafana

1. Port forward: `kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80`
2. Login to Grafana (http://localhost:3000)
3. Go to Explore tab
4. Select Tempo datasource
5. Service: `leave-backend`
6. Find traces and click to view details

---

## 📋 Metrics Checklist

- [x] Business metrics (users, leave requests, registrations)
- [x] Performance metrics (latency, throughput, size)
- [x] Error metrics (HTTP, auth, database)
- [x] Database metrics (query latency, connection pool)
- [x] System metrics (CPU, memory, event loop)
- [x] Distributed tracing (spans for business logic)
- [x] PromQL queries documented
- [x] Grafana dashboards recommended
- [x] Implementation guide provided
- [x] KPIs defined

---

## 📚 Files Reference

| File | Purpose |
|------|---------|
| `instrumentation-enhanced.js` | All 17 custom metrics definitions |
| `metrics-middleware.js` | Middleware for collecting metrics automatically |
| `app-enhanced.js` | Example app.js showing integration |
| `METRICS_QUERY_GUIDE.md` | This file - All PromQL queries |

---

## Next Steps

1. **Copy enhanced files to your backend**:
   ```bash
   cp instrumentation-enhanced.js instrumentation.js
   cp metrics-middleware.js metrics-middleware.js
   ```

2. **Update app.js** to import metrics middleware

3. **Track events** in your route handlers

4. **Deploy** and test metrics

5. **Build dashboards** in Grafana using the recommended queries

6. **Set alerts** based on the KPI targets

All metrics are production-ready and follow OpenTelemetry best practices! 🎉
