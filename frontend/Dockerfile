
# =========================
# STAGE 1: BUILDER
# =========================
FROM node:22-alpine AS builder

WORKDIR /app

# Copy package configuration
COPY package*.json ./

# Install dependencies
RUN npm ci

# Copy frontend source
COPY . .

# Build production files
RUN npm run build


# =========================
# STAGE 2: FINAL
# =========================
FROM nginx:alpine AS final

# Copy Vite production files
COPY --from=builder /app/dist/ /usr/share/nginx/html/

# Copy our Nginx configuration
COPY nginx.conf /etc/nginx/templates/default.conf.template

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
