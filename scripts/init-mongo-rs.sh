#!/usr/bin/env bash

# Sourced from .env if running from host setup directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
if [[ -f "$PARENT_DIR/.env" ]]; then
    set -a
    source <(grep -E '^[A-Za-z0-9_]+=' "$PARENT_DIR/.env" | tr -d '\r') 2>/dev/null || true
    set +a
fi

if [[ -z "$MONGO_CONTAINER" ]]; then
    # Dynamically find running mongodb container for this compose project/directory if available
    MONGO_CONTAINER=$(cd "$PARENT_DIR" && docker compose ps mongodb --format '{{.Name}}' 2>/dev/null | head -n1 || true)
    if [[ -z "$MONGO_CONTAINER" ]]; then
        MONGO_CONTAINER=$(docker ps --filter "name=mongodb" --format '{{.Names}}' 2>/dev/null | head -n1 || true)
    fi
    if [[ -z "$MONGO_CONTAINER" ]]; then
        MONGO_CONTAINER="mongodb"
    fi
fi

MONGO_USER="${MONGODB_USER}"
MONGO_PASS="${MONGODB_PASS}"

echo "Waiting for MongoDB container ($MONGO_CONTAINER)..."

until docker exec "$MONGO_CONTAINER" \
    mongosh \
    --quiet \
    -u "$MONGO_USER" \
    -p "$MONGO_PASS" \
    --authenticationDatabase admin \
    --eval "db.adminCommand({ ping: 1 })" \
    >/dev/null 2>&1 || \
    docker exec "$MONGO_CONTAINER" \
    mongosh \
    --quiet \
    --eval "db.adminCommand({ ping: 1 })" \
    >/dev/null 2>&1
do
    sleep 2
done

echo "MongoDB is ready."

echo "Checking replica set status..."

IS_OK=""
if [[ -n "$MONGO_USER" && -n "$MONGO_PASS" ]]; then
    IS_OK=$(docker exec "$MONGO_CONTAINER" mongosh --quiet -u "$MONGO_USER" -p "$MONGO_PASS" --authenticationDatabase admin --eval "rs.status().ok" 2>/dev/null || true)
fi

if [[ "$IS_OK" != "1" ]]; then
    IS_OK=$(docker exec "$MONGO_CONTAINER" mongosh --quiet --eval "rs.status().ok" 2>/dev/null || true)
fi

if echo "$IS_OK" | grep -q "1"; then

    echo "Replica set already initialized."

else

    echo "Initializing replica set..."

    INIT_CMD='rs.initiate({ _id: "rs0", members: [{ _id: 0, host: "mongodb:27017" }] })'

    # Try authenticated initiation first, fallback to unauthenticated (localhost exception before admin user creation)
    if [[ -n "$MONGO_USER" && -n "$MONGO_PASS" ]]; then
        INIT_OUT=$(docker exec "$MONGO_CONTAINER" mongosh --quiet -u "$MONGO_USER" -p "$MONGO_PASS" --authenticationDatabase admin --eval "$INIT_CMD" 2>&1 || true)
    else
        INIT_OUT=$(docker exec "$MONGO_CONTAINER" mongosh --quiet --eval "$INIT_CMD" 2>&1 || true)
    fi

    if [[ "$INIT_OUT" == *"requires authentication"* ]] || [[ "$INIT_OUT" == *"AuthenticationFailed"* ]]; then
        INIT_OUT=$(docker exec "$MONGO_CONTAINER" mongosh --quiet --eval "$INIT_CMD" 2>&1 || true)
    fi

    echo "Replica set initialization response: $INIT_OUT"

fi

echo "Waiting for PRIMARY..."

until docker exec "$MONGO_CONTAINER" \
    mongosh \
    --quiet \
    -u "$MONGO_USER" \
    -p "$MONGO_PASS" \
    --authenticationDatabase admin \
    --eval "db.adminCommand({ hello: 1 }).isWritablePrimary" \
    2>/dev/null | grep -q "true" || \
    docker exec "$MONGO_CONTAINER" \
    mongosh \
    --quiet \
    --eval "db.adminCommand({ hello: 1 }).isWritablePrimary" \
    2>/dev/null | grep -q "true"
do
    sleep 2
done

echo "MongoDB PRIMARY is ready."
