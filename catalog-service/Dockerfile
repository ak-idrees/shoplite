
# =========================
# STAGE 1: BUILDER
# =========================
FROM node:22-alpine AS builder

WORKDIR /app

COPY package*.json ./

RUN npm ci --omit=dev


# =========================
# STAGE 2: FINAL
# =========================
FROM node:22-alpine AS final

WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3000

# Copy dependencies from builder
COPY --from=builder /app/node_modules ./node_modules

# Copy application files
COPY package.json ./
COPY src/ ./src/

# Run as non-root user
USER node

EXPOSE 3000

CMD ["node", "src/index.js"]
