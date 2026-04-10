# 🚀 LOAD TEST START HERE - Quick Navigation Guide

## Choose Your Path Based on What You Need

---

## 🏃 **Path 1: I Want to Run It NOW (5 minutes)**
**Best for:** "Just get it working!"

**Read:** 
1. [LOAD_TEST_QUICK_COMMANDS.md](LOAD_TEST_QUICK_COMMANDS.md) - Copy-paste the exact commands

**Then:**
```bash
# Terminal 1: Grafana dashboards
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Terminal 2: Prometheus queries
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Terminal 3: Backend metrics
kubectl port-forward svc/backend 9464:9464

# Terminal 4: Watch pods scale
watch -n 2 'kubectl get pods -l app=backend'

# Terminal 5: Run the test!
cd load-test && k6 run advanced-scenario.js
```

**Result:** 23-minute test with 100 concurrent users ✓

---

## 📋 **Path 2: I Want Step-by-Step Guidance (15 minutes)**
**Best for:** "Walk me through exactly what to do"

**Read:** 
1. [LOAD_TEST_MONITORING_CHECKLIST.md](LOAD_TEST_MONITORING_CHECKLIST.md)
   - Pre-test checklist for verification
   - Step-by-step execution
   - Grafana panel setup (copy-paste PromQL queries)
   - Timeline expectations
   - Success criteria

**Timeline:**
- Pre-test checklist: 5 minutes
- Setup monitoring: 5 minutes
- Run test: 23 minutes
- Verify results: 5 minutes

---

## 📚 **Path 3: I Want Complete Reference (30 minutes)**
**Best for:** "I want to understand everything"

**Read in this order:**
1. [LOAD_TEST_IMPLEMENTATION_SUMMARY.md](LOAD_TEST_IMPLEMENTATION_SUMMARY.md) - 5 min read
   - Overview of what's been created
   - What each script does
   - Success indicators

2. [LOAD_TEST_ARCHITECTURE_DIAGRAMS.md](LOAD_TEST_ARCHITECTURE_DIAGRAMS.md) - 10 min read
   - System architecture
   - Request flows
   - Metrics collection
   - Test stages explained
   - Performance expectations

3. [LOAD_TEST_REALTIME_WALKTHROUGH.md](LOAD_TEST_REALTIME_WALKTHROUGH.md) - 10 min read
   - Minute-by-minute what you'll see
   - Expected values at each stage
   - Verification checklist
   - Troubleshooting

4. [LOAD_TEST_COMPLETE_GUIDE.md](LOAD_TEST_COMPLETE_GUIDE.md) - 5 min skim
   - Alternative deployment options
   - Advanced scenarios

---

## 🎯 **Path 4: I Want Specific Answers (5-10 minutes)**
**Best for:** "Just answer my question"

**Common Questions:**

| Question | Answer | File |
|----------|--------|------|
| How long does the test take? | 23 minutes min (advanced), 15 min (basic), or custom | LOAD_TEST_QUICK_COMMANDS.md |
| What user stories are tested? | Registration, Login, Apply Leave, View Leaves | LOAD_TEST_IMPLEMENTATION_SUMMARY.md |
| What should I watch for? | Active users → 100, Pods → 5, Latency < 500ms | LOAD_TEST_REALTIME_WALKTHROUGH.md |
| What metrics will appear? | active_users, leave_requests_total, latency, errors (20 total) | LOAD_TEST_COMPLETE_GUIDE.md |
| How do I set up Grafana? | 8 panels with copy-paste PromQL queries | LOAD_TEST_MONITORING_CHECKLIST.md |
| What if something goes wrong? | Troubleshooting guide at end | LOAD_TEST_REALTIME_WALKTHROUGH.md |
| Can I run this locally? | Yes, or on Kubernetes, or manually curl | LOAD_TEST_COMPLETE_GUIDE.md |
| Do I need to pre-create users? | Optional: basic script registers users, pre-populated script uses 100 existing users | LOAD_TEST_IMPLEMENTATION_SUMMARY.md |

