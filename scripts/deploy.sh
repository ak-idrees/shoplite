
#!/usr/bin/env bash

set -euo pipefail

# =========================
# CONFIGURATION
# =========================

AWS_ACCOUNT_ID="836505524477"
AWS_REGION="ap-southeast-2"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

TAG="${TAG:-latest}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$PROJECT_DIR"

echo "Starting ShopLite deployment..."
echo "Image tag: $TAG"

# =========================
# CHECK REQUIREMENTS
# =========================

command -v docker >/dev/null 2>&1 || {
    echo "ERROR: Docker is not installed."
    exit 1
}

command -v aws >/dev/null 2>&1 || {
    echo "ERROR: AWS CLI is not installed."
    exit 1
}

if [ ! -f .env ]; then
    echo "ERROR: .env file is missing!"
    exit 1
fi

# =========================
# LOGIN TO ECR
# =========================

echo "Logging in to ECR..."

aws ecr get-login-password --region "$AWS_REGION" |
    docker login --username AWS --password-stdin "$ECR_REGISTRY"

# =========================
# PULL NEW IMAGES
# =========================

echo "Pulling new images..."

docker pull "$ECR_REGISTRY/shoplite-frontend:$TAG"
docker pull "$ECR_REGISTRY/shoplite-catalog:$TAG"
docker pull "$ECR_REGISTRY/shoplite-inventory:$TAG"
docker pull "$ECR_REGISTRY/shoplite-orders:$TAG"

# =========================
# REMOVE OLD APPLICATION CONTAINERS
# =========================

echo "Removing old application containers..."

for CONTAINER in frontend orders inventory catalog; do
    docker rm -f "$CONTAINER" 2>/dev/null || true
done

# =========================
# START NEW CONTAINERS
# =========================

echo "Starting new containers..."

export TAG
export FRONTEND_PORT="${FRONTEND_PORT:-80}"
export SERVER_NAME="${SERVER_NAME:-_}"
export IMAGE_PREFIX="$ECR_REGISTRY/"

bash "$PROJECT_DIR/scripts/up.sh"

echo "ShopLite deployment completed."
docker ps

