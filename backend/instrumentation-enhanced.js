/* instrumentation.js - Enhanced with Custom Metrics */
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { PrometheusExporter } = require('@opentelemetry/exporter-prometheus');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');

// Import OpenTelemetry Meter and Tracer APIs
const { metrics, trace } = require('@opentelemetry/api');
const { MeterProvider } = require('@opentelemetry/sdk-metrics');
const { Resource } = require('@opentelemetry/resources');
const { SemanticResourceAttributes } = require('@opentelemetry/semantic-conventions');

// Metrics: Prometheus Exporter listening on port 9464
const metricsExporter = new PrometheusExporter({
    port: 9464,
    endpoint: '/metrics',
}, () => {
    console.log('Prometheus metrics ready at :9464/metrics');
});

// Tracing: OTLP Exporter (Sends to Tempo/Jaeger)
const traceExporter = new OTLPTraceExporter();

const sdk = new NodeSDK({
    serviceName: 'leave-backend',
    metricReader: metricsExporter,
    traceExporter: traceExporter,
    instrumentations: [getNodeAutoInstrumentations()],
});

sdk.start();

// ============================================================
// CUSTOM METRICS FOR LEAVE MANAGEMENT SYSTEM
// ============================================================

// Get global meter
const meter = metrics.getMeter('leave-backend-metrics', '1.0.0');

// ============================================================
// BUSINESS METRICS
// ============================================================

// 1. Active Users (Gauge) - Number of concurrent active sessions
const activeUsersGauge = meter.createObservableGauge('active_users', {
    description: 'Number of currently active users',
    unit: '1',
});

// 2. Leave Requests Counter - Total leave requests
const leaveRequestsCounter = meter.createCounter('leave_requests_total', {
    description: 'Total number of leave requests submitted',
    unit: '1',
});

// 3. Leave Requests by Status Gauge
const leaveRequestsByStatusGauge = meter.createObservableGauge('leave_requests_by_status', {
    description: 'Number of leave requests by status',
    unit: '1',
});

// 4. Login Attempts Counter
const loginAttemptsCounter = meter.createCounter('login_attempts_total', {
    description: 'Total number of login attempts',
    unit: '1',
});

// 5. User Registrations Counter
const registrationsCounter = meter.createCounter('user_registrations_total', {
    description: 'Total number of user registrations',
    unit: '1',
});

// ============================================================
// PERFORMANCE METRICS
// ============================================================

// 6. Request Latency Histogram - Track response time by endpoint
const requestLatencyHistogram = meter.createHistogram('http_request_duration_seconds', {
    description: 'HTTP request latency in seconds',
    unit: 's',
});

// 7. Request Size Histogram
const requestSizeHistogram = meter.createHistogram('http_request_size_bytes', {
    description: 'HTTP request size in bytes',
    unit: 'By',
});

// 8. Response Size Histogram
const responseSizeHistogram = meter.createHistogram('http_response_size_bytes', {
    description: 'HTTP response size in bytes',
    unit: 'By',
});

// 9. Database Query Latency Histogram
const dbQueryLatencyHistogram = meter.createHistogram('db_query_duration_seconds', {
    description: 'Database query latency in seconds',
    unit: 's',
});

// 10. Database Connection Pool Gauge
const dbConnectionPoolGauge = meter.createObservableGauge('db_pool_connections', {
    description: 'Database connection pool statistics',
    unit: '1',
});

// ============================================================
// ERROR METRICS
// ============================================================

// 11. HTTP Errors Counter
const httpErrorsCounter = meter.createCounter('http_errors_total', {
    description: 'Total number of HTTP errors by status code',
    unit: '1',
});

// 12. Authentication Errors Counter
const authErrorsCounter = meter.createCounter('auth_errors_total', {
    description: 'Total number of authentication errors',
    unit: '1',
});

// 13. Database Errors Counter
const dbErrorsCounter = meter.createCounter('db_errors_total', {
    description: 'Total number of database errors',
    unit: '1',
});

// ============================================================
// THROUGHPUT METRICS
// ============================================================

// 14. Requests per Endpoint Counter
const requestsPerEndpointCounter = meter.createCounter('http_requests_by_endpoint', {
    description: 'HTTP requests by endpoint',
    unit: '1',
});

// 15. API Requests by Method Counter
const requestsByMethodCounter = meter.createCounter('http_requests_by_method', {
    description: 'HTTP requests by method',
    unit: '1',
});

// ============================================================
// BUSINESS LOGIC METRICS
// ============================================================

// 16. Leave Days Used Histogram
const leaveDaysUsedHistogram = meter.createHistogram('leave_days_requested', {
    description: 'Number of days requested in leave applications',
    unit: '1',
});

// 17. Leave Approval Rate Gauge
const leaveApprovalRateGauge = meter.createObservableGauge('leave_approval_rate', {
    description: 'Percentage of approved leave requests',
    unit: '%',
});

// ============================================================
// CUSTOM TRACER FOR DISTRIBUTED TRACING
// ============================================================

const tracer = trace.getTracer('leave-backend-tracer', '1.0.0');

// ============================================================
// GAUGES - Observable values (need callback registration)
// ============================================================

// Track active users count
activeUsersGauge.addCallback((result) => {
    // Will be updated by metrics middleware
    const count = globalThis.activeUserCount || 0;
    result.observe(count, {});
});

// Track leave requests by status
leaveRequestsByStatusGauge.addCallback((result) => {
    // Called from database queries in app
    if (globalThis.leaveRequestsByStatus) {
        Object.entries(globalThis.leaveRequestsByStatus).forEach(([status, count]) => {
            result.observe(count, { status });
        });
    }
});

// Track DB connection pool
dbConnectionPoolGauge.addCallback((result) => {
    // Will be updated when pool info is available
    if (globalThis.dbPoolInfo) {
        result.observe(globalThis.dbPoolInfo.current || 0, { pool_type: 'current' });
        result.observe(globalThis.dbPoolInfo.max || 0, { pool_type: 'max' });
    }
});

// Track leave approval rate
leaveApprovalRateGauge.addCallback((result) => {
    if (globalThis.leaveApprovalStats) {
        const total = globalThis.leaveApprovalStats.approved + globalThis.leaveApprovalStats.rejected;
        const approvalRate = total > 0 ? (globalThis.leaveApprovalStats.approved / total) * 100 : 0;
        result.observe(approvalRate, {});
    }
});

// ============================================================
// EXPORT METRICS & TRACER FOR USE IN APP
// ============================================================

module.exports = {
    sdk,
    tracer,
    metrics: {
        // Business metrics
        activeUsersGauge,
        leaveRequestsCounter,
        leaveRequestsByStatusGauge,
        loginAttemptsCounter,
        registrationsCounter,
        // Performance metrics
        requestLatencyHistogram,
        requestSizeHistogram,
        responseSizeHistogram,
        dbQueryLatencyHistogram,
        dbConnectionPoolGauge,
        // Error metrics
        httpErrorsCounter,
        authErrorsCounter,
        dbErrorsCounter,
        // Throughput metrics
        requestsPerEndpointCounter,
        requestsByMethodCounter,
        // Business logic metrics
        leaveDaysUsedHistogram,
        leaveApprovalRateGauge,
    },
};

// Graceful shutdown
process.on('SIGTERM', () => {
    sdk.shutdown()
        .then(() => console.log('Tracing/Metrics terminated'))
        .catch((error) => console.log('Error terminating', error))
        .finally(() => process.exit(0));
});
