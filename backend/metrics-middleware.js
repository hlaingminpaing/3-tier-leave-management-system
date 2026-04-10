/* metrics-middleware.js - Middleware for collecting metrics */
const { trace, context } = require('@opentelemetry/api');
const instrumentationModule = require('./instrumentation-enhanced');

// Get tracer and metrics
const tracer = instrumentationModule.tracer;
const {
    requestLatencyHistogram,
    requestSizeHistogram,
    responseSizeHistogram,
    httpErrorsCounter,
    requestsPerEndpointCounter,
    requestsByMethodCounter,
    loginAttemptsCounter,
    registrationsCounter,
    leaveRequestsCounter,
    authErrorsCounter,
    dbQueryLatencyHistogram,
    dbErrorsCounter,
} = instrumentationModule.metrics;

// Track active users (in-memory store for demo)
let activeUsers = new Set();
let activeUserCount = 0;

/**
 * Request/Response Metrics Middleware
 * Tracks latency, size, errors for all HTTP requests
 */
function metricsMiddleware(req, res, next) {
    const startTime = Date.now();
    const contentLength = parseInt(req.headers['content-length'] || 0);

    // Record request size
    if (contentLength > 0) {
        requestSizeHistogram.record(contentLength, {
            method: req.method,
            endpoint: req.path,
        });
    }

    // Create span for this request
    const span = tracer.startSpan(`HTTP ${req.method} ${req.path}`, {
        attributes: {
            'http.method': req.method,
            'http.url': req.url,
            'http.target': req.path,
            'http.host': req.hostname,
        },
    });

    // Run the rest in span context
    return context.with(trace.setSpan(context.active(), span), () => {
        // Track original res.end to capture response metrics
        const originalEnd = res.end;
        res.end = function(chunk, encoding) {
            // Calculate latency
            const latency = (Date.now() - startTime) / 1000;
            requestLatencyHistogram.record(latency, {
                method: req.method,
                endpoint: req.path,
                status: res.statusCode,
            });

            // Record response size
            if (chunk) {
                const responseSize = Buffer.byteLength(chunk, encoding);
                responseSizeHistogram.record(responseSize, {
                    method: req.method,
                    endpoint: req.path,
                });
            }

            // Record HTTP errors
            if (res.statusCode >= 400) {
                httpErrorsCounter.add(1, {
                    method: req.method,
                    endpoint: req.path,
                    status: res.statusCode,
                });
            }

            // Record request count
            requestsPerEndpointCounter.add(1, {
                method: req.method,
                endpoint: req.path,
                status: res.statusCode,
            });

            requestsByMethodCounter.add(1, {
                method: req.method,
            });

            // End span with status
            span.setAttributes({
                'http.status_code': res.statusCode,
                'http.response_content_length': responseSize || 0,
            });
            span.end();

            // Call original end
            originalEnd.call(this, chunk, encoding);
        };

        next();
    });
}

/**
 * Track Authentication Events
 */
function trackLoginAttempt(success, username) {
    const span = tracer.startSpan('login_attempt', {
        attributes: {
            'auth.username': username,
            'auth.success': success,
        },
    });

    loginAttemptsCounter.add(1, {
        result: success ? 'success' : 'failure',
        username: username,
    });

    if (!success) {
        authErrorsCounter.add(1, {
            type: 'login_failure',
            username: username,
        });
    }

    span.end();
}

/**
 * Track User Registration
 */
function trackRegistration(username, role) {
    const span = tracer.startSpan('user_registration', {
        attributes: {
            'user.username': username,
            'user.role': role,
        },
    });

    registrationsCounter.add(1, {
        role: role,
    });

    span.end();
}

/**
 * Track Leave Request Submission
 */
function trackLeaveRequest(userId, startDate, endDate, reason) {
    const startDateObj = new Date(startDate);
    const endDateObj = new Date(endDate);
    const daysRequested = (endDateObj - startDateObj) / (1000 * 60 * 60 * 24) + 1; // +1 to include end date

    const span = tracer.startSpan('leave_request_submitted', {
        attributes: {
            'leave.user_id': userId,
            'leave.start_date': startDate,
            'leave.end_date': endDate,
            'leave.days_requested': daysRequested,
            'leave.reason': reason,
        },
    });

    leaveRequestsCounter.add(1, {
        reason: reason || 'other',
    });

    // Record the number of days
    if (daysRequested > 0) {
        leaveRequestsCounter.add(daysRequested, {
            metric_type: 'days_requested',
        });
    }

    span.end();
}

/**
 * Track Leave Request Approval/Rejection
 */
function trackLeaveStatusUpdate(leaveId, newStatus, userId) {
    const span = tracer.startSpan('leave_request_status_updated', {
        attributes: {
            'leave.id': leaveId,
            'leave.status': newStatus,
            'leave.updated_by': userId,
        },
    });

    span.end();
}

/**
 * Track Database Operations
 */
function createDatabaseSpan(operation, query) {
    const span = tracer.startSpan(`db.${operation}`, {
        attributes: {
            'db.system': 'mysql',
            'db.operation': operation,
            'db.statement': query.substring(0, 100), // First 100 chars for safety
        },
    });

    return {
        span,
        recordDuration: (duration) => {
            dbQueryLatencyHistogram.record(duration / 1000, {
                operation: operation,
                query: query.split(' ')[0], // Record just the operation (SELECT, INSERT, etc)
            });
            span.setAttributes({
                'db.duration_ms': duration,
            });
        },
        recordError: (error) => {
            dbErrorsCounter.add(1, {
                operation: operation,
                error_type: error.code || 'unknown',
            });
            span.recordException(error);
        },
    };
}

/**
 * Track Authentication Errors
 */
function trackAuthenticationError(errorType, details) {
    const span = tracer.startSpan('authentication_error', {
        attributes: {
            'auth.error_type': errorType,
            'auth.details': details,
        },
    });

    authErrorsCounter.add(1, {
        error_type: errorType,
    });

    span.end();
}

/**
 * Update Active User Count
 */
function setActiveUser(userId) {
    activeUsers.add(userId);
    activeUserCount = activeUsers.size;
}

function removeActiveUser(userId) {
    activeUsers.delete(userId);
    activeUserCount = activeUsers.size;
}

/**
 * Get Active User Count
 */
function getActiveUserCount() {
    return activeUserCount;
}

module.exports = {
    metricsMiddleware,
    trackLoginAttempt,
    trackRegistration,
    trackLeaveRequest,
    trackLeaveStatusUpdate,
    createDatabaseSpan,
    trackAuthenticationError,
    setActiveUser,
    removeActiveUser,
    getActiveUserCount,
};
