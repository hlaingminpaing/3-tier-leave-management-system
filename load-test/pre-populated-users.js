/**
 * load-test/pre-populated-users.js
 * Load test with pre-populated users (avoids registration race conditions)
 * Focuses on realistic user journeys: login → apply leave → view leaves
 */

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const successRate = new Rate('success');
const loginDuration = new Trend('login_duration');
const leaveDuration = new Trend('leave_request_duration');
const getUserLeavesDuration = new Trend('get_leaves_duration');
const activeLeaveRequests = new Counter('active_leave_requests');

export const options = {
    stages: [
        // Phase 1: Warm-up
        { duration: '2m', target: 20 },
        
        // Phase 2: Ramp-up to 50
        { duration: '3m', target: 50 },
        
        // Phase 3: Peak at 100 concurrent (HPA should trigger)
        { duration: '10m', target: 100 },
        
        // Phase 4: Maintain peak
        { duration: '5m', target: 100 },
        
        // Phase 5: Cool-down
        { duration: '3m', target: 0 },
    ],
    
    thresholds: {
        'http_req_duration': ['p(95)<500', 'p(99)<1000'],
        'login_duration': ['p(95)<300'],
        'leave_request_duration': ['p(95)<500'],
        'errors': ['rate<0.1'],
        'success': ['rate>0.9'],
        'http_reqs': ['rate>50'],
    },
};

const BASE_URL = __ENV.API_URL || 'http://localhost:3000';

/**
 * Pre-populated users - replace with your actual users
 * In production, load from database or CSV
 */
const PRE_POPULATED_USERS = [
    // First 100 users pre-registered for load testing
    ...Array.from({ length: 100 }, (_, i) => ({
        username: `preuser${i + 1}`,
        password: `PrePass${i + 1}@123`,
    })),
];

/**
 * Generate realistic leave request dates
 */
function generateLeaveRequest() {
    const today = new Date();
    const start = new Date(today);
    const end = new Date(today);
    
    start.setDate(today.getDate() + Math.floor(Math.random() * 30));
    end.setDate(start.getDate() + Math.floor(Math.random() * 10) + 1);
    
    const reasons = ['Vacation', 'Sick Leave', 'Personal', 'Bereavement', 'Other'];
    
    return {
        start_date: start.toISOString().split('T')[0],
        end_date: end.toISOString().split('T')[0],
        reason: reasons[Math.floor(Math.random() * reasons.length)],
    };
}

/**
 * Main test function - simulates realistic user behavior
 */
export default function () {
    // Select random user from pre-populated list
    const user = PRE_POPULATED_USERS[Math.floor(Math.random() * PRE_POPULATED_USERS.length)];
    
    group('01 - Login (Pre-populated User)', () => {
        const startTime = Date.now();
        
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

        loginDuration.add(Date.now() - startTime);

        const loginSuccess = check(res, {
            'Login status 200': (r) => r.status === 200,
            'Login returns token': (r) => r.json('token') !== undefined,
        });

        if (!loginSuccess) {
            errorRate.add(1);
            console.error(`Login failed for ${user.username}: ${res.status}`);
            return;
        }

        successRate.add(1);
        const token = res.json('token');
        const headers = {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`,
        };

        sleep(0.5);

        group('02 - Apply Leave Request', () => {
            const startTime = Date.now();
            const leaveRequest = generateLeaveRequest();

            const res = http.post(
                `${BASE_URL}/api/leave`,
                JSON.stringify(leaveRequest),
                {
                    headers: headers,
                    tags: { name: 'ApplyLeave' },
                }
            );

            leaveDuration.add(Date.now() - startTime);

            const applySuccess = check(res, {
                'Apply leave status 200': (r) => r.status === 200,
            });

            if (applySuccess) {
                successRate.add(1);
                activeLeaveRequests.add(1);
            } else {
                errorRate.add(1);
            }
        });

        sleep(0.5);

        group('03 - View Leave History', () => {
            const startTime = Date.now();

            const res = http.get(
                `${BASE_URL}/api/leave`,
                {
                    headers: headers,
                    tags: { name: 'GetLeaves' },
                }
            );

            getUserLeavesDuration.add(Date.now() - startTime);

            check(res, {
                'Get leaves status 200': (r) => r.status === 200,
                'Get leaves returns array': (r) => Array.isArray(r.json()),
            }) || errorRate.add(1);
        });

        // 30% of users apply additional leaves
        if (Math.random() > 0.7) {
            sleep(0.5);
            
            group('04 - Apply Another Leave', () => {
                const leaveRequest = generateLeaveRequest();

                http.post(
                    `${BASE_URL}/api/leave`,
                    JSON.stringify(leaveRequest),
                    {
                        headers: headers,
                        tags: { name: 'ApplyLeaveAgain' },
                    }
                );

                activeLeaveRequests.add(1);
            });
        }
    });

    sleep(1);
}
