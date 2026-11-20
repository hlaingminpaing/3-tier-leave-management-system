# Stage 1: Dependencies
FROM node:24-alpine AS dependencies
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install only production dependencies
RUN npm ci --only=production --omit=dev && \
    npm cache clean --force && \
    # Remove unnecessary files from node_modules to reduce size
    find /app/node_modules -type f -name "*.md" -delete && \
    find /app/node_modules -type f -name "*.ts" -delete && \
    find /app/node_modules -type f -name "*.map" -delete && \
    find /app/node_modules -type d -name "test" -exec rm -rf {} + 2>/dev/null || true && \
    find /app/node_modules -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true && \
    find /app/node_modules -type d -name "docs" -exec rm -rf {} + 2>/dev/null || true && \
    find /app/node_modules -type d -name "examples" -exec rm -rf {} + 2>/dev/null || true

# Stage 2: Production
FROM node:24-alpine AS production
WORKDIR /app

# Install only essential runtime dependencies
RUN apk add --no-cache dumb-init && \
    rm -rf /var/cache/apk/*

# Copy only production dependencies from builder
COPY --from=dependencies /app/node_modules ./node_modules

# Copy application code
COPY . .

# Remove unnecessary files to reduce size
RUN rm -rf \
    .git \
    .gitignore \
    .dockerignore \
    README.md \
    tests \
    *.test.js \
    package-lock.json \
    .env.example

# Create non-root user for security
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001 && \
    chown -R nodejs:nodejs /app

USER nodejs

EXPOSE 3000

# Use dumb-init to handle signals properly
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "app.js"]
