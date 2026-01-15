#!/usr/bin/env bash
# setup_and_test.sh - Automated Forgejo environment for testing migration script

set -e
CONTAINER_IMAGE="codeberg.org/forgejo/forgejo:14.0.0"
CONTAINER_NAME="forgejo-test"
HTTP_PORT=3000
FORGEJO_USER="testuser"
FORGEJO_PASS="Password123!"
FORGEJO_EMAIL="test@example.com"
TOKEN_NAME="test-token-$(date +%s)"

# Cleanup previous runs
if [ "$(docker ps -aq -f name=$CONTAINER_NAME)" ]; then
    echo "Cleaning up existing container..."
    docker rm -f $CONTAINER_NAME
fi

echo "Starting Forgejo container..."
# Using environment variables to bypass the installation wizard
docker run -d --name "$CONTAINER_NAME" \
    -p "$HTTP_PORT:3000" \
    -e "FORGEJO__security__INSTALL_LOCK=true" \
    -e "FORGEJO__database__DB_TYPE=sqlite3" \
    -e "FORGEJO__server__OFFLINE_MODE=false" \
    $CONTAINER_IMAGE

echo "Waiting for Forgejo to be ready..."
MAX_RETRIES=30
COUNT=0
until curl -s "http://localhost:$HTTP_PORT/" >/dev/null; do
    sleep 2
    COUNT=$((COUNT + 1))
    if [ $COUNT -ge $MAX_RETRIES ]; then
        echo "Forgejo failed to start in time."
        docker logs $CONTAINER_NAME
        exit 1
    fi
    echo -n "."
done
echo " Ready!"

echo "Creating admin user: $FORGEJO_USER"
docker exec -u 1000 "$CONTAINER_NAME" forgejo admin user create \
    --username "$FORGEJO_USER" \
    --password "$FORGEJO_PASS" \
    --email "$FORGEJO_EMAIL" \
    --admin --must-change-password=false

echo "Generating access token..."
FORGEJO_TOKEN=$(docker exec -u 1000 "$CONTAINER_NAME" forgejo admin user generate-access-token \
    --username "$FORGEJO_USER" \
    --token-name "$TOKEN_NAME" \
    --scopes all \
    --raw)

if [ -z "$FORGEJO_TOKEN" ]; then
    echo "Failed to generate Forgejo token."
    exit 1
fi

export FORGEJO_URL="http://localhost:$HTTP_PORT"
export FORGEJO_USER="$FORGEJO_USER"
export FORGEJO_TOKEN="$FORGEJO_TOKEN"

# Update .env for direnv support
touch .env
grep -v "^FORGEJO_" .env >.env.tmp || true
{
    cat .env.tmp
    echo "FORGEJO_URL=\"$FORGEJO_URL\""
    echo "FORGEJO_USER=\"$FORGEJO_USER\""
    echo "FORGEJO_TOKEN=\"$FORGEJO_TOKEN\""
} >.env
rm .env.tmp

if command -v direnv >/dev/null 2>&1; then
    echo "Updating direnv..."
    direnv allow . || true
fi

echo "--------------------------------------------------"
echo "Forgejo is ready!"
echo "URL: $FORGEJO_URL"
echo "User: $FORGEJO_USER"
echo "Token: $FORGEJO_TOKEN"
echo "--------------------------------------------------"
echo "Now running github-forgejo-migrate.sh"
echo "Note: You may be prompted for GITHUB_USER and GITHUB_TOKEN if they are not in your environment."
echo "--------------------------------------------------"

# Run the migration script
bash github-forgejo-migrate.sh

echo "--------------------------------------------------"
echo "Migration script finished."
echo "You can check the results at $FORGEJO_URL"

echo ""
read -r -p "Do you want to stop and remove the test container? (y/N): " cleanup
if [[ "$cleanup" =~ ^[yY]$ ]]; then
    echo "Cleaning up..."
    docker rm -f "$CONTAINER_NAME"
    echo "Done."
else
    echo "Keeping container running."
    echo "To clean up later, run: docker rm -f $CONTAINER_NAME"
fi