---

## 📍 File Map

```
load-test/
├─ script.js                              ← Quick test (15 min, 50 users)
├─ advanced-scenario.js                   ← Main test (23 min, 100 users) ✓ RECOMMENDED
├─ pre-populated-users.js                 ← Alternative (23 min, 100 pre-created users)
└─ setup-monitoring.sh                    ← Verify prerequisites (1 min)

Documentation/
├─ LOAD_TEST_START_HERE.md               ← You are here! Navigation guide
├─ LOAD_TEST_QUICK_COMMANDS.md            ← Copy-paste commands (FASTEST)
├─ LOAD_TEST_MONITORING_CHECKLIST.md      ← Step-by-step guide (MOST DETAILED)
├─ LOAD_TEST_IMPLEMENTATION_SUMMARY.md    ← What was built (OVERVIEW)
├─ LOAD_TEST_ARCHITECTURE_DIAGRAMS.md     ← System design (VISUAL)
├─ LOAD_TEST_REALTIME_WALKTHROUGH.md      ← What you'll see (PRACTICAL)
└─ LOAD_TEST_COMPLETE_GUIDE.md            ← Full reference (COMPREHENSIVE)
```

---

## 🛠️ **First Time? Do This:**

### Step 1: Verify Everything Ready (1 minute)
```bash
bash load-test/setup-monitoring.sh
```
Should show: ✓ kubectl ready, ✓ k6 installed, ✓ cluster connected, ✓ monitoring running

### Step 2: Choose Your Test Script

| Script | Duration | Load | Best For |
|--------|----------|------|----------|
| `script.js` | 15 min | Ramps to 50 | Quick validation |
| `advanced-scenario.js` | 23 min | Ramps to 100 | Full test (RECOMMENDED) |
| `pre-populated-users.js` | 23 min | 100 pre-created | No registration phase |

### Step 3: Open 5 Terminals
```
Terminal 1: kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
Terminal 2: kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
Terminal 3: kubectl port-forward svc/backend 9464:9464
Terminal 4: watch -n 2 'kubectl get pods -l app=backend'
Terminal 5: cd load-test && k6 run advanced-scenario.js
```

### Step 4: Watch It Happen
Open http://localhost:3000 (Grafana) in browser → Watch metrics climb!

### Step 5: Verify Success
- ✓ Active users reached 100?
- ✓ Pods scaled from 1 to 5?
- ✓ Latency stayed under 500ms?
- ✓ 100 leave requests submitted?
- ✓ Error rate under 5%?

If YES to all: **🎉 LOAD TEST SUCCESSFUL!**

---

## 🎯 What Success Looks Like

```
✅ Load Test Completed Successfully!

Key Results:
- Peak Concurrent Users: 100 ✓
- Total Requests: 5,000+ ✓
- Success Rate: 95%+ ✓
- Latency P95: < 500ms ✓
- Error Rate: < 5% ✓
- Pod Scaling: 1 → 5 pods ✓
- Metrics Collected: 20+ custom metrics ✓
- Leave Requests Submitted: ~100 ✓

System Status:
✓ No pod crashes
✓ No database errors
✓ Memory stable (no leaks)
✓ CPU well distributed
✓ Database keeping up
✓ All metrics flowing to Grafana
✓ All logs in Loki
✓ All traces in Tempo
```

---

## 📊 Dashboard Queries Ready to Copy-Paste

All Grafana queries are ready in [LOAD_TEST_MONITORING_CHECKLIST.md](LOAD_TEST_MONITORING_CHECKLIST.md) and [LOAD_TEST_QUICK_COMMANDS.md](LOAD_TEST_QUICK_COMMANDS.md):

