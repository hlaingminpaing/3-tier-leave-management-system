/**
 * load-test/advanced-scenario.js
 * Advanced load testing with realistic user journeys and business logic
 * Tests 100 concurrent users performing multiple leave request operations
 */

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const successRate = new Rate('success');
const registerDuration = new Trend('register_duration');
const loginDuration = new Trend('login_duration');
const leaveDuration = new Trend('leave_request_duration');
const getUserLeavesDuration = new Trend('get_leaves_duration');
const totalUsers = new Counter('total_users_tested');

// Configuration for 100 concurrent users
export const options = {
    stages: [
        // Phase 1: Warm-up - 5 mins with low load
        { duration: '5m', target: 10 },
        
        // Phase 2: Ramp-up - 5 mins increasing to 50 users
        { duration: '5m', target: 50 },
        
        // Phase 3: Heavy load - 10 mins at 100 concurrent users (PEAK - triggers HPA/scaling)
        { duration: '10m', target: 100 },
        
        // Phase 4: Stress - 5 mins maintain peak
        { duration: '5m', target: 100 },
        
        // Phase 5: Cool-down - 5 mins ramp down
        { duration: '3m', target: 30 },
        { duration: '2m', target: 0 },
    ],
    
    // Performance thresholds
    thresholds: {
        'http_req_duration': [
            'p(50)<200',    // Median < 200ms
            'p(95)<500',    // 95th percentile < 500ms
            'p(99)<1000',   // 99th percentile < 1s
        ],
        'register_duration': ['p(95)<300'],
        'login_duration': ['p(95)<300'],
        'leave_request_duration': ['p(95)<500'],
        'get_leaves_duration': ['p(95)<300'],
        'errors': ['rate<0.1'],      // Allow up to 10% error rate (includes auth failures)
        'success': ['rate>0.9'],     // At least 90% success rate
        'http_reqs': ['rate>50'],    // At least 50 requests per second
    },
    
    // Alert configuration
    ext: {
        loadimpact: {
            projectID: 3356804, // Set this to your Load Impact project ID if using cloud execution
            name: 'Leave System - 100 Users Load Test',
        },
    },
};

const BASE_URL = __ENV.API_URL || 'http://localhost:3000';

// Shared user credentials storage (in real scenario, pre-register users)
const registeredUsers = [];
let userCounter = 0;

/**
 * Generate unique user credentials
 */
function generateUser() {
    userCounter++;
    return {
        username: `loaduser_${userCounter}_${Date.now()}`,
        password: `LoadPass123!_${Date.now()}`,
        email: `loaduser${userCounter}@test.com`,
    };
}

/**
 * Generate realistic leave request dates
 */
function generateLeaveRequest() {
    const today = new Date();
    const start = new Date(today);
    const end = new Date(today);
    
    // Random start date within next 30 days
    start.setDate(today.getDate() + Math.floor(Math.random() * 30));
    
    // Random duration 1-10 days
    end.setDate(start.getDate() + Math.floor(Math.random() * 10) + 1);
    
    const reasons = ['Vacation', 'Sick Leave', 'Personal', 'Bereavement', 'Other'];
    const reason = reasons[Math.floor(Math.random() * reasons.length)];
    
    return {
        start_date: start.toISOString().split('T')[0],
        end_date: end.toISOString().split('T')[0],
        reason: reason,
    };
}

/**
 * Main user journey for 100 concurrent users
 */
export default function () {
    const user = generateUser();
    totalUsers.add(1);

    group('01 - User Registration', () => {
        const startTime = new Date();
        
        const res = http.post(
            `${BASE_URL}/api/register`,
            JSON.stringify({
                username: user.username,
                password: user.password,
                role: 'EMPLOYEE',
            }),
            {
                headers: { 'Content-Type': 'application/json' },
                tags: { name: 'RegisterUser' },
            }
        );

        const duration = new Date() - startTime;
        registerDuration.add(duration);

        const registrationSuccess = check(res, {
            'Register status is 200 or 409': (r) => r.status === 200 || r.status === 409,
            'Register response has message': (r) => r.json('message') !== undefined || r.status === 409,
        });

        if (registrationSuccess) {
            successRate.add(1);
            registeredUsers.push(user);
        } else {
            errorRate.add(1);
        }
    });

    sleep(0.5); // Small delay between operations

    group('02 - User Login', () => {
        const startTime = new Date();
        
        const res = http.post(
            `${BASE_URL}/api/login`,
            JSON.stringify({
                username: user.username,
                password: user.password,
            }),
            {
                headers: { 'Content-Type': 'application/json' },
                tags: { name: 'Login' },
            }
        );

        const duration = new Date() - startTime;
        loginDuration.add(duration);

        const loginSuccess = check(res, {
            'Login status is 200': (r) => r.status === 200,
            'Login returns token': (r) => r.json('token') !== undefined && r.json('token') !== '',
            'Login returns role': (r) => r.json('role') !== undefined,
        });

        if (!loginSuccess) {
            errorRate.add(1);
            return; // Don't proceed if login fails
        }

        successRate.add(1);
        
        const token = res.json('token');
        const authHeaders = {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`,
        };

        sleep(0.5);

        group('03 - Apply Leave Request', () => {
            const startTime = new Date();
            const leaveRequest = generateLeaveRequest();

            const res = http.post(
                `${BASE_URL}/api/leave`,
                JSON.stringify(leaveRequest),
                {
                    headers: authHeaders,
                    tags: { name: 'ApplyLeave' },
                }
            );

            const duration = new Date() - startTime;
            leaveDuration.add(duration);

            const applySuccess = check(res, {
                'Apply leave status is 200': (r) => r.status === 200,
                'Apply leave response has message': (r) => r.json('message') !== undefined,
            });

            if (applySuccess) {
                successRate.add(1);
            } else {
                errorRate.add(1);
            }
        });

        sleep(0.5);

        group('04 - Retrieve User Leaves', () => {
            const startTime = new Date();

            const res = http.get(
                `${BASE_URL}/api/leave`,
                {
                    headers: authHeaders,
                    tags: { name: 'GetLeaves' },
                }
            );

            const duration = new Date() - startTime;
            getUserLeavesDuration.add(duration);

            const getSuccess = check(res, {
                'Get leaves status is 200': (r) => r.status === 200,
                'Get leaves returns array': (r) => Array.isArray(r.json()),
            });

            if (getSuccess) {
                successRate.add(1);
            } else {
                errorRate.add(1);
            }
        });

        sleep(0.5);

        // Simulate random user actions - some apply multiple leaves
        if (Math.random() > 0.7) {
            group('05 - Apply Additional Leave Request', () => {
                const leaveRequest = generateLeaveRequest();

                const res = http.post(
                    `${BASE_URL}/api/leave`,
                    JSON.stringify(leaveRequest),
                    {
                        headers: authHeaders,
                        tags: { name: 'ApplyLeaveAgain' },
                    }
                );

                check(res, {
                    'Additional leave status is 200': (r) => r.status === 200,
                });
            });
        }
    });

    // Simulate realistic user behavior - not instant
    sleep(1);
}
