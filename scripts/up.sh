
#!/usr/bin/env bash

set -euo pipefail

# =========================
# PROJECT CONFIGURATION
# =========================

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

TAG="${TAG:-1.0.0}"
IMAGE_PREFIX="${IMAGE_PREFIX:-}"
FRONTEND_PORT="${FRONTEND_PORT:-8080}"
SERVER_NAME="${SERVER_NAME:-shoplite.test}"

echo "Starting ShopLite..."
echo "Image tag: $TAG"

# =========================
# CHECK ENVIRONMENT
# =========================

if [ ! -f .env ]; then
    echo "ERROR: .env file is missing!"
    exit 1
fi

if [ ! -f db/init.sql ]; then
    echo "ERROR: db/init.sql is missing!"
    exit 1
fi

# =========================
# PREPARE NETWORKS
# =========================

docker network inspect backend-net >/dev/null 2>&1 || \
    docker network create --internal backend-net

docker network inspect frontend-net >/dev/null 2>&1 || \
    docker network create frontend-net

# =========================
# PREPARE DATABASE VOLUME
# =========================

docker volume inspect pgdata >/dev/null 2>&1 || \
    docker volume create pgdata

# =========================
# START POSTGRESQL
# =========================

if ! docker container inspect postgres >/dev/null 2>&1; then
    echo "Creating PostgreSQL container..."

    docker run -d \
        --name postgres \
        --network backend-net \
        --network-alias postgres \
        --restart unless-stopped \
        --env-file .env \
        -v pgdata:/var/lib/postgresql/data \
        -v "$PROJECT_DIR/db/init.sql:/docker-entrypoint-initdb.d/init.sql:ro" \
        --health-cmd="pg_isready -U shop -d shopdb" \
        --health-interval=10s \
        --health-timeout=5s \
        --health-retries=5 \
        postgres:17-alpine
else
    echo "PostgreSQL already exists. Keeping its data."
    docker start postgres 2>/dev/null || true
fi

# Wait for PostgreSQL to become healthy
echo "Waiting for PostgreSQL..."

for i in $(seq 1 30); do
    STATUS="$(docker inspect -f '{{.State.Health.Status}}' postgres)"

    if [ "$STATUS" = "healthy" ]; then
        echo "PostgreSQL is healthy."
        break
    fi

    if [ "$i" -eq 30 ]; then
        echo "ERROR: PostgreSQL did not become healthy."
        docker logs --tail 30 postgres
        exit 1
    fi

    sleep 2
done

# =========================
# START BACKEND SERVICES
# =========================

start_backend() {
    NAME="$1"
    IMAGE="$2"

    echo "Starting $NAME..."

    docker run -d \
        --name "$NAME" \
        --network backend-net \
        --network-alias "$NAME" \
        --env-file .env \
        --restart unless-stopped \
        "${IMAGE_PREFIX}${IMAGE}:$TAG"

    docker network connect frontend-net "$NAME"
}

start_backend catalog shoplite-catalog
start_backend inventory shoplite-inventory
start_backend orders shoplite-orders

# =========================
# START FRONTEND
# =========================

echo "Starting frontend..."

docker run -d \
    --name frontend \
    --network frontend-net \
    --env-file .env \
    -e SERVER_NAME="$SERVER_NAME" \
    -p "$FRONTEND_PORT:80" \
    --restart unless-stopped \
    "${IMAGE_PREFIX}shoplite-frontend:$TAG"

# =========================
# DEPLOYMENT COMPLETE
# =========================

echo "ShopLite started successfully."
docker ps

