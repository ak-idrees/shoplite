
#!/usr/bin/env bash

set -euo pipefail

# =========================
# CONFIGURATION
# =========================

: "${IMAGE_TAG:?ERROR: IMAGE_TAG is required. Example: IMAGE_TAG=abc123 ./deploy.sh}"

AWS_ACCOUNT_ID="836505524477"
AWS_REGION="ap-southeast-2"
REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/db/init.sql" ]; then
    PROJECT_DIR="$SCRIPT_DIR"
else
    PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

cd "$PROJECT_DIR"

FRONTEND_PORT="${FRONTEND_PORT:-80}"

echo "=================================="
echo "       SHOPLITE DEPLOYMENT"
echo "=================================="
echo "Image tag: $IMAGE_TAG"

# =========================
# CHECK REQUIREMENTS
# =========================

for COMMAND in docker aws curl; do
    command -v "$COMMAND" >/dev/null 2>&1 || {
        echo "ERROR: $COMMAND is not installed."
        exit 1
    }
done

if [ ! -f .env ]; then
    echo "ERROR: .env file is missing!"
    exit 1
fi

if [ ! -f db/init.sql ]; then
    echo "ERROR: db/init.sql is missing!"
    exit 1
fi

# =========================
# LOGIN TO ECR
# =========================

echo "Logging in to Amazon ECR..."

aws ecr get-login-password --region "$AWS_REGION" |
    docker login --username AWS --password-stdin "$REGISTRY"

# =========================
# PULL ALL IMAGES FIRST
# =========================

echo "Pulling all four images..."

docker pull "$REGISTRY/shoplite/frontend:$IMAGE_TAG"
docker pull "$REGISTRY/shoplite/catalog:$IMAGE_TAG"
docker pull "$REGISTRY/shoplite/inventory:$IMAGE_TAG"
docker pull "$REGISTRY/shoplite/orders:$IMAGE_TAG"

echo "All images pulled successfully."

# No application containers have been stopped yet.

# =========================
# PREPARE NETWORKS AND VOLUME
# =========================

docker network inspect backend-net >/dev/null 2>&1 || \
    docker network create --internal backend-net

docker network inspect frontend-net >/dev/null 2>&1 || \
    docker network create frontend-net

docker volume inspect pgdata >/dev/null 2>&1 || \
    docker volume create pgdata

# =========================
# KEEP POSTGRESQL RUNNING
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
    echo "PostgreSQL already exists. Preserving it."
    docker start postgres 2>/dev/null || true
fi

# =========================
# WAIT FOR CONTAINER HEALTH
# =========================

wait_healthy() {
    local CONTAINER="$1"

    echo "Waiting for $CONTAINER to become healthy..."

    for i in $(seq 1 30); do
        local STATUS
        STATUS="$(docker inspect -f \
            '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' \
            "$CONTAINER")"

        if [ "$STATUS" = "healthy" ]; then
            echo "$CONTAINER is healthy."
            return 0
        fi

        if [ "$STATUS" = "unhealthy" ] || [ "$STATUS" = "no-healthcheck" ]; then
            echo "ERROR: $CONTAINER status is $STATUS."
            docker logs --tail 30 "$CONTAINER"
            return 1
        fi

        sleep 2
    done

    echo "ERROR: $CONTAINER did not become healthy."
    docker logs --tail 30 "$CONTAINER"
    return 1
}

wait_healthy postgres

# =========================
# DEPLOY BACKEND SERVICES
# =========================

start_backend() {
    local NAME="$1"
    local IMAGE="$2"
    local HEALTH_COMMAND="$3"

    echo "Replacing $NAME..."

    docker rm -f "$NAME" 2>/dev/null || true

    docker run -d \
        --name "$NAME" \
        --network backend-net \
        --network-alias "$NAME" \
        --env-file .env \
        --restart unless-stopped \
        --health-cmd="$HEALTH_COMMAND" \
        --health-interval=10s \
        --health-timeout=5s \
        --health-retries=5 \
        --health-start-period=10s \
        "$REGISTRY/shoplite/$IMAGE:$IMAGE_TAG"

    docker network connect frontend-net "$NAME"

    wait_healthy "$NAME"
}

start_backend catalog catalog \
    'node -e "fetch(\"http://127.0.0.1:3000/health\").then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"'

start_backend inventory inventory \
    '/inventory-service -healthcheck'

start_backend orders orders \
    'wget -q -O /dev/null http://127.0.0.1:8082/health || exit 1'

# =========================
# DEPLOY FRONTEND LAST
# =========================

echo "Replacing frontend..."

docker rm -f frontend 2>/dev/null || true

docker run -d \
    --name frontend \
    --network frontend-net \
    --env-file .env \
    -e SERVER_NAME="${SERVER_NAME:-_}" \
    -p "$FRONTEND_PORT:80" \
    --restart unless-stopped \
    --health-cmd='wget -q -O /dev/null http://127.0.0.1/api/catalog/health || exit 1' \
    --health-interval=10s \
    --health-timeout=5s \
    --health-retries=5 \
    --health-start-period=10s \
    "$REGISTRY/shoplite/frontend:$IMAGE_TAG"

wait_healthy frontend

# =========================
# FRONTEND API SMOKE TEST
# =========================

echo "Checking frontend catalog API..."

HEALTHY=false

for i in $(seq 1 60); do
    if curl -fsS \
        "http://127.0.0.1:${FRONTEND_PORT}/api/catalog/health" \
        >/dev/null; then
        HEALTHY=true
        break
    fi

    sleep 1
done

if [ "$HEALTHY" != true ]; then
    echo "ERROR: Frontend catalog API did not respond within 60 seconds."
    docker logs --tail 30 frontend
    exit 1
fi

echo "Frontend catalog API is responding."

# =========================
# REMOVE OLD UNUSED IMAGES
# =========================

echo "Removing unused images older than seven days..."

docker image prune -af --filter "until=168h"

# =========================
# DEPLOYMENT COMPLETE
# =========================

echo "=================================="
echo " SHOPLITE DEPLOYMENT SUCCESSFUL"
echo " Image tag: $IMAGE_TAG"
echo "=================================="

docker ps
