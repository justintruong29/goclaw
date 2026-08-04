#!/usr/bin/env bash
# Deploy một tag ảnh cụ thể cho stack GoClaw nằm cùng thư mục với script này.
#
#   ./deploy-version.sh build-20260804-1601-b5ca462   # ghim bản cụ thể
#   ./deploy-version.sh stable                        # tag do fork retag đặt
#   ./deploy-version.sh latest                        # = deploy-latest.sh
#
# Tự dò project/port/creds từ compose nên chạy được ở mọi stack (goclaw,
# goclaw2, ...) không cần sửa gì. Luôn dump DB trước khi đổi ảnh: ảnh mới chạy
# `goclaw upgrade` lúc khởi động và migration không lùi được.
#
# Biến môi trường: GOCLAW_IMAGE_REPO, GOCLAW_BACKUP_DIR, GOCLAW_SKIP_BACKUP=1
set -euo pipefail

TAG="${1:-}"
if [ -z "$TAG" ]; then
  echo "dùng: $0 <tag>   (vd: build-20260804-1601-b5ca462 | stable | latest)" >&2
  exit 2
fi
if ! printf '%s' "$TAG" | grep -qE '^[A-Za-z0-9_][A-Za-z0-9._-]{0,126}$'; then
  echo "tag không hợp lệ: $TAG" >&2
  exit 2
fi

IMAGE_REPO="${GOCLAW_IMAGE_REPO:-ghcr.io/justintruong29/goclaw}"
SERVICE=goclaw
OVERRIDE=docker-compose.override.yml

cd "$(dirname "$(readlink -f "$0")")"
STACK=$(basename "$PWD")

for f in docker-compose.yml docker-compose.postgres.yml; do
  [ -f "$f" ] || { echo "thiếu $f — đặt script trong thư mục stack" >&2; exit 2; }
done

# Trước khi override tồn tại chỉ dùng được bộ 2 file; sau khi ghi mới dùng đủ 3.
DC_BASE=(docker compose -f docker-compose.yml -f docker-compose.postgres.yml)
DC=("${DC_BASE[@]}" -f "$OVERRIDE")

echo "==> Stack: $STACK   Tag đích: $IMAGE_REPO:$TAG"
"${DC_BASE[@]}" ps || { echo "compose không đọc được stack ở đây" >&2; exit 2; }

# ── Ghim ảnh đang chạy để rollback không bị prune mất ────────────────────────
PREV_CID=$("${DC_BASE[@]}" ps -q "$SERVICE" 2>/dev/null | head -1)
PREV_IMG=""
if [ -n "$PREV_CID" ]; then
  PREV_IMG=$(docker inspect "$PREV_CID" --format '{{.Image}}')
  docker tag "$PREV_IMG" "goclaw-prev:$STACK"
  echo "==> Ảnh hiện tại ghim vào goclaw-prev:$STACK"
fi

# ── Backup DB ────────────────────────────────────────────────────────────────
BACKUP_FILE=""
if [ "${GOCLAW_SKIP_BACKUP:-0}" = "1" ]; then
  echo "==> BỎ QUA backup (GOCLAW_SKIP_BACKUP=1) — chỉ dùng khi vừa backup tay"
else
  BACKUP_DIR="${GOCLAW_BACKUP_DIR:-$HOME/backups}"
  mkdir -p "$BACKUP_DIR"
  PGUSER=$("${DC_BASE[@]}" exec -T postgres printenv POSTGRES_USER | tr -d '\r\n')
  PGDB=$("${DC_BASE[@]}" exec -T postgres printenv POSTGRES_DB | tr -d '\r\n')
  BACKUP_FILE="$BACKUP_DIR/${STACK}_$(date +%F-%H%M).sql"
  echo "==> Dump DB ($PGUSER/$PGDB) -> $BACKUP_FILE"
  "${DC_BASE[@]}" exec -T postgres pg_dump -U "$PGUSER" "$PGDB" > "$BACKUP_FILE"
  [ -s "$BACKUP_FILE" ] || { echo "dump rỗng — dừng" >&2; exit 1; }
  ls -lh "$BACKUP_FILE"
