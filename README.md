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
9. [Backend Tier Deployment](#9-backend-tier-deployment)
10. [Frontend Tier Deployment](#10-frontend-tier-deployment)
11. [Auto Scaling Configuration](#11-auto-scaling-configuration)
12. [Testing and Validation](#12-testing-and-validation)
13. [Monitoring and Maintenance](#13-monitoring-and-maintenance)

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
│  - Frontend ASG (Nginx + React)                 │
│  - Backend ASG (Node.js)                        │
└─────────────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────────────┐
│  Private DB Subnets (2 AZs)                     │
│  - RDS MySQL (Multi-AZ)                         │
└─────────────────────────────────────────────────┘
```

### Traffic Flow

- **Frontend**: `http://alb-dns-name.elb.amazonaws.com/` → Frontend Target Group (Port 80)
- **Backend API**: `http://alb-dns-name.elb.amazonaws.com/api/*` → Backend Target Group (Port 3000)

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

Create **4 security groups** with least-privilege access:

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

### 4.2 Frontend Security Group

```
Name: leave-system-frontend-sg
Description: Security group for Frontend EC2 instances
VPC: leave-system-vpc
```

**Inbound Rules:**
| Type | Protocol | Port | Source | Description |
|------|----------|------|--------|-------------|
| HTTP | TCP | 80 | leave-system-alb-sg | Allow HTTP from ALB |
| SSH | TCP | 22 | Your-IP/32 | SSH access (optional, for debugging) |

**Outbound Rules:**
| Type | Protocol | Port | Destination | Description |
|------|----------|------|-------------|-------------|
| All traffic | All | All | 0.0.0.0/0 | Allow all outbound |

### 4.3 Backend Security Group

```
Name: leave-system-backend-sg
Description: Security group for Backend EC2 instances
VPC: leave-system-vpc
```

**Inbound Rules:**
| Type | Protocol | Port | Source | Description |
|------|----------|------|--------|-------------|
| Custom TCP | TCP | 3000 | leave-system-alb-sg | Allow API traffic from ALB |
| SSH | TCP | 22 | Your-IP/32 | SSH access (optional, for debugging) |

**Outbound Rules:**
| Type | Protocol | Port | Destination | Description |
|------|----------|------|-------------|-------------|
| All traffic | All | All | 0.0.0.0/0 | Allow all outbound |

### 4.4 RDS Security Group

```
Name: leave-system-rds-sg
Description: Security group for RDS MySQL database
VPC: leave-system-vpc
```

**Inbound Rules:**
| Type | Protocol | Port | Source | Description |
|------|----------|------|--------|-------------|
| MySQL/Aurora | TCP | 3306 | leave-system-backend-sg | Allow MySQL from backend |

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
> - The value must be valid JSON (escape `"` and `\` inside values). Validate it with `echo '<json>' | jq .` before saving.
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

### 8.1 Create Target Groups

#### Target Group 1: Backend

1. **Navigate to EC2 → Target Groups → Create target group**

2. **Configuration**
   ```
   Target type: Instances
   Target group name: leave-system-backend-tg
   Protocol: HTTP
   Port: 3000
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

4. **Create target group** (don't register targets yet)

#### Target Group 2: Frontend

1. **Create another target group**

2. **Configuration**
   ```
   Target type: Instances
   Target group name: leave-system-frontend-tg
   Protocol: HTTP
   Port: 80
   VPC: leave-system-vpc
   Protocol version: HTTP1
   ```

3. **Health Check Settings**
   ```
   Health check protocol: HTTP
   Health check path: /
   Advanced health check settings:
     - Healthy threshold: 2
     - Unhealthy threshold: 3
     - Timeout: 5 seconds
     - Interval: 30 seconds
     - Success codes: 200
   ```

4. **Create target group**

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
   Default action: Forward to leave-system-frontend-tg
   ```

7. **Create Load Balancer**

8. **Wait for State: Active** (~3-5 minutes)

9. **Note the DNS Name**
   - Copy the DNS name (e.g., `leave-system-alb-1234567890.us-east-1.elb.amazonaws.com`)

### 8.3 Configure Listener Rules

1. **Select the ALB → Listeners tab**

2. **Click on the HTTP:80 listener → Manage rules**

3. **Add Rules** (in order):

   **Rule 1: Backend API Routing**
   ```
   Priority: 1
   IF: Path is /api/*
   THEN: Forward to leave-system-backend-tg
   ```

   **Default Rule: Frontend Routing**
   ```
   Already configured to forward to leave-system-frontend-tg
   ```

4. **Save rules**

---

## 9. Backend Tier Deployment

### 9.1 Create Backend Launch Template

1. **Navigate to EC2 → Launch Templates → Create launch template**

2. **Launch Template Name and Description**
   ```
   Launch template name: LeaveApp-Backend-LT
   Template version description: Backend Node.js application v1
   ```

3. **Application and OS Images (AMI)**
   ```
   Quick Start: Amazon Linux
   Amazon Machine Image: Amazon Linux 2023 AMI (latest)
   Architecture: 64-bit (x86)
   ```

4. **Instance Type**
   ```
   Instance type: t3.micro (or t3.small for better performance)
   ```

5. **Key Pair**
   ```
   Key pair name: Select your existing key pair (or create new)
   ```

6. **Network Settings**
   ```
   Subnet: Don't include in launch template (will be set by ASG)
   Firewall (security groups): Select existing security group
     - leave-system-backend-sg
   ```

7. **Advanced Details**
   
   **IAM Instance Profile:**
   ```
   IAM instance profile: LeaveApp-EC2-Role
   ```

   **User Data:**
   
   Replace `YOUR_GITHUB_USER` and `YOUR_REPO_NAME` with your actual values:

   ```bash
   #!/bin/bash
   set -e

   # Update system
   dnf update -y

   # Install Node.js 22 (LTS)
   curl -fsSL https://rpm.nodesource.com/setup_22.x | bash -
   dnf install -y nodejs git nginx

   # Create application directory
   cd /home/ec2-user

   # Clone repository and checkout deploy/aws branch
   git clone https://github.com/hlaingminpaing/3-tier-leave-management-system.git app
   cd app/backend

   # Install dependencies
   npm install

   # Fetch all secrets from ONE SSM parameter (JSON)
   export AWS_DEFAULT_REGION=ap-southeast-7
   dnf install -y jq

   CONFIG_JSON=$(aws ssm get-parameter --name "/leave-app/production/config" --with-decryption --query "Parameter.Value" --output text)

   DB_HOST=$(echo "$CONFIG_JSON" | jq -r '.DB_HOST')
   DB_USER=$(echo "$CONFIG_JSON" | jq -r '.DB_USER')
   DB_PASS=$(echo "$CONFIG_JSON" | jq -r '.DB_PASS')
   DB_NAME=$(echo "$CONFIG_JSON" | jq -r '.DB_NAME')
   JWT_SECRET=$(echo "$CONFIG_JSON" | jq -r '.JWT_SECRET')

   # Create .env file with quoted values to handle special characters
   cat > .env << EOF
   DB_HOST='$DB_HOST'
   DB_USER='$DB_USER'
   DB_PASS='$DB_PASS'
   DB_NAME='$DB_NAME'
   JWT_SECRET='$JWT_SECRET'
   PORT=3000
   EOF

   # Set proper permissions
   chown -R ec2-user:ec2-user /home/ec2-user/app
   chmod 600 /home/ec2-user/app/backend/.env

   # Initialize database tables (run only once, idempotent)
   dnf install -y mariadb105
   
   # Wait for RDS to be ready
   until mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -e "SELECT 1" &>/dev/null; do
     echo "Waiting for RDS to be ready..."
     sleep 5
   done

   # Create tables if they don't exist
   mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" << 'SQLEOF'
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

   echo "Database tables initialized successfully"

   # Install PM2 globally
   npm install -g pm2

   # Start application with PM2 as ec2-user
   sudo -u ec2-user bash << 'USEREOF'
   cd /home/ec2-user/app/backend
   pm2 start app.js --name "backend"
   pm2 save
   USEREOF

   # Configure PM2 to start on boot
   env PATH=$PATH:/usr/bin pm2 startup systemd -u ec2-user --hp /home/ec2-user
   systemctl enable pm2-ec2-user
   ```

8. **Create Launch Template**

### 9.2 Database Tables Initialization

**Important:** The user data script above automatically creates the database tables (`users` and `leave_requests`) when the first backend instance launches. The script uses `CREATE TABLE IF NOT EXISTS`, so it's safe to run multiple times and won't cause errors if tables already exist.

**What happens:**
1. The script installs MySQL client
2. Waits for RDS to be ready
3. Creates the `users` and `leave_requests` tables if they don't exist
4. This runs on every backend instance launch, but only creates tables once

**Manual Setup (Optional):**
If you prefer to create tables manually before launching instances:
```bash
mysql -h your-rds-endpoint.rds.amazonaws.com -u admin -p
USE leave_db;
-- Then run the CREATE TABLE statements from db.sql
```

---

## 10. Frontend Tier Deployment

### 10.1 Create Frontend Launch Template

1. **Navigate to EC2 → Launch Templates → Create launch template**

2. **Launch Template Name and Description**
   ```
   Launch template name: LeaveApp-Frontend-LT
   Template version description: Frontend React application v1
   ```

3. **Application and OS Images (AMI)**
   ```
   Quick Start: Amazon Linux
   Amazon Machine Image: Amazon Linux 2023 AMI (latest)
   Architecture: 64-bit (x86)
   ```

4. **Instance Type**
   ```
   Instance type: t3.small (needs more RAM for npm build)
   ```

5. **Key Pair**
   ```
   Key pair name: Select your existing key pair
   ```

6. **Network Settings**
   ```
   Subnet: Don't include in launch template
   Firewall (security groups): Select existing security group
     - leave-system-frontend-sg
   ```

7. **Advanced Details**
   
   **IAM Instance Profile:**
   ```
   IAM instance profile: LeaveApp-EC2-Role
   ```

   **User Data:**
   
   Replace `YOUR_GITHUB_USER` and `YOUR_REPO_NAME`:

   ```bash
   #!/bin/bash
   set -e

   # Update system
   dnf update -y

   # Install Node.js 22 (Vite requires Node 20+)
   curl -fsSL https://rpm.nodesource.com/setup_22.x | bash -
   dnf install -y nodejs git nginx jq

   # Create application directory
   cd /home/ec2-user

   # Clone repository and checkout deploy/aws branch
   git clone https://github.com/hlaingminpaing/3-tier-leave-management-system.git app
   cd app/frontend

   # Install dependencies
   npm install

   # Read API route from the shared SSM config parameter (fallback: /api)
   export AWS_DEFAULT_REGION=ap-southeast-7
   CONFIG_JSON=$(aws ssm get-parameter --name "/leave-app/production/config" --with-decryption --query "Parameter.Value" --output text)
   export VITE_API_URL=$(echo "$CONFIG_JSON" | jq -r '.API_URL // "/api"')

   # Build production bundle
   npm run build

   # Deploy to Nginx
   rm -rf /usr/share/nginx/html/*
   cp -r dist/* /usr/share/nginx/html/

   # Configure Nginx for React SPA
   cat > /etc/nginx/conf.d/default.conf << 'EOF'
   server {
       listen 80;
       server_name _;
       root /usr/share/nginx/html;
       index index.html;

       # Enable gzip compression
       gzip on;
       gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

       # SPA routing - serve index.html for all routes
       location / {
           try_files $uri $uri/ /index.html;
       }

       # Cache static assets
       location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
           expires 1y;
           add_header Cache-Control "public, immutable";
       }
   }
   EOF

   # Start and enable Nginx
   systemctl enable nginx
   systemctl start nginx
   ```

8. **Create Launch Template**

---

## 11. Auto Scaling Configuration

### 11.1 Create Backend Auto Scaling Group

1. **Navigate to EC2 → Auto Scaling Groups → Create Auto Scaling group**

2. **Step 1: Choose Launch Template**
   ```
   Auto Scaling group name: leave-system-backend-asg
   Launch template: LeaveApp-Backend-LT
   Version: Latest
   ```

3. **Step 2: Choose Instance Launch Options**
   ```
   VPC: leave-system-vpc
   Availability Zones and subnets:
     - leave-system-app-subnet-1a
     - leave-system-app-subnet-1b
   ```

4. **Step 3: Configure Advanced Options**
   ```
   Load balancing: Attach to an existing load balancer
   Choose from your load balancer target groups:
     - leave-system-backend-tg
   
   Health checks:
     ✅ ELB health checks
     Health check grace period: 300 seconds
   ```

5. **Step 4: Configure Group Size and Scaling**
   ```
   Desired capacity: 2
   Minimum capacity: 1
   Maximum capacity: 4
   
   Scaling policies: Target tracking scaling policy
     - Metric type: Average CPU utilization
     - Target value: 70
     - Instance warmup: 300 seconds
   ```

6. **Step 5: Add Notifications** (Optional)
   - Skip for now

7. **Step 6: Add Tags**
   ```
   Key: Name
   Value: leave-system-backend
   ```

8. **Create Auto Scaling Group**

### 11.2 Create Frontend Auto Scaling Group

1. **Create another Auto Scaling group**

2. **Step 1: Choose Launch Template**
   ```
   Auto Scaling group name: leave-system-frontend-asg
   Launch template: LeaveApp-Frontend-LT
   Version: Latest
   ```

3. **Step 2: Choose Instance Launch Options**
   ```
   VPC: leave-system-vpc
   Availability Zones and subnets:
     - leave-system-app-subnet-1a
     - leave-system-app-subnet-1b
   ```

4. **Step 3: Configure Advanced Options**
   ```
   Load balancing: Attach to an existing load balancer
   Choose from your load balancer target groups:
     - leave-system-frontend-tg
   
   Health checks:
     ✅ ELB health checks
     Health check grace period: 300 seconds
   ```

5. **Step 4: Configure Group Size and Scaling**
   ```
   Desired capacity: 2
   Minimum capacity: 1
   Maximum capacity: 4
   
   Scaling policies: Target tracking scaling policy
     - Metric type: Average CPU utilization
     - Target value: 70
     - Instance warmup: 300 seconds
   ```

6. **Step 5: Add Tags**
   ```
   Key: Name
   Value: leave-system-frontend
   ```

7. **Create Auto Scaling Group**

---

## 12. Testing and Validation

### 12.1 Wait for Instances to Launch

1. **Check Auto Scaling Groups**
   - EC2 → Auto Scaling Groups
   - Verify both ASGs show "Desired: 2, Current: 2"

2. **Check Target Group Health**
   - EC2 → Target Groups
   - Select each target group
   - Targets tab → Wait for status "healthy" (~5-10 minutes)

### 12.2 Test the Application

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

### 12.3 Troubleshooting

If targets are unhealthy:

1. **Check Security Groups**
   - Verify ALB can reach instances on correct ports
   - Verify backend can reach RDS on port 3306

2. **Check Instance Logs via Session Manager**
   ```
   # Connect to instance via Session Manager
   sudo su - ec2-user
   cd /home/ec2-user/app/backend
   pm2 logs
   ```

3. **Check User Data Execution**
   ```
   sudo cat /var/log/cloud-init-output.log
   ```

4. **Verify SSM Parameters**
   ```
   aws ssm get-parameter --name "/leave-app/production/config" --with-decryption \
     --query "Parameter.Value" --output text | jq .
   ```

---

## 13. Monitoring and Maintenance

### 13.1 CloudWatch Monitoring

1. **Navigate to CloudWatch → Dashboards**

2. **Create Dashboard: leave-system-dashboard**

3. **Add Widgets:**
   - ALB Request Count
   - ALB Target Response Time
   - EC2 CPU Utilization (by ASG)
   - RDS CPU Utilization
   - RDS Database Connections

### 13.2 Set Up Alarms

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

### 13.3 Backup Strategy

**RDS Automated Backups:**
- Already configured (7-day retention)
- Manual snapshots before major changes

**Application Code:**
- Version controlled in GitHub
- Tag releases for rollback capability

### 13.4 Update Strategy

**To Deploy New Code:**

1. **Update Launch Template**
   - Create new version with updated user data or AMI
   - Set as default version

2. **Instance Refresh**
   - Auto Scaling Groups → Instance refresh
   - This gradually replaces instances with zero downtime

**Alternative: Blue/Green Deployment**
- Create new ASG with new launch template
- Attach to same target groups
- Gradually shift traffic
- Terminate old ASG

---

## 📊 Cost Estimation (Monthly)

| Resource | Configuration | Estimated Cost |
|----------|--------------|----------------|
| EC2 Instances | 4x t3.micro (2 frontend, 2 backend) | ~$30 |
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