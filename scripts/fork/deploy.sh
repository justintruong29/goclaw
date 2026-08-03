#!/usr/bin/env bash
#
# deploy.sh — triển khai fork lên VPS bằng ảnh CI đã dựng (KHÔNG build từ source).
#
# Ảnh được ghim qua GOCLAW_IMAGE trong .env, ví dụ:
#   GOCLAW_IMAGE=ghcr.io/justintruong29/goclaw:fork-v3.15.0-beta.188-20260803
#
# Quay lui = sửa GOCLAW_IMAGE về tag cũ rồi chạy lại script này. Không đụng git,
# không build lại.
#
# Dùng:
#   ./scripts/fork/deploy.sh                                  # dùng .env hiện tại
#   ./scripts/fork/deploy.sh ghcr.io/justintruong29/goclaw:fork-v3.15.0-beta.188-20260803
set -euo pipefail

cd "$(dirname "$0")/../.."

COMPOSE=(-f docker-compose.yml -f docker-compose.postgres.yml -f docker-compose.fork.yml)

if [ $# -ge 1 ]; then
  IMAGE="$1"
  # Ghi đè GOCLAW_IMAGE trong .env để lần deploy sau vẫn dùng đúng ảnh này.
  if grep -q '^GOCLAW_IMAGE=' .env 2>/dev/null; then
    sed -i "s|^GOCLAW_IMAGE=.*|GOCLAW_IMAGE=${IMAGE}|" .env
  else
    echo "GOCLAW_IMAGE=${IMAGE}" >> .env
  fi
fi

IMAGE="$(grep '^GOCLAW_IMAGE=' .env 2>/dev/null | cut -d= -f2- || true)"
IMAGE="${IMAGE:-ghcr.io/justintruong29/goclaw:release}"

echo "==> Triển khai: ${IMAGE}"

# Lưu lại ảnh đang chạy để biết quay lui về đâu.
PREV="$(docker compose "${COMPOSE[@]}" images -q goclaw 2>/dev/null | head -1 || true)"
[ -n "${PREV}" ] && echo "==> Ảnh hiện tại: ${PREV}"

docker compose "${COMPOSE[@]}" pull
docker compose "${COMPOSE[@]}" up -d

echo
echo "==> Xong. Kiểm tra:"
docker compose "${COMPOSE[@]}" ps
echo
echo "Xem log:     docker compose ${COMPOSE[*]} logs -f goclaw"
echo "Quay lui:    ./scripts/fork/deploy.sh <tag-anh-cu>"
