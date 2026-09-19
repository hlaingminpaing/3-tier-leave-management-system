require("./instrumentation-enhanced"); // OpenTelemetry Setup MUST be first
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

/* ROOT HEALTH CHECK (For Target Group Health Checks) */
// This was from deploy/aws
app.get("/health", (_, res) => res.send("OK"));

/* API ROUTER (For ALB Routed Requests) */
const apiRouter = express.Router();

/* API HEALTH & READINESS CHECKS */
apiRouter.get("/health", (_, res) => res.json({ status: "healthy" }));
apiRouter.get("/ready", (_, res) => res.json({ status: "ready" }));

/* REGISTER USER */
apiRouter.post("/register", async (req, res) => {
  const { username, password, role } = req.body;
  const hash = await bcrypt.hash(password, 10);

  db.query(
    "INSERT INTO users (username,password,role) VALUES (?,?,?)",
    [username, hash, role || "EMPLOYEE"],
    (err) => {
      if (err) {
        console.error("Database error:", err);
        return res.status(500).json({ error: "Database error. Is MySQL running?" });
      }
      trackRegistration(username, role || "EMPLOYEE");
      res.json({ message: "User created" });
    }
  );
});

/* LOGIN */
apiRouter.post("/login", (req, res) => {
  const { username, password } = req.body;

  db.query(
    "SELECT * FROM users WHERE username=?",
    [username],
    async (err, rows) => {
      if (err) {
        console.error("Database error:", err);
        return res.status(500).json({ error: "Database error. Is MySQL running?" });
      }

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

      // Track successful login and active user
      trackLoginAttempt(true, username);
      setActiveUser(rows[0].id);

      res.json({ token, role: rows[0].role });
    }
  );
});

/* EMPLOYEE APPLY LEAVE */
apiRouter.post("/leave", auth(), (req, res) => {
  const { start_date, end_date, reason } = req.body;

  db.query(
    "INSERT INTO leave_requests (user_id,start_date,end_date,reason) VALUES (?,?,?,?)",
    [req.user.id, start_date, end_date, reason],
    (err) => {
      if (err) {
        console.error("Database error:", err);
        return res.status(500).json({ error: "Database error" });
      }
      // Track leave request submission for Prometheus metric leave_requests_total
      trackLeaveRequest(req.user.id, start_date, end_date, reason);
      res.json({ message: "Leave submitted" });
    }
  );
});

/* EMPLOYEE VIEW OWN LEAVES */
apiRouter.get("/leave", auth(), (req, res) => {
  db.query(
    "SELECT * FROM leave_requests WHERE user_id=?",
    [req.user.id],
    (err, rows) => {
      if (err) {
        console.error("Database error:", err);
        return res.status(500).json({ error: "Database error" });
      }
      res.json(rows);
    }
  );
});

/* ADMIN VIEW ALL LEAVES */
apiRouter.get("/admin/leaves", auth("ADMIN"), (_, res) => {
  db.query(
    "SELECT lr.*, u.username FROM leave_requests lr JOIN users u ON lr.user_id=u.id",
    (err, rows) => {
      if (err) {
        console.error("Database error:", err);
        return res.status(500).json({ error: "Database error" });
      }

      // Update leave requests by status for Prometheus gauge leave_requests_by_status
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

  db.query(
    "UPDATE leave_requests SET status=? WHERE id=?",
    [status, req.params.id],
    (err) => {
      if (err) {
        console.error("Database error:", err);
        return res.status(500).json({ error: "Database error" });
      }
      trackLeaveStatusUpdate(req.params.id, status, req.user.id);
      res.json({ message: "Updated" });
    }
  );
});

// MOUNT THE ROUTER AT /api
app.use("/api", apiRouter);

if (require.main === module) {
  app.listen(3000, () => console.log("Backend running on 3000"));
}

module.exports = app;
