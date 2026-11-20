# 🏗️ AWS 3-Tier Architecture Deployment Guide

Complete guide to deploy the Leave Management System on AWS using a production-ready 3-tier architecture with VPC, subnets, load balancers, auto-scaling, and RDS.

---

## 📋 Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Prerequisites](#2-prerequisites)
3. [Network Infrastructure Setup](#3-network-infrastructure-setup)
4. [Security Groups Configuration](#4-security-groups-configuration)
5. [Database Tier (RDS)](#5-database-tier-rds)
6. [Secrets Management (SSM Parameter Store)](#6-secrets-management-ssm-parameter-store)
7. [IAM Roles and Policies](#7-iam-roles-and-policies)
8. [Application Load Balancer Setup](#8-application-load-balancer-setup)
9. [Application Tier Deployment (Frontend + Backend on One EC2)](#9-application-tier-deployment-frontend--backend-on-one-ec2)
10. [Auto Scaling Configuration](#10-auto-scaling-configuration)
11. [Testing and Validation](#11-testing-and-validation)
12. [Monitoring and Maintenance](#12-monitoring-and-maintenance)

---

## 1. Architecture Overview

### Infrastructure Components

```
Internet
    ↓
Application Load Balancer (ALB)
    ↓
┌─────────────────────────────────────────────────┐
│  Public Subnets (2 AZs)                         │
│  - NAT Gateways                                 │
└─────────────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────────────┐
│  Private App Subnets (2 AZs)                    │
│  - App ASG: each EC2 runs                       │
│      Nginx (React build) + Node.js API (PM2)    │
└─────────────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────────────┐
│  Private DB Subnets (2 AZs)                     │
│  - RDS MySQL (Multi-AZ)                         │
└─────────────────────────────────────────────────┘
```

### Traffic Flow

- **All traffic**: `http://alb-dns-name.elb.amazonaws.com/*` → App Target Group (Port 80) → Nginx on each EC2
- **Frontend**: Nginx serves the React build for `/`
- **Backend API**: Nginx proxies `/api/*` to the local Node.js backend on port `3000`. Port 3000 is not opened in the security group, so the backend is only reachable through Nginx

### High Availability

- **Multi-AZ Deployment**: Resources distributed across 2 Availability Zones
- **Auto Scaling**: Automatic scaling based on CPU/traffic
- **RDS Multi-AZ**: Automatic failover for database
- **NAT Gateway**: Redundant NAT Gateways in each AZ

---

## 2. Prerequisites

Before starting, ensure you have:

- [ ] AWS Account with appropriate permissions
- [ ] AWS CLI installed and configured
- [ ] GitHub repository with your application code
- [ ] Domain name (optional, for custom DNS)
- [ ] SSH key pair created in AWS EC2

---

## 3. Network Infrastructure Setup

### 3.1 Create VPC

1. **Navigate to VPC Console**
   - Go to AWS Console → VPC → Your VPCs → Create VPC

2. **VPC Configuration**
   ```
   Name tag: leave-system-vpc
   IPv4 CIDR block: 10.0.0.0/16
   IPv6 CIDR block: No IPv6 CIDR block
   Tenancy: Default
   ```

3. **Enable DNS Settings**
   - Select the VPC → Actions → Edit VPC settings
   - ✅ Enable DNS resolution
   - ✅ Enable DNS hostnames

### 3.2 Create Internet Gateway

1. **Create IGW**
   ```
   Name tag: leave-system-igw
   ```

2. **Attach to VPC**
   - Select IGW → Actions → Attach to VPC
   - Select `leave-system-vpc`

### 3.3 Create Subnets

Create **6 subnets** across **2 Availability Zones**:

#### Public Subnets (for ALB and NAT Gateways)

| Name | AZ | CIDR Block | Type |
|------|-----|------------|------|
| leave-system-public-subnet-1a | ap-southeast-7a | 10.0.1.0/24 | Public |
| leave-system-public-subnet-1b | ap-southeast-7b | 10.0.2.0/24 | Public |

#### Private App Subnets (for EC2 instances)

| Name | AZ | CIDR Block | Type |
|------|-----|------------|------|
| leave-system-app-subnet-1a | ap-southeast-7a | 10.0.11.0/24 | Private |
| leave-system-app-subnet-1b | ap-southeast-7b | 10.0.12.0/24 | Private |

#### Private DB Subnets (for RDS)

| Name | AZ | CIDR Block | Type |
|------|-----|------------|------|
| leave-system-db-subnet-1a | ap-southeast-7a | 10.0.21.0/24 | Private |
| leave-system-db-subnet-1b | ap-southeast-7b | 10.0.22.0/24 | Private |

**Steps to Create Each Subnet:**
1. VPC → Subnets → Create subnet
2. Select VPC: `leave-system-vpc`
3. Enter subnet name, AZ, and CIDR block
4. Click Create subnet

**Enable Auto-assign Public IP for Public Subnets:**
- Select each public subnet → Actions → Edit subnet settings
- ✅ Enable auto-assign public IPv4 address

### 3.4 Create NAT Gateways

Create **2 NAT Gateways** (one per AZ for high availability):

#### NAT Gateway 1 (AZ 1a)
```
Name: leave-system-nat-1a
Subnet: leave-system-public-subnet-1a
Elastic IP: Click "Allocate Elastic IP"
```

#### NAT Gateway 2 (AZ 1b)
```
Name: leave-system-nat-1b
Subnet: leave-system-public-subnet-1b
Elastic IP: Click "Allocate Elastic IP"
```

**Steps:**
1. VPC → NAT Gateways → Create NAT gateway
2. Fill in details and allocate new Elastic IP
3. Wait for status to become "Available" (~5 minutes)

### 3.5 Create Route Tables

Create **3 route tables**:

#### Route Table 1: Public Route Table

```
Name: leave-system-public-rt
VPC: leave-system-vpc
```

**Routes:**
| Destination | Target |
|-------------|--------|
| 10.0.0.0/16 | local |
| 0.0.0.0/0 | leave-system-igw |

**Subnet Associations:**
- leave-system-public-subnet-1a
- leave-system-public-subnet-1b

#### Route Table 2: Private App Route Table (AZ 1a)

```
Name: leave-system-app-rt-1a
VPC: leave-system-vpc
```

**Routes:**
| Destination | Target |
|-------------|--------|
| 10.0.0.0/16 | local |
| 0.0.0.0/0 | leave-system-nat-1a |

**Subnet Associations:**
- leave-system-app-subnet-1a

#### Route Table 3: Private App Route Table (AZ 1b)

```
Name: leave-system-app-rt-1b
VPC: leave-system-vpc
```

**Routes:**
| Destination | Target |
|-------------|--------|
| 10.0.0.0/16 | local |
| 0.0.0.0/0 | leave-system-nat-1b |

**Subnet Associations:**
- leave-system-app-subnet-1b

#### Route Table 4: Private DB Route Table

```
Name: leave-system-db-rt
VPC: leave-system-vpc
```

**Routes:**
| Destination | Target |
|-------------|--------|
| 10.0.0.0/16 | local |

**Subnet Associations:**
- leave-system-db-subnet-1a
- leave-system-db-subnet-1b

**Steps to Create Route Tables:**
1. VPC → Route Tables → Create route table
2. Add routes via "Edit routes"
3. Associate subnets via "Edit subnet associations"

---

## 4. Security Groups Configuration

Create **3 security groups** with least-privilege access:

### 4.1 ALB Security Group

```
Name: leave-system-alb-sg
Description: Security group for Application Load Balancer
VPC: leave-system-vpc
```

**Inbound Rules:**
| Type | Protocol | Port | Source | Description |
|------|----------|------|--------|-------------|
| HTTP | TCP | 80 | 0.0.0.0/0 | Allow HTTP from internet |
| HTTPS | TCP | 443 | 0.0.0.0/0 | Allow HTTPS from internet (optional) |

**Outbound Rules:**
| Type | Protocol | Port | Destination | Description |
|------|----------|------|-------------|-------------|
| All traffic | All | All | 0.0.0.0/0 | Allow all outbound |

### 4.2 App Security Group

Used by the EC2 instances that run both the frontend (Nginx) and backend (Node.js).

```
Name: leave-system-app-sg
Description: Security group for App EC2 instances (frontend + backend)
VPC: leave-system-vpc
```

**Inbound Rules:**
| Type | Protocol | Port | Source | Description |
|------|----------|------|--------|-------------|
| HTTP | TCP | 80 | leave-system-alb-sg | Allow HTTP from ALB |
| SSH | TCP | 22 | Your-IP/32 | SSH access (optional, for debugging) |

> Port `3000` is **not** opened. The backend runs on port 3000, but the ALB only talks to Nginx on port 80, and Nginx forwards to the backend inside the instance.

**Outbound Rules:**
| Type | Protocol | Port | Destination | Description |
|------|----------|------|-------------|-------------|
| All traffic | All | All | 0.0.0.0/0 | Allow all outbound |

### 4.3 RDS Security Group

```
Name: leave-system-rds-sg
Description: Security group for RDS MySQL database
VPC: leave-system-vpc
```

**Inbound Rules:**
| Type | Protocol | Port | Source | Description |
|------|----------|------|--------|-------------|
| MySQL/Aurora | TCP | 3306 | leave-system-app-sg | Allow MySQL from app instances |

**Outbound Rules:**
| Type | Protocol | Port | Destination | Description |
|------|----------|------|-------------|-------------|
| All traffic | All | All | 0.0.0.0/0 | Allow all outbound |

---

## 5. Database Tier (RDS)

### 5.1 Create DB Subnet Group

1. **Navigate to RDS Console**
   - RDS → Subnet groups → Create DB subnet group

2. **Configuration**
   ```
   Name: leave-system-db-subnet-group
   Description: Subnet group for Leave System RDS
   VPC: leave-system-vpc
   ```

3. **Add Subnets**
   - Availability Zones: us-east-1a, us-east-1b
   - Subnets: 
     - leave-system-db-subnet-1a (10.0.21.0/24)
     - leave-system-db-subnet-1b (10.0.22.0/24)

### 5.2 Create RDS MySQL Instance

1. **Navigate to RDS → Databases → Create database**

2. **Engine Options**
   ```
   Engine type: MySQL
   Edition: MySQL Community
   Version: MySQL 8.0.35 (or latest)
   ```

3. **Templates**
   ```
   Select: Free tier (for testing) OR Production (for production)
   ```

4. **Settings**
   ```
   DB instance identifier: leave-system-db
   Master username: admin
   Master password: [Create a strong password - save this!]
   ```

5. **Instance Configuration**
   ```
   DB instance class: 
     - Free tier: db.t3.micro
     - Production: db.t3.small or larger
   ```

6. **Storage**
   ```
   Storage type: General Purpose SSD (gp3)
   Allocated storage: 20 GB
   ✅ Enable storage autoscaling
   Maximum storage threshold: 100 GB
   ```

7. **Connectivity**
   ```
   VPC: leave-system-vpc
   DB subnet group: leave-system-db-subnet-group
   Public access: No
   VPC security group: Choose existing → leave-system-rds-sg
   Availability Zone: No preference
   ```

8. **Database Authentication**
   ```
   Database authentication: Password authentication
   ```

9. **Additional Configuration**
   ```
   Initial database name: leave_db
   ✅ Enable automated backups
   Backup retention period: 7 days
   ✅ Enable encryption (optional but recommended)
   ```

10. **Create Database**
    - Click "Create database"
    - Wait for status to become "Available" (~10-15 minutes)

11. **Note the Endpoint**
    - After creation, copy the endpoint (e.g., `leave-system-db.xxxxxxxxx.us-east-1.rds.amazonaws.com`)
    - You'll need this for the SSM parameters

---

## 6. Secrets Management (SSM Parameter Store)

Store sensitive configuration in AWS Systems Manager Parameter Store.

### 6.1 Create the Parameter

All application configuration (database, JWT secret and API route) is stored in **one** SecureString parameter as JSON. Both the backend and frontend user data read it with a single API call.

1. **Navigate to Systems Manager → Parameter Store → Create parameter**

2. **Create the parameter:**
```
Name: /leave-app/production/config
Tier: Standard
Type: SecureString
KMS key source: My current account (alias/aws/ssm)
Description: Leave app configuration (DB, JWT secret, API route)
Value: (JSON below)
```

```json
{
  "DB_HOST": "leave-system-db.xxxxxxxxx.ap-southeast-7.rds.amazonaws.com",
  "DB_USER": "admin",
  "DB_PASS": "YOUR_RDS_MASTER_PASSWORD",
  "DB_NAME": "leave_db",
  "JWT_SECRET": "YOUR_RANDOM_64_CHAR_SECRET",
  "API_URL": "/api"
}
```

| Key | Description |
|-----|-------------|
| `DB_HOST` | RDS MySQL endpoint |
| `DB_USER` | RDS master username |
| `DB_PASS` | RDS master password |
| `DB_NAME` | Database name |
| `JWT_SECRET` | JWT signing secret |
| `API_URL` | Frontend API base route, baked into the build as `VITE_API_URL` (use `/api` for ALB/Nginx routing) |

**Generate JWT Secret:**
```bash
# On Linux/Mac
openssl rand -base64 64 | tr -d '\n'

# On Windows PowerShell
[Convert]::ToBase64String((1..64 | ForEach-Object { Get-Random -Maximum 256 }))
```

**Or create it with the AWS CLI:**
```bash
aws ssm put-parameter \
  --region ap-southeast-7 \
  --name "/leave-app/production/config" \
  --type SecureString \
  --overwrite \
  --value '{
    "DB_HOST": "leave-system-db.xxxxxxxxx.ap-southeast-7.rds.amazonaws.com",
    "DB_USER": "admin",
    "DB_PASS": "YOUR_RDS_MASTER_PASSWORD",
    "DB_NAME": "leave_db",
    "JWT_SECRET": "YOUR_RANDOM_64_CHAR_SECRET",
    "API_URL": "/api"
  }'
```

> **Notes**
> - The value must be valid JSON (escape `"` and `\` inside values). Validate it with `echo '<json>' | python3 -m json.tool` before saving.
> - Standard tier SecureString values are limited to 4 KB, which is plenty for this config.
> - To change a DB or JWT value later, update the JSON and relaunch backend instances (or regenerate `.env` and run `pm2 restart backend`).
> - `API_URL` is used at **build time**, so changing it requires rebuilding the frontend (relaunch frontend instances).
> - Both backend and frontend instances use `LeaveApp-EC2-Role`, so both can read this parameter.

---

## 7. IAM Roles and Policies

### 7.1 Create IAM Role for EC2 Instances

1. **Navigate to IAM → Roles → Create role**

2. **Select Trusted Entity**
   ```
   Trusted entity type: AWS service
   Use case: EC2
   ```

3. **Add Permissions - Attach Policies**
   
   **Policy 1: AWS Managed Policy**
   - Search and select: `AmazonSSMManagedInstanceCore`
   - This allows Session Manager access (no SSH keys needed)

4. **Create Inline Policy for SSM Parameters**
   - Click "Create inline policy"
   - Switch to JSON tab
   - Paste the following:

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "ssm:GetParameter"
         ],
         "Resource": [
           "arn:aws:ssm:ap-southeast-7:*:parameter/leave-app/production/config"
         ]
       },
       {
         "Effect": "Allow",
         "Action": [
           "kms:Decrypt"
         ],
         "Resource": "*"
       }
     ]
   }
   ```
   
   - Name: `SSMParameterAccess`
   - Click "Create policy"

5. **Name and Create Role**
   ```
   Role name: LeaveApp-EC2-Role
   Description: IAM role for Leave System EC2 instances
   ```

6. **Create Role**

---

## 8. Application Load Balancer Setup

### 8.1 Create Target Group

One target group is enough: every instance serves the frontend and proxies the API through Nginx on port 80.

1. **Navigate to EC2 → Target Groups → Create target group**

2. **Configuration**
   ```
   Target type: Instances
   Target group name: leave-system-app-tg
   Protocol: HTTP
   Port: 80
   VPC: leave-system-vpc
   Protocol version: HTTP1
   ```

3. **Health Check Settings**
   ```
   Health check protocol: HTTP
   Health check path: /health
   Advanced health check settings:
     - Healthy threshold: 2
     - Unhealthy threshold: 3
     - Timeout: 5 seconds
     - Interval: 30 seconds
     - Success codes: 200
   ```
   Why port 80 + `/health` covers both frontend and backend even though the backend uses port 3000:

   | Situation | ALB request `GET :80/health` | Target status |
   |-----------|------------------------------|---------------|
   | Nginx + backend running | Nginx → `127.0.0.1:3000/health` → `OK` (200) | ✅ healthy |
   | Backend (PM2) stopped/crashed | Nginx can't reach :3000 → **502** | ❌ unhealthy |
   | Nginx stopped | connection refused on :80 | ❌ unhealthy |

   The React files are served by the same Nginx, so if Nginx answers, the frontend is being served too. You do **not** need a second target group on port 3000.

4. **Create target group** (don't register targets — the Auto Scaling Group registers instances automatically)

### 8.2 Create Application Load Balancer

1. **Navigate to EC2 → Load Balancers → Create load balancer**

2. **Select Load Balancer Type**
   - Choose: Application Load Balancer

3. **Basic Configuration**
   ```
   Load balancer name: leave-system-alb
   Scheme: Internet-facing
   IP address type: IPv4
   ```

4. **Network Mapping**
   ```
   VPC: leave-system-vpc
   Mappings: Select both AZs
     - us-east-1a: leave-system-public-subnet-1a
     - us-east-1b: leave-system-public-subnet-1b
   ```

5. **Security Groups**
   ```
   Remove default security group
   Select: leave-system-alb-sg
   ```

6. **Listeners and Routing**
   ```
   Protocol: HTTP
   Port: 80
   Default action: Forward to leave-system-app-tg
   ```

7. **Create Load Balancer**

8. **Wait for State: Active** (~3-5 minutes)

9. **Note the DNS Name**
   - Copy the DNS name (e.g., `leave-system-alb-1234567890.us-east-1.elb.amazonaws.com`)

### 8.3 Listener Rules

No extra path rules are needed. The default action forwards everything to `leave-system-app-tg`, and Nginx on each instance routes `/api/*` to the backend and everything else to the React app.

> If you later add HTTPS, create an `HTTPS:443` listener with an ACM certificate that forwards to `leave-system-app-tg`, and change the `HTTP:80` listener to redirect to HTTPS.

---

## 9. Application Tier Deployment (Frontend + Backend on One EC2)

Each EC2 instance runs the whole application:

```
ALB :80 ──► Nginx :80 (EC2)
              ├── /            → React build (/usr/share/nginx/html)
              ├── /api/*       → proxy → 127.0.0.1:3000/api/*  (Node.js, PM2)
              └── /health      → proxy → 127.0.0.1:3000/health
                                     │
                                     ▼
                                RDS MySQL (3306)
```

### 9.1 Create Launch Template

1. **Navigate to EC2 → Launch Templates → Create launch template**

2. **Launch Template Name and Description**
   ```
   Launch template name: LeaveApp-App-LT
   Template version description: Frontend (Nginx + React) + Backend (Node.js) v1
   ✅ Provide guidance to help me set up a template that I can use with EC2 Auto Scaling
   ```

3. **Application and OS Images (AMI)**
   ```
   Quick Start: Amazon Linux
   Amazon Machine Image: Amazon Linux 2023 AMI (latest)   # Amazon Linux 2 is also supported
   Architecture: 64-bit (x86)
   ```

4. **Instance Type**
   ```
   Instance type: t3.small (minimum — the frontend build needs ~1 GB RAM)
   ```

5. **Key Pair**
   ```
   Key pair name: Select your existing key pair (optional if you use Session Manager)
   ```

6. **Network Settings**
   ```
   Subnet: Don't include in launch template (will be set by ASG)
   Firewall (security groups): Select existing security group
     - leave-system-app-sg
   ```

7. **Advanced Details**

   **IAM Instance Profile:**
   ```
   IAM instance profile: LeaveApp-EC2-Role
   ```

   **User Data:**

   The same script is in the repo as [`userdata-single-ec2.sh`](userdata-single-ec2.sh). It works on **Amazon Linux 2023 and Amazon Linux 2**, and can also be run directly on an existing instance (see [9.4](#94-run-or-re-run-the-script-directly)). It reads all configuration (DB, JWT secret, API route) from the SSM parameter `/leave-app/production/config` created in [6.1](#61-create-the-parameter).

```bash
#!/bin/bash
# =============================================================================
# Leave Management System - single EC2 (frontend + backend on one instance)
#
#   Nginx :80  ├── /            -> React build (/usr/share/nginx/html)
#              ├── API_URL/*    -> Node backend :3000/api/*   (PM2)
#              └── /health      -> Node backend :3000/health  (ALB health check)
#
# Works on Amazon Linux 2023 and Amazon Linux 2.
# Use it as EC2 user data, or run it directly (safe to re-run):
#     sudo bash userdata-single-ec2.sh
#
# Optional overrides (env vars):
#     AWS_REGION   (default ap-southeast-1)
#     SSM_PARAM    (default /leave-app/production/config)
#     REPO_BRANCH  (default main)
#
# SSM parameter value (SecureString, JSON):
#   {"DB_HOST":"...","DB_USER":"admin","DB_PASS":"...","DB_NAME":"leave_db",
#    "JWT_SECRET":"...","API_URL":"/api"}
# Only port 80 needs to be open (ALB target group: HTTP 80, health check /health).
# =============================================================================
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root: sudo bash $0" >&2
  exit 1
fi

exec > >(tee -a /var/log/user-data.log) 2>&1
echo "===== $(date -u) : leave-app deploy start ====="

# cloud-init may not set HOME; npm and git need it
export HOME="${HOME:-/root}"
[ "$HOME" = "/" ] && export HOME=/root

AWS_REGION="${AWS_REGION:-ap-southeast-1}"
export AWS_DEFAULT_REGION="$AWS_REGION"
SSM_PARAM="${SSM_PARAM:-/leave-app/production/config}"
REPO_URL="https://github.com/hlaingminpaing/3-tier-leave-management-system.git"
REPO_BRANCH="${REPO_BRANCH:-main}"
APP_USER="ec2-user"
APP_DIR="/home/${APP_USER}/app"
NODE_MAJOR=22

# ---------- Detect OS ----------
. /etc/os-release
case "${VERSION_ID}" in
  2023*) OS=al2023 ;;
  2)     OS=al2 ;;
  *) echo "ERROR: unsupported OS ${PRETTY_NAME:-unknown} (need Amazon Linux 2023 or 2)" >&2; exit 1 ;;
esac
echo "Detected OS: ${PRETTY_NAME} (${OS})"

node_major() { command -v node >/dev/null 2>&1 && node -v | sed 's/^v\([0-9]*\).*/\1/' || echo 0; }

# ---------- System packages + Node.js ----------
if [ "$OS" = "al2023" ]; then
  dnf -y update
  dnf install -y git nginx mariadb105 python3 tar
  if [ "$(node_major)" -lt "$NODE_MAJOR" ]; then
    curl -fsSL "https://rpm.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
    dnf install -y nodejs
  fi
else
  # Amazon Linux 2: glibc 2.26 is too old for official Node 18+ builds,
  # so use the Node.js project's "unofficial-builds" glibc-217 binaries.
  yum -y update
  yum install -y git python3 tar xz
  amazon-linux-extras install -y nginx1 mariadb10.5
  if [ "$(node_major)" -lt "$NODE_MAJOR" ]; then
    NODE_VER=$(curl -fsSL https://unofficial-builds.nodejs.org/download/release/index.json | python3 -c '
import json, sys
major = sys.argv[1]
for r in json.load(sys.stdin):
    if r["version"].startswith("v" + major + ".") and "linux-x64-glibc-217" in r.get("files", []):
        print(r["version"]); break' "$NODE_MAJOR")
    if [ -z "$NODE_VER" ]; then
      echo "ERROR: could not find a Node ${NODE_MAJOR} glibc-217 build for Amazon Linux 2" >&2
      exit 1
    fi
    echo "Installing Node ${NODE_VER} (glibc-217 build)"
    mkdir -p /usr/local/lib/nodejs
    curl -fsSL "https://unofficial-builds.nodejs.org/download/release/${NODE_VER}/node-${NODE_VER}-linux-x64-glibc-217.tar.xz" \
      | tar -xJ -C /usr/local/lib/nodejs
    ln -sfn "/usr/local/lib/nodejs/node-${NODE_VER}-linux-x64-glibc-217" /usr/local/lib/nodejs/current
    for b in node npm npx; do ln -sf "/usr/local/lib/nodejs/current/bin/$b" "/usr/bin/$b"; done
  fi
fi
echo "Node $(node -v), npm $(npm -v)"

# ---------- Swap (frontend build needs memory on small instances) ----------
MEM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
if [ "$MEM_MB" -lt 2000 ] && [ -z "$(swapon --show 2>/dev/null)" ]; then
  echo "Low memory (${MEM_MB} MB): creating 2 GB swap"
  [ -f /swapfile ] || dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# ---------- Get code (clone or update) ----------
git config --global --add safe.directory "$APP_DIR" || true
if [ -d "$APP_DIR/.git" ]; then
  echo "Updating existing repo in $APP_DIR"
  git -C "$APP_DIR" fetch --depth 1 origin "$REPO_BRANCH"
  git -C "$APP_DIR" reset --hard FETCH_HEAD
else
  rm -rf "$APP_DIR"
  git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$APP_DIR"
fi

# ---------- Read all config from ONE SSM parameter ----------
CONFIG_JSON=$(aws ssm get-parameter --name "$SSM_PARAM" --with-decryption \
  --query "Parameter.Value" --output text)

# Parse with python3. Accepts strict JSON and tolerates common copy/paste problems:
#   - KEY=VALUE lines (.env style)
#   - JSON whose quotes were stripped by PowerShell: {DB_HOST:xxx,DB_USER:admin,...}
#   - smart quotes / trailing commas
PARSED_CFG=$(printf '%s' "$CONFIG_JSON" | python3 -c '
import json, re, shlex, sys
KEYS = ["DB_HOST", "DB_USER", "DB_PASS", "DB_NAME", "JWT_SECRET", "API_URL"]
raw = sys.stdin.read().strip()
cfg, mode = None, "json"
try:
    cfg = json.loads(raw)
except Exception:
    mode = "fallback"
    txt = raw.translate({0x201c: 34, 0x201d: 34, 0x2018: 39, 0x2019: 39})
    try:
        cfg = json.loads(re.sub(r",\s*}", "}", txt))
    except Exception:
        pat = r"[\"\x27]?\b(" + "|".join(KEYS) + r")\b[\"\x27]?\s*[:=]\s*"
        parts = re.split(pat, txt.strip().strip("{}"))
        cfg = {}
        for i in range(1, len(parts) - 1, 2):
            v = parts[i + 1].strip().rstrip(",").strip()
            if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"\x27":
                v = v[1:-1]
            cfg[parts[i]] = v
if not isinstance(cfg, dict) or not cfg:
    masked = re.sub(r"[A-Za-z0-9]", "x", raw[:60])
    sys.stderr.write("ERROR: cannot parse SSM config (length %d). Shape (letters/digits masked): %s\n" % (len(raw), masked))
    sys.exit(1)
if mode != "json":
    sys.stderr.write("WARNING: config is not strict JSON; parsed with fallback. Keys found: %s\n" % ", ".join(k for k in KEYS if k in cfg))
for k in KEYS:
    v = cfg.get(k)
    print("%s=%s" % (k, shlex.quote("" if v is None else str(v))))
') || exit 1
eval "$PARSED_CFG"

API_URL="${API_URL:-/api}"
API_URL="${API_URL%/}"   # strip trailing slash
case "$API_URL" in
  /*) ;;
  *) echo "ERROR: API_URL must be a relative path like /api (got: $API_URL)" >&2; exit 1 ;;
esac

for v in DB_HOST DB_USER DB_PASS DB_NAME JWT_SECRET; do
  if [ -z "${!v}" ]; then
    echo "ERROR: $v missing from $SSM_PARAM" >&2
    exit 1
  fi
  case "${!v}" in
    *\'*) echo "ERROR: $v must not contain a single quote (')" >&2; exit 1 ;;
  esac
done
echo "Config loaded from $SSM_PARAM (DB_HOST=$DB_HOST, DB_NAME=$DB_NAME, API_URL=$API_URL)"

# ---------- Database init (idempotent) ----------
export MYSQL_PWD="$DB_PASS"   # keeps the password off the command line
echo "Waiting for database $DB_HOST:3306 ..."
for i in $(seq 1 60); do
  if mysql -h "$DB_HOST" -u "$DB_USER" -e "SELECT 1" >/dev/null 2>&1; then
    echo "Database reachable"; break
  fi
  if [ "$i" -eq 60 ]; then
    echo "ERROR: cannot connect to MySQL at $DB_HOST:3306 after 5 minutes." >&2
    echo "       Check the RDS security group allows 3306 from this instance, and DB_USER/DB_PASS." >&2
    mysql -h "$DB_HOST" -u "$DB_USER" -e "SELECT 1" || true
    exit 1
  fi
  sleep 5
done

mysql -h "$DB_HOST" -u "$DB_USER" -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`"
mysql -h "$DB_HOST" -u "$DB_USER" "$DB_NAME" << 'SQLEOF'
CREATE TABLE IF NOT EXISTS users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  username VARCHAR(50) UNIQUE,
  password VARCHAR(255),
  role ENUM('EMPLOYEE','ADMIN') DEFAULT 'EMPLOYEE'
);

CREATE TABLE IF NOT EXISTS leave_requests (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT,
  start_date DATE,
  end_date DATE,
  reason VARCHAR(255),
  status ENUM('PENDING','APPROVED','REJECTED') DEFAULT 'PENDING',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
SQLEOF
unset MYSQL_PWD
echo "Database tables ready"

# ---------- Backend ----------
cd "$APP_DIR/backend"
npm ci --omit=dev || npm install --omit=dev

cat > .env << EOF
DB_HOST='$DB_HOST'
DB_USER='$DB_USER'
DB_PASS='$DB_PASS'
DB_NAME='$DB_NAME'
JWT_SECRET='$JWT_SECRET'
PORT=3000
EOF
chmod 600 .env

# ---------- Frontend build ----------
cd "$APP_DIR/frontend"
npm ci || npm install
VITE_API_URL="$API_URL" npm run build

mkdir -p /usr/share/nginx/html
rm -rf /usr/share/nginx/html/*
cp -r dist/* /usr/share/nginx/html/

# ---------- Nginx ----------
# Write a clean main config instead of patching the distro one, so it is the same on AL2 and AL2023.
[ -f /etc/nginx/nginx.conf.orig ] || cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.orig
cat > /etc/nginx/nginx.conf << 'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log notice;
pid /run/nginx.pid;

include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 1024;
}

http {
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    access_log /var/log/nginx/access.log main;

    sendfile            on;
    tcp_nopush          on;
    keepalive_timeout   65;
    types_hash_max_size 4096;
    server_tokens       off;

    include      /etc/nginx/mime.types;
    default_type application/octet-stream;

    include /etc/nginx/conf.d/*.conf;
}
EOF

# Disable any other site configs (e.g. default.conf from the old frontend script)
for f in /etc/nginx/conf.d/*.conf; do
  [ -e "$f" ] || continue
  [ "$(basename "$f")" = "leave-app.conf" ] && continue
  mv -f "$f" "$f.disabled"
done

cat > /etc/nginx/conf.d/leave-app.conf << 'EOF'
upstream backend {
    server 127.0.0.1:3000;
    keepalive 16;
}

server {
    listen 80 default_server;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    # API -> Node backend. Public route comes from SSM API_URL; backend router is mounted at /api.
    location ^~ __API_URL__/ {
        proxy_pass http://backend/api/;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 60s;
    }

    # ALB target group health check: 200 only if Nginx AND the Node backend are up (502 if backend is down)
    location = /health {
        proxy_pass http://backend/health;
        access_log off;
    }

    # Cache static assets
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files $uri =404;
    }

    # SPA routing
    location / {
        try_files $uri $uri/ /index.html;
    }
}
EOF
sed -i "s#__API_URL__#${API_URL}#g" /etc/nginx/conf.d/leave-app.conf

# Allow Nginx to proxy to the local backend if SELinux is enforcing
if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce)" = "Enforcing" ]; then
  setsebool -P httpd_can_network_connect 1 || true
fi

nginx -t
systemctl enable nginx
systemctl restart nginx

# ---------- Permissions ----------
chown -R "$APP_USER:$APP_USER" "$APP_DIR"

# ---------- PM2 ----------
npm install -g pm2
if [ ! -x /usr/bin/pm2 ] && [ -x /usr/local/lib/nodejs/current/bin/pm2 ]; then
  ln -sf /usr/local/lib/nodejs/current/bin/pm2 /usr/bin/pm2
fi
PM2_BIN=$(command -v pm2)
NODE_BIN_DIR=$(dirname "$(readlink -f "$(command -v node)")")

sudo -u "$APP_USER" -H env PATH="$NODE_BIN_DIR:/usr/bin:/bin" bash -c "
  set -e
  cd '$APP_DIR/backend'
  '$PM2_BIN' delete backend >/dev/null 2>&1 || true
  '$PM2_BIN' start app.js --name backend
  '$PM2_BIN' save
"

env PATH="$NODE_BIN_DIR:$PATH" "$PM2_BIN" startup systemd -u "$APP_USER" --hp "/home/$APP_USER"
systemctl enable "pm2-$APP_USER"

# ---------- Verify ----------
echo "Checking http://127.0.0.1/health ..."
for i in $(seq 1 15); do
  if curl -fsS http://127.0.0.1/health >/dev/null 2>&1; then
    echo "Health check OK"
    echo "===== $(date -u) : deploy complete: frontend on :80, API ${API_URL} -> :3000/api ====="
    exit 0
  fi
  sleep 2
done
echo "ERROR: health check failed. Debug with:" >&2
echo "  sudo -u $APP_USER pm2 logs backend --lines 50" >&2
echo "  sudo tail -n 50 /var/log/nginx/error.log" >&2
exit 1
```

8. **Create Launch Template**

### 9.2 Database Tables Initialization

**Important:** The user data script automatically creates the database tables (`users` and `leave_requests`) when an instance launches. It uses `CREATE TABLE IF NOT EXISTS`, so it's safe to run on every instance and won't cause errors if the tables already exist.

**What happens:**
1. The script installs the MySQL client
2. Waits for RDS to be reachable
3. Creates the `users` and `leave_requests` tables if they don't exist

**Manual Setup (Optional):**
If you prefer to create tables manually before launching instances:
```bash
mysql -h your-rds-endpoint.rds.amazonaws.com -u admin -p
USE leave_db;
-- Then run the CREATE TABLE statements from db.sql
```

### 9.3 Provisioning Time

First boot takes about **5–10 minutes** (system update, Node.js install, `npm install`, frontend build). The ASG health check grace period in [10.1](#101-create-auto-scaling-group-attach-existing-alb-target-group) is set to cover this.

### 9.4 Run or Re-run the Script Directly

The script is idempotent, so you can run it by hand on an instance (for example, to fix a failed first boot or to deploy new code):

```bash
curl -fsSL -o userdata-single-ec2.sh \
  https://raw.githubusercontent.com/hlaingminpaing/3-tier-leave-management-system/main/userdata-single-ec2.sh
sudo bash userdata-single-ec2.sh

# Optional overrides
sudo AWS_REGION=ap-southeast-1 SSM_PARAM=/leave-app/production/config REPO_BRANCH=main \
  bash userdata-single-ec2.sh
```

On re-run it pulls the latest code, rewrites `.env` and the Nginx config, rebuilds the frontend and restarts the backend with PM2. It ends with a local `/health` check and exits non-zero if that fails. Output is appended to `/var/log/user-data.log`.

**OS differences handled by the script**

| | Amazon Linux 2023 | Amazon Linux 2 |
|---|---|---|
| Packages | `dnf` | `yum` + `amazon-linux-extras` (`nginx1`, `mariadb10.5`) |
| Node.js 22 | NodeSource RPM | Node.js glibc-217 build from unofficial-builds.nodejs.org (official builds need a newer glibc than AL2 has) |
| Nginx config | Script writes a clean `/etc/nginx/nginx.conf` (original saved as `nginx.conf.orig`) | Same |

> Instances with less than 2 GB RAM get a 2 GB swap file automatically so the frontend build doesn't run out of memory.

---

## 10. Auto Scaling Configuration

### 10.1 Create Auto Scaling Group (Attach Existing ALB Target Group)

Before you start, make sure these already exist:
- Launch template `LeaveApp-App-LT` ([9.1](#91-create-launch-template))
- ALB `leave-system-alb` with target group `leave-system-app-tg` ([section 8](#8-application-load-balancer-setup))

1. **Navigate to EC2 → Auto Scaling Groups → Create Auto Scaling group**

2. **Step 1: Choose launch template**
   ```
   Auto Scaling group name: leave-system-app-asg
   Launch template: LeaveApp-App-LT
   Version: Latest
   ```
   Click **Next**.

3. **Step 2: Choose instance launch options**
   ```
   VPC: leave-system-vpc
   Availability Zones and subnets:
     - leave-system-app-subnet-1a
     - leave-system-app-subnet-1b
   Availability Zone distribution: Balanced best effort
   ```
   Click **Next**.

4. **Step 3: Integrate with other services — attach the existing ALB**
   ```
   Load balancing:
     (•) Attach to an existing load balancer
         ( ) Attach to a new load balancer
         ( ) No load balancer

   Attach to an existing load balancer:
     (•) Choose from your load balancer target groups
         ( ) Choose from Classic Load Balancers

   Existing load balancer target groups:
     ✅ leave-system-app-tg | HTTP   (Application Load Balancer: leave-system-alb)

   VPC Lattice integration options: No VPC Lattice service

   Health checks:
     ✅ Turn on Elastic Load Balancing health checks
     Health check grace period: 600 seconds
   ```
   - Selecting the target group is what connects the ASG to the ALB: every instance the ASG launches is registered in `leave-system-app-tg` automatically, and deregistered when it is terminated.
   - With ELB health checks on, the ASG replaces instances that the target group marks unhealthy.
   - The 600-second grace period gives first boot time to finish the build before health checks count.

   Click **Next**.

5. **Step 4: Configure group size and scaling**
   ```
   Desired capacity: 2
   Minimum capacity: 1
   Maximum capacity: 4

   Automatic scaling: Target tracking scaling policy
     - Scaling policy name: cpu-target-70
     - Metric type: Average CPU utilization
     - Target value: 70
     - Instance warmup: 600 seconds

   Instance maintenance policy: Prioritize availability (launch before terminating)
   ```
   Click **Next**.

6. **Step 5: Add notifications** (Optional) — skip for now

7. **Step 6: Add tags**
   ```
   Key: Name
   Value: leave-system-app
   ✅ Tag new instances
   ```

8. **Step 7: Review → Create Auto Scaling group**

9. **Confirm the attachment**
   - EC2 → Auto Scaling Groups → `leave-system-app-asg` → **Integrations** tab → Load balancing shows `leave-system-app-tg`
   - EC2 → Target Groups → `leave-system-app-tg` → **Targets** tab → instances appear and become `healthy` after provisioning

**Attach to an existing ASG instead** (if the ASG was created without a load balancer):
- EC2 → Auto Scaling Groups → select the ASG → **Integrations** tab → Load balancing → **Edit**
- ✅ Application, Network or Gateway Load Balancer target groups → select `leave-system-app-tg` → **Update**
- **Details** tab → Health checks → **Edit** → ✅ Elastic Load Balancing health checks, grace period 600 → **Update**

**AWS CLI alternative:**
```bash
export AWS_DEFAULT_REGION=ap-southeast-7

TG_ARN=$(aws elbv2 describe-target-groups --names leave-system-app-tg \
  --query "TargetGroups[0].TargetGroupArn" --output text)

aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name leave-system-app-asg \
  --launch-template "LaunchTemplateName=LeaveApp-App-LT,Version=\$Latest" \
  --vpc-zone-identifier "subnet-APP-1A,subnet-APP-1B" \
  --target-group-arns "$TG_ARN" \
  --health-check-type ELB \
  --health-check-grace-period 600 \
  --min-size 1 --max-size 4 --desired-capacity 2 \
  --tags "Key=Name,Value=leave-system-app,PropagateAtLaunch=true"

aws autoscaling put-scaling-policy \
  --auto-scaling-group-name leave-system-app-asg \
  --policy-name cpu-target-70 \
  --policy-type TargetTrackingScaling \
  --target-tracking-configuration '{"PredefinedMetricSpecification":{"PredefinedMetricType":"ASGAverageCPUUtilization"},"TargetValue":70.0}'

# Attach the target group to an existing ASG
aws autoscaling attach-load-balancer-target-groups \
  --auto-scaling-group-name leave-system-app-asg \
  --target-group-arns "$TG_ARN"
```
Replace `subnet-APP-1A,subnet-APP-1B` with the IDs of your private app subnets.

---

## 11. Testing and Validation

### 11.1 Wait for Instances to Launch

1. **Check Auto Scaling Groups**
   - EC2 → Auto Scaling Groups
   - Verify `leave-system-app-asg` shows "Desired: 2, Current: 2"

2. **Check Target Group Health**
   - EC2 → Target Groups
   - Select `leave-system-app-tg`
   - Targets tab → Wait for status "healthy" (~5-10 minutes)

### 11.2 Test the Application

1. **Get ALB DNS Name**
   - EC2 → Load Balancers
   - Copy DNS name: `leave-system-alb-xxxxxxxxx.us-east-1.elb.amazonaws.com`

2. **Test Frontend**
   ```
   Open browser: http://leave-system-alb-xxxxxxxxx.us-east-1.elb.amazonaws.com
   ```
   - Should load the React application

3. **Test Backend API**
   ```
   Open browser: http://leave-system-alb-xxxxxxxxx.us-east-1.elb.amazonaws.com/api/health
   ```
   - Should return: `{"status":"healthy"}`

4. **Test Full Application Flow**
   - Register a new user
   - Login as employee
   - Submit a leave request
   - Login as admin
   - Approve/reject leave request

### 11.3 Troubleshooting

If targets are unhealthy:

1. **Check Security Groups**
   - Verify `leave-system-alb-sg` can reach `leave-system-app-sg` on port 80
   - Verify `leave-system-app-sg` can reach RDS on port 3306

2. **Check Instance Logs via Session Manager**
   ```
   # Connect to instance via Session Manager
   sudo su - ec2-user
   cd /home/ec2-user/app/backend
   pm2 logs
   ```

3. **Check User Data Execution**
   ```
   sudo tail -n 100 /var/log/user-data.log
   sudo cat /var/log/cloud-init-output.log
   ```

4. **Check Nginx and the Local Backend on the Instance**
   ```
   sudo -u ec2-user pm2 status
   sudo nginx -t && systemctl status nginx
   curl -s http://127.0.0.1/health          # via Nginx → backend
   curl -s http://127.0.0.1:3000/api/health # backend directly
   ```

5. **Verify SSM Parameter**
   ```
   aws ssm get-parameter --name "/leave-app/production/config" --with-decryption \
     --query "Parameter.Value" --output text | python3 -m json.tool
   ```

---

## 12. Monitoring and Maintenance

### 12.1 CloudWatch Monitoring

1. **Navigate to CloudWatch → Dashboards**

2. **Create Dashboard: leave-system-dashboard**

3. **Add Widgets:**
   - ALB Request Count
   - ALB Target Response Time
   - EC2 CPU Utilization (by ASG)
   - RDS CPU Utilization
   - RDS Database Connections

### 12.2 Set Up Alarms

**High CPU Alarm:**
```
Metric: EC2 > By Auto Scaling Group > CPUUtilization
Threshold: > 80% for 2 consecutive periods
Action: Send SNS notification
```

**Unhealthy Target Alarm:**
```
Metric: ApplicationELB > TargetGroup > UnHealthyHostCount
Threshold: >= 1 for 2 consecutive periods
Action: Send SNS notification
```

### 12.3 Backup Strategy

**RDS Automated Backups:**
- Already configured (7-day retention)
- Manual snapshots before major changes

**Application Code:**
- Version controlled in GitHub
- Tag releases for rollback capability

### 12.4 Update Strategy

**To Deploy New Code:**

1. **Update Launch Template**
   - Create new version with updated user data or AMI
   - Set as default version

2. **Instance Refresh**
   - Auto Scaling Groups → Instance refresh
   - This gradually replaces instances with zero downtime

**Alternative: Blue/Green Deployment**
- Create new ASG with new launch template
- Attach to the same target group (`leave-system-app-tg`)
- Gradually shift traffic
- Terminate old ASG

---

## 📊 Cost Estimation (Monthly)

| Resource | Configuration | Estimated Cost |
|----------|--------------|----------------|
| EC2 Instances | 2x t3.small (frontend + backend on each) | ~$30 |
| NAT Gateways | 2x NAT Gateway | ~$65 |
| Application Load Balancer | 1x ALB | ~$20 |
| RDS MySQL | 1x db.t3.micro | ~$15 |
| Data Transfer | ~100 GB/month | ~$9 |
| **Total** | | **~$139/month** |

**Cost Optimization Tips:**
- Use single NAT Gateway (reduces HA but saves $32/month)
- Use Reserved Instances for predictable workloads (up to 72% savings)
- Enable RDS storage autoscaling to avoid over-provisioning
- Use CloudWatch to identify underutilized resources

---

## 🎯 Next Steps

- [ ] Configure custom domain with Route 53
- [ ] Add SSL/TLS certificate with ACM
- [ ] Set up CloudWatch Logs for application logging
- [ ] Implement AWS WAF for security
- [ ] Configure S3 for static asset storage
- [ ] Set up CloudFront CDN for better performance
- [ ] Implement CI/CD pipeline with AWS CodePipeline


# 🏗️ EKS 3-Tier Architecture Deployment Guide

This section details how to migrate and deploy the 3-Tier Leave Management System to **Amazon EKS (Elastic Kubernetes Service)**.

### Architecture on EKS

```
Internet
    ↓
AWS Application Load Balancer (ALB)
    ↓
┌─────────────────────────────────────────────────┐
| EKS Cluster                                     |
|                                                 |
|   [Ingress: leave-ingress]                      |
|          ↓               ↓                      |
|    [Svc: frontend]   [Svc: backend]             |
|          ↓               ↓                      |
|    [Pod: frontend]   [Pod: backend]             |
|          |               ↓                      |
└──────────┼───────────────┼──────────────────────┘
           |               |
           ↓               ↓
    [Pod: mysql]   OR   [AWS RDS MySQL]
```

###  Prerequisites

1.  **AWS CLI** installed and configured.
2.  **kubectl** installed.
3.  **eksctl** installed (for creating clusters).
4.  **Docker** installed (to build images).
5.  **Helm** installed (for AWS Load Balancer Controller).

### Create EKS Cluster

Create a cluster with OIDC enabled (required for IAM roles for service accounts):

```bash
eksctl create cluster \
  --name leave-system-cluster \
  --region us-east-1 \
  --version 1.27 \
  --nodegroup-name standard-workers \
  --node-type t3.medium \
  --nodes 2 \
  --with-oidc
```

### Deployment Steps

#### Step 1: Build and Push Docker Images

You need to push your application images to Docker Hub or Amazon ECR.

```bash
# Backend
cd backend
docker build -t your-dockerhub-user/leave-backend:v1 .
docker push your-dockerhub-user/leave-backend:v1

# Frontend
cd frontend
docker build -t your-dockerhub-user/leave-frontend:v1 .
docker push your-dockerhub-user/leave-frontend:v1
```

*Update `k8s/backend.yaml` and `k8s/frontend.yaml` with your new image names.*

#### Step 2: Set Up Database

**Option A: MySQL in EKS (Testing/Dev)**
1.  Apply the MySQL deployment:
    ```
    kubectl apply -f k8s/secrets.yaml
    kubectl apply -f k8s/mysql.yaml
    ```
2.  Wait for the pod to start:
    ```bash
    kubectl wait --for=condition=ready pod -l app=mysql --timeout=120s
    ```
3.  Initialize the database schema:
    ```bash
    # Get Pod Name
    POD=\$(kubectl get pods -l app=mysql -o jsonpath=\"{.items[0].metadata.name}\")
    
    # Run SQL
    kubectl exec -i \$POD -- mysql -u root -proot leave_db < db.sql
    ```

**Option B: AWS RDS (Production)**
1.  Create an RDS instance (MySQL).
2.  Update `k8s/secrets.yaml` with your RDS endpoint, username, and password.
3.  Ensure the RDS Security Group allows traffic from your EKS Node Group Security Group.

#### Step 3: Deploy Application

1.  **Apply Secrets:**
    ```bash
    kubectl apply -f k8s/secrets.yaml
    ```

2.  **Deploy Backend & Frontend:**
    ```bash
    kubectl apply -f k8s/backend.yaml
    kubectl apply -f k8s/frontend.yaml
    ```

#### Step 4: Configure Networking (Ingress)

To expose your application using an AWS Application Load Balancer, you need the **AWS Load Balancer Controller**.

1.  **Install Load Balancer Controller** (if not already installed). Follow the [official AWS guide](https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html).

2.  **Edit Ingress Manifest:**
    *   Open `k8s/ingress.yaml`
    *   Update `alb.ingress.kubernetes.io/certificate-arn` with your ACM Certificate ARN (required for HTTPS).

3.  **Apply Ingress:**
    ```bash
    kubectl apply -f k8s/ingress.yaml
    ```

4.  **Get Load Balancer URL:**
    ```bash
    kubectl get ingress leave-ingress
    ```
    *Copy the `ADDRESS` field (e.g., `k8s-default-leaveing-....us-east-1.elb.amazonaws.com`).*

### Validation

*   **Frontend**: Visit the Load Balancer URL in your browser.
*   **Backend API**: Visit `http://<LOAD_BALANCER_URL>/api/health` ⇒ Should return `{\"status\": \"healthy\"}`.
*   **Database**: Log in to the frontend, register a user, and check if data persists.

### Troubleshooting Common Errors

*   **502 Bad Gateway**: Check backend logs (`kubectl logs -l app=backend`). It usually means the backend cannot connect to the database.
*   **404 Not Found (Frontend)**: Ensure your `k8s/ingress.yaml` has the correct path routing rules.
*   **CrashLoopBackOff**: Check pod logs. Often incorrect database credentials or missing environment variables.
*   **Ingress Address Empty**: Ensure the AWS Load Balancer Controller is running properly (`kubectl get deployment -n kube-system aws-load-balancer-controller`).