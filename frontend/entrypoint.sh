#!/bin/sh
# Generate config.js from environment variables
if [ ! -z "$API_URL" ]; then
  echo "globalThis.env = { API_URL: \"$API_URL\" };" > /usr/share/nginx/html/config.js
fi