1. **Active Users** - Shows current concurrent users (target: 100)
2. **Request Rate** - Requests per second (target: 50+)
3. **Latency P95** - 95th percentile response time (target: < 500ms)
4. **Error Rate** - Percentage of failed requests (target: < 5%)
5. **Leave Requests Total** - Total leave requests submitted (target: ~100)
6. **Pod Count** - Number of backend pods (target: scales 1→5)
7. **Database Query P95** - Database performance (target: < 200ms)
8. **Login Success Rate** - Auth success percentage (target: > 98%)

---

## 🔥 TL;DR - Super Quick Start

```bash
# 1. Check everything is ready
bash load-test/setup-monitoring.sh

# 2. Open 5 terminals (copy-paste from LOAD_TEST_QUICK_COMMANDS.md)
# Terminal 1: Port-forward Grafana
# Terminal 2: Port-forward Prometheus
# Terminal 3: Port-forward backend metrics
# Terminal 4: Watch pods
# Terminal 5: Run test

# 3. Run load test
cd load-test && k6 run advanced-scenario.js

# 4. Watch http://localhost:3000 (Grafana) for 23 minutes

# 5. Verify:
# - Users: 100 ✓
# - Pods: 5 ✓
# - Latency: < 500ms ✓
# - Errors: < 5% ✓
# - Requests: 5,000+ ✓

# 6. Celebrate! 🎉
```

---

## 🤔 Common Scenarios

**Scenario 1: "I just want to see it work"**
- Read: [LOAD_TEST_QUICK_COMMANDS.md](LOAD_TEST_QUICK_COMMANDS.md)
- Time: 30 minutes (test execution only)

**Scenario 2: "I need to understand it completely"**
- Read: All documentation top to bottom
- Time: 2 hours (reading + test execution)

**Scenario 3: "I need to present this to my team"**
- Show: [LOAD_TEST_ARCHITECTURE_DIAGRAMS.md](LOAD_TEST_ARCHITECTURE_DIAGRAMS.md) (architecture)
- Show: [LOAD_TEST_REALTIME_WALKTHROUGH.md](LOAD_TEST_REALTIME_WALKTHROUGH.md) (real-time results)
- Time: 15 minutes prep + 23 minutes live demo

**Scenario 4: "Something went wrong, help!"**
- Check: [LOAD_TEST_REALTIME_WALKTHROUGH.md](LOAD_TEST_REALTIME_WALKTHROUGH.md) troubleshooting section
- Check: [LOAD_TEST_MONITORING_CHECKLIST.md](LOAD_TEST_MONITORING_CHECKLIST.md) verification steps

---

## 📞 Quick Links

- **Quick Start:** [LOAD_TEST_QUICK_COMMANDS.md](LOAD_TEST_QUICK_COMMANDS.md)
- **Step by Step:** [LOAD_TEST_MONITORING_CHECKLIST.md](LOAD_TEST_MONITORING_CHECKLIST.md)
- **What You'll See:** [LOAD_TEST_REALTIME_WALKTHROUGH.md](LOAD_TEST_REALTIME_WALKTHROUGH.md)
- **Architecture:** [LOAD_TEST_ARCHITECTURE_DIAGRAMS.md](LOAD_TEST_ARCHITECTURE_DIAGRAMS.md)
- **Complete Guide:** [LOAD_TEST_COMPLETE_GUIDE.md](LOAD_TEST_COMPLETE_GUIDE.md)
- **Summary:** [LOAD_TEST_IMPLEMENTATION_SUMMARY.md](LOAD_TEST_IMPLEMENTATION_SUMMARY.md)

---

## ✨ You're All Set!

Everything is ready to run. Pick your path above and get started!

Remember:
- Start with [LOAD_TEST_QUICK_COMMANDS.md](LOAD_TEST_QUICK_COMMANDS.md) if you're in a hurry
- Use [LOAD_TEST_MONITORING_CHECKLIST.md](LOAD_TEST_MONITORING_CHECKLIST.md) if you want detailed verification
- Check [LOAD_TEST_REALTIME_WALKTHROUGH.md](LOAD_TEST_REALTIME_WALKTHROUGH.md) to know what to expect

Let's test this system! 🚀
