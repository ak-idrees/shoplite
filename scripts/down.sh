
#!/usr/bin/env bash

set -e

echo "Stopping ShopLite containers..."

# Stop and remove application containers
for CONTAINER in frontend orders inventory catalog postgres; do
    if docker container inspect "$CONTAINER" >/dev/null 2>&1; then
        docker rm -f "$CONTAINER"
        echo "$CONTAINER removed."
    else
        echo "$CONTAINER does not exist."
    fi
done

# Remove Docker networks
docker network rm frontend-net 2>/dev/null || true
docker network rm backend-net 2>/dev/null || true

echo "ShopLite stopped successfully."
echo "PostgreSQL volume pgdata is preserved."
