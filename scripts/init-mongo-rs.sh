#!/usr/bin/env bash

set -e

MONGO_CONTAINER="${MONGO_CONTAINER:-mongodb}"
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
    >/dev/null 2>&1
do
    sleep 2
done

echo "MongoDB is ready."

echo "Checking replica set status..."

if docker exec "$MONGO_CONTAINER" \
    mongosh \
    --quiet \
    -u "$MONGO_USER" \
    -p "$MONGO_PASS" \
    --authenticationDatabase admin \
    --eval "rs.status().ok" \
    2>/dev/null | grep -q "1"; then

    echo "Replica set already initialized."

else

    echo "Initializing replica set..."

    docker exec "$MONGO_CONTAINER" \
        mongosh \
        --quiet \
        -u "$MONGO_USER" \
        -p "$MONGO_PASS" \
        --authenticationDatabase admin \
        --eval '
            rs.initiate({
                _id: "rs0",
                members: [
                    {
                        _id: 0,
                        host: "mongodb:27017"
                    }
                ]
            })
        '

    echo "Replica set initialized."

fi

echo "Waiting for PRIMARY..."

until docker exec "$MONGO_CONTAINER" \
    mongosh \
    --quiet \
    -u "$MONGO_USER" \
    -p "$MONGO_PASS" \
    --authenticationDatabase admin \
    --eval "db.adminCommand({ hello: 1 }).isWritablePrimary" \
    2>/dev/null | grep -q "true"
do
    sleep 2
done

echo "MongoDB PRIMARY is ready."
