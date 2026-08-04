#!/usr/bin/env bash
# Deploy bản mới nhất (:latest) cho stack GoClaw nằm cùng thư mục.
#
# :latest chỉ nhảy khi workflow `fork release image` chạy với move_latest = true.
# Dựng ảnh mà không tích ô đó thì chạy script này sẽ không thấy gì mới — đúng
# chủ ý: dựng thử chưa phát hành.
#
# Toàn bộ việc thật nằm ở deploy-version.sh (backup, ghim ảnh cũ, health, log).
set -euo pipefail
exec "$(dirname "$(readlink -f "$0")")/deploy-version.sh" latest
