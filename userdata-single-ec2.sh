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
