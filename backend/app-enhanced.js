// app-enhanced.js - Example of app.js with integrated metrics
// This shows how to integrate metrics into your existing app.js

require("./instrumentation"); // OpenTelemetry Setup MUST be first
require("dotenv").config();
const express = require("express");
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const db = require("./db");
const auth = require("./auth");

// Import metrics middleware and tracking functions
const {
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
} = require("./metrics-middleware");

const app = express();
app.use(express.json());

/* METRICS MIDDLEWARE - Track all HTTP requests */
app.use(metricsMiddleware);

/* CORS */
app.use((req, res, next) => {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Headers", "*");
    next();
});

/* ROOT HEALTH CHECK */
app.get("/health", (_, res) => res.send("OK"));

/* METRICS ENDPOINT - Prometheus scrapes this */
// (Automatically exposed by OpenTelemetry at :9464/metrics)

/* API ROUTER */
const apiRouter = express.Router();

/* API HEALTH CHECK */
apiRouter.get("/health", (_, res) => res.json({ status: "healthy" }));

/* REGISTER USER */
apiRouter.post("/register", async (req, res) => {
    const { username, password, role } = req.body;
    const hash = await bcrypt.hash(password, 10);

    // Create database span for tracing
    const dbSpan = createDatabaseSpan('INSERT', 'INSERT INTO users (username,password,role) VALUES (?,?,?)');

    const startTime = Date.now();

    db.query(
        "INSERT INTO users (username,password,role) VALUES (?,?,?)",
        [username, hash, role || "EMPLOYEE"],
        (err) => {
            const duration = Date.now() - startTime;
            dbSpan.recordDuration(duration);

            if (err) {
                console.error("Database error:", err);
                dbSpan.recordError(err);
                return res.status(500).json({ error: "Database error. Is MySQL running?" });
            }

            dbSpan.span.end();

            // Track registration
            trackRegistration(username, role || "EMPLOYEE");

            res.json({ message: "User created" });
        }
    );
});

/* LOGIN */
apiRouter.post("/login", (req, res) => {
    const { username, password } = req.body;

    const dbSpan = createDatabaseSpan('SELECT', 'SELECT * FROM users WHERE username=?');
    const startTime = Date.now();

    db.query(
        "SELECT * FROM users WHERE username=?",
        [username],
        async (err, rows) => {
            const duration = Date.now() - startTime;
            dbSpan.recordDuration(duration);

            if (err) {
                console.error("Database error:", err);
                dbSpan.recordError(err);
                trackAuthenticationError('database_error', err.message);
                return res.status(500).json({ error: "Database error. Is MySQL running?" });
            }

            dbSpan.span.end();

            if (!rows.length) {
                trackLoginAttempt(false, username);
                return res.sendStatus(401);
            }

            const valid = await bcrypt.compare(password, rows[0].password);
            if (!valid) {
                trackLoginAttempt(false, username);
                return res.sendStatus(401);
            }

            const token = jwt.sign(
                { id: rows[0].id, role: rows[0].role },
                process.env.JWT_SECRET
            );

            // Track successful login
            trackLoginAttempt(true, username);
            setActiveUser(rows[0].id);

            res.json({ token, role: rows[0].role });
        }
    );
});

/* EMPLOYEE APPLY LEAVE */
apiRouter.post("/leave", auth(), (req, res) => {
    const { start_date, end_date, reason } = req.body;

    // Calculate days for metrics
    const startDate = new Date(start_date);
    const endDate = new Date(end_date);
    const daysRequested = (endDate - startDate) / (1000 * 60 * 60 * 24) + 1;

    const dbSpan = createDatabaseSpan('INSERT', 'INSERT INTO leave_requests (user_id,start_date,end_date,reason) VALUES (?,?,?,?)');
    const startTime = Date.now();

    db.query(
        "INSERT INTO leave_requests (user_id,start_date,end_date,reason) VALUES (?,?,?,?)",
        [req.user.id, start_date, end_date, reason],
        (err) => {
            const duration = Date.now() - startTime;
            dbSpan.recordDuration(duration);

            if (err) {
                console.error("Database error:", err);
                dbSpan.recordError(err);
                return res.status(500).json({ error: "Database error" });
            }

            dbSpan.span.end();

            // Track leave request submission
            trackLeaveRequest(req.user.id, start_date, end_date, reason);

            res.json({ message: "Leave submitted" });
        }
    );
});

