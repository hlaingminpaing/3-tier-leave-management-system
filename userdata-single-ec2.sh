#!/bin/bash
# Single-EC2 user data: React frontend (Nginx) + Node backend (PM2) on one instance.
# Nginx serves the SPA on :80 and proxies /api/* to the backend on 127.0.0.1:3000.
set -euo pipefail
exec > >(tee /var/log/user-data.log) 2>&1

export AWS_DEFAULT_REGION=ap-southeast-7
APP_DIR=/home/ec2-user/app
REPO_URL=https://github.com/hlaingminpaing/3-tier-leave-management-system.git

# ---------- System packages ----------
dnf update -y
curl -fsSL https://rpm.nodesource.com/setup_22.x | bash -
dnf install -y nodejs git nginx mariadb105 jq

# ---------- Clone repo (once) ----------
if [ ! -d "$APP_DIR" ]; then
  git clone "$REPO_URL" "$APP_DIR"
fi

# ---------- Fetch all secrets from ONE SSM parameter (JSON) ----------
CONFIG_JSON=$(aws ssm get-parameter --name "/leave-app/production/config" --with-decryption \
  --query "Parameter.Value" --output text)

DB_HOST=$(echo "$CONFIG_JSON" | jq -r '.DB_HOST')
DB_USER=$(echo "$CONFIG_JSON" | jq -r '.DB_USER')
DB_PASS=$(echo "$CONFIG_JSON" | jq -r '.DB_PASS')
DB_NAME=$(echo "$CONFIG_JSON" | jq -r '.DB_NAME')
JWT_SECRET=$(echo "$CONFIG_JSON" | jq -r '.JWT_SECRET')

for v in DB_HOST DB_USER DB_PASS DB_NAME JWT_SECRET; do
  if [ -z "${!v}" ] || [ "${!v}" = "null" ]; then
    echo "ERROR: $v missing from /leave-app/production/config" >&2
    exit 1
  fi
done

# ---------- Backend ----------
cd "$APP_DIR/backend"
npm install --omit=dev

cat > .env << EOF
DB_HOST='$DB_HOST'
DB_USER='$DB_USER'
DB_PASS='$DB_PASS'
DB_NAME='$DB_NAME'
JWT_SECRET='$JWT_SECRET'
PORT=3000
EOF
chmod 600 .env

# ---------- Database init (idempotent) ----------
until mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -e "SELECT 1" &>/dev/null; do
  echo "Waiting for RDS to be ready..."
  sleep 5
done

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
echo "Database tables initialized"

# ---------- Frontend build ----------
cd "$APP_DIR/frontend"
npm install
VITE_API_URL="/api" npm run build

rm -rf /usr/share/nginx/html/*
cp -r dist/* /usr/share/nginx/html/

# ---------- Nginx: SPA + reverse proxy to backend ----------
# Remove the default server block in nginx.conf so ours is the only one on :80
sed -i '/^\s*server\s*{/,/^\s*}/d' /etc/nginx/nginx.conf || true

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

    # API -> Node backend (backend already mounts its router at /api, so no prefix stripping)
    location ^~ /api/ {
        proxy_pass http://backend;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 60s;
    }

    # Backend health check (useful for ALB/monitoring)
    location = /health {
        proxy_pass http://backend/health;
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

# Allow Nginx to connect to the local backend if SELinux is enforcing
if command -v setsebool &>/dev/null; then
  setsebool -P httpd_can_network_connect 1 || true
fi

nginx -t
systemctl enable --now nginx
systemctl reload nginx

# ---------- Permissions ----------
chown -R ec2-user:ec2-user "$APP_DIR"

# ---------- PM2 ----------
npm install -g pm2

sudo -u ec2-user bash << 'USEREOF'
cd /home/ec2-user/app/backend
pm2 delete backend 2>/dev/null || true
pm2 start app.js --name backend
pm2 save
USEREOF

env PATH=$PATH:/usr/bin pm2 startup systemd -u ec2-user --hp /home/ec2-user
systemctl enable pm2-ec2-user

echo "Deployment complete: frontend on :80, API proxied at /api -> :3000"