fi

# ── Ghi override (atomically) ────────────────────────────────────────────────
{
  echo 'services:'
  echo "  $SERVICE:"
  echo "    image: $IMAGE_REPO:$TAG"
  if [ "$TAG" = "latest" ]; then
    echo '    pull_policy: always'
  fi
} > "$OVERRIDE.tmp"
mv "$OVERRIDE.tmp" "$OVERRIDE"
echo "==> $OVERRIDE:"
sed 's/^/    /' "$OVERRIDE"

# ── Pull + up ────────────────────────────────────────────────────────────────
"${DC[@]}" pull "$SERVICE"
"${DC[@]}" up -d --no-build "$SERVICE"

# ── Health ───────────────────────────────────────────────────────────────────
HOSTPORT=$("${DC[@]}" port "$SERVICE" 18790 2>/dev/null | tail -1)
[ -n "$HOSTPORT" ] || HOSTPORT="127.0.0.1:18790"
echo "==> Chờ health tại http://$HOSTPORT/health"
OK=0
for _ in $(seq 1 45); do
  if curl -fsS "http://$HOSTPORT/health" >/dev/null 2>&1; then OK=1; break; fi
  sleep 2
done

if [ "$OK" != "1" ]; then
  echo "!! HEALTH CHECK THẤT BẠI — 60 dòng log cuối:" >&2
  "${DC[@]}" logs --tail 60 "$SERVICE" >&2 || true
  echo "" >&2
  echo "Rollback: migration có thể ĐÃ chạy, khi đó phải khôi phục DB TRƯỚC." >&2
  echo "  ${DC[*]} stop $SERVICE" >&2
  if [ -n "$BACKUP_FILE" ]; then
    echo "  ${DC_BASE[*]} exec -T postgres psql -U \$PGUSER -d postgres -c 'DROP DATABASE $PGDB; CREATE DATABASE $PGDB OWNER \$PGUSER;'" >&2
    echo "  ${DC_BASE[*]} exec -T postgres psql -U \$PGUSER -d $PGDB < $BACKUP_FILE" >&2
  fi
  echo "  ./deploy-version.sh <tag-cũ trong deploy.log>   # hoặc dùng ảnh goclaw-prev:$STACK" >&2
  exit 1
fi

# ── Nghiệm thu ───────────────────────────────────────────────────────────────
NEW_IMG=$(docker inspect "$("${DC[@]}" ps -q "$SERVICE" | head -1)" --format '{{.Image}}')
VERSION=$("${DC[@]}" exec -T "$SERVICE" /app/goclaw version 2>/dev/null | tr -d '\r' || echo "?")
echo "==> OK  $VERSION"
echo "==> Image: $NEW_IMG"

"${DC[@]}" logs "$SERVICE" 2>&1 | grep -iE "Schema (current|required)|Applying SQL migrations|Upgrade complete" | tail -5 || true

if [ -n "${PGUSER:-}" ]; then
  "${DC_BASE[@]}" exec -T postgres psql -U "$PGUSER" -d "$PGDB" -c \
    "SELECT 'agents' t,count(*) FROM agents UNION ALL SELECT 'sessions',count(*) FROM sessions UNION ALL SELECT 'vault_docs',count(*) FROM vault_documents UNION ALL SELECT 'skills',count(*) FROM skills;" || true
fi

printf '%s\ttag=%s\timage=%s\tprev=%s\tbackup=%s\n' \
  "$(date -Is)" "$TAG" "$NEW_IMG" "${PREV_IMG:-none}" "${BACKUP_FILE:-skipped}" >> deploy.log
echo "==> Đã ghi deploy.log"