/* EMPLOYEE VIEW OWN LEAVES */
apiRouter.get("/leave", auth(), (req, res) => {
    const dbSpan = createDatabaseSpan('SELECT', 'SELECT * FROM leave_requests WHERE user_id=?');
    const startTime = Date.now();

    db.query(
        "SELECT * FROM leave_requests WHERE user_id=?",
        [req.user.id],
        (err, rows) => {
            const duration = Date.now() - startTime;
            dbSpan.recordDuration(duration);

            if (err) {
                console.error("Database error:", err);
                dbSpan.recordError(err);
                return res.status(500).json({ error: "Database error" });
            }

            dbSpan.span.end();
            res.json(rows);
        }
    );
});

/* ADMIN VIEW ALL LEAVES */
apiRouter.get("/admin/leaves", auth("ADMIN"), (_, res) => {
    const dbSpan = createDatabaseSpan('SELECT', 'SELECT lr.*, u.username FROM leave_requests lr JOIN users u ON lr.user_id=u.id');
    const startTime = Date.now();

    db.query(
        "SELECT lr.*, u.username FROM leave_requests lr JOIN users u ON lr.user_id=u.id",
        (err, rows) => {
            const duration = Date.now() - startTime;
            dbSpan.recordDuration(duration);

            if (err) {
                console.error("Database error:", err);
                dbSpan.recordError(err);
                return res.status(500).json({ error: "Database error" });
            }

            dbSpan.span.end();

            // Update leave requests by status for metrics
            if (rows) {
                const statusCounts = {};
                rows.forEach(row => {
                    const status = row.status || 'PENDING';
                    statusCounts[status] = (statusCounts[status] || 0) + 1;
                });
                globalThis.leaveRequestsByStatus = statusCounts;
            }

            res.json(rows);
        }
    );
});

/* ADMIN APPROVE / REJECT */
apiRouter.post("/admin/leave/:id", auth("ADMIN"), (req, res) => {
    const { status } = req.body;
    const leaveId = req.params.id;

    const dbSpan = createDatabaseSpan('UPDATE', 'UPDATE leave_requests SET status=? WHERE id=?');
    const startTime = Date.now();

    db.query(
        "UPDATE leave_requests SET status=? WHERE id=?",
        [status, leaveId],
        (err) => {
            const duration = Date.now() - startTime;
            dbSpan.recordDuration(duration);

            if (err) {
                console.error("Database error:", err);
                dbSpan.recordError(err);
                return res.status(500).json({ error: "Database error" });
            }

            dbSpan.span.end();

            // Track leave status update
            trackLeaveStatusUpdate(leaveId, status, req.user.id);

            res.json({ message: "Updated" });
        }
    );
});

/* CUSTOM ENDPOINT: Get Active Users Count */
apiRouter.get("/metrics/active-users", (_, res) => {
    res.json({ active_users: getActiveUserCount() });
});

/* CUSTOM ENDPOINT: Get Application Stats */
apiRouter.get("/metrics/stats", auth("ADMIN"), (_, res) => {
    res.json({
        active_users: getActiveUserCount(),
        leave_requests_by_status: globalThis.leaveRequestsByStatus || {},
        approval_rate: globalThis.leaveApprovalStats || {},
        timestamp: new Date().toISOString(),
    });
});

// MOUNT THE ROUTER AT /api
app.use("/api", apiRouter);

if (require.main === module) {
    app.listen(3000, () => console.log("Backend running on 3000"));
}

module.exports = app;
