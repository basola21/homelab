#!/bin/bash
set -e

HOMELAB_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Stopping all stacks..."
for stack in infra requests media downloads vpn; do
  echo "    Stopping $stack..."
  docker compose -f "$HOMELAB_DIR/$stack/docker-compose.yml" down
done

echo ""
echo "==> Starting vpn..."
docker compose -f "$HOMELAB_DIR/vpn/docker-compose.yml" up -d

echo "    Waiting for gluetun to be healthy..."
until [ "$(docker inspect --format='{{.State.Health.Status}}' gluetun 2>/dev/null)" = "healthy" ]; do
  echo "    gluetun status: $(docker inspect --format='{{.State.Health.Status}}' gluetun 2>/dev/null)..."
  sleep 5
done
echo "    gluetun is healthy."

echo ""
echo "==> Starting downloads..."
docker compose -f "$HOMELAB_DIR/downloads/docker-compose.yml" up -d

echo ""
echo "==> Starting media..."
docker compose -f "$HOMELAB_DIR/media/docker-compose.yml" up -d

echo ""
echo "==> Starting requests..."
docker compose -f "$HOMELAB_DIR/requests/docker-compose.yml" up -d

echo ""
echo "==> Starting infra..."
docker compose -f "$HOMELAB_DIR/infra/docker-compose.yml" up -d

echo ""
echo "==> All stacks up."
