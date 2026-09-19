#!/bin/sh
# Generate config.js from environment variables
if [ ! -z "$API_URL" ]; then
  echo "globalThis.env = { API_URL: \"$API_URL\" };" > /usr/share/nginx/html/config.js
fi

# Substitute BACKEND_HOST in nginx config if provided (defaults to backend)
if [ ! -z "$BACKEND_HOST" ]; then
  sed -i "s|proxy_pass http://backend:3000;|proxy_pass http://${BACKEND_HOST}:3000;|g" /etc/nginx/conf.d/default.conf
fi

