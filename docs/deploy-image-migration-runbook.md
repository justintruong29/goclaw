# Runbook: chuyển stack GoClaw sang deploy bằng image dựng sẵn

Chuyển một stack Docker Compose đang chạy (build tại chỗ hoặc pull ảnh upstream) sang chạy **ảnh dựng sẵn từ CI của fork**, giữ nguyên toàn bộ data Postgres, volume, port và env.

Đã chạy thật trên stack `goclaw2` (tenant binhdien) ngày 2026-08-04: `nextlevelbuilder:latest` → `ghcr.io/justintruong29/goclaw:build-20260804-1601-b5ca462`, schema v93 → v96, không mất data.

Nền tảng: pipeline ảnh ở `.github/workflows/fork-release-image.yaml` + `fork-retag.yaml` (nhánh `release` của fork). Deploy kiểu binary + systemd trên zuey là chuyện khác, xem `deployment-guide.md`.

---

## Nguyên tắc

**Chỉ đổi đúng một dòng `image:`.** Port, volume, env, compose gốc không đụng tới. Data nằm ở named volume, không nằm trong image, nên đổi image không thể làm mất data. Cái duy nhất một chiều là **migration schema** — xử lý bằng backup ở Phase 1.

---

## Phase 0 — Thu thập (chỉ đọc)

```bash
cd ~/projects/goclaw          # vd goclaw2
```

```bash
# tên project + đúng bộ file compose đang dùng (đừng đoán)
docker inspect goclaw-goclaw-1 --format '{{index .Config.Labels "com.docker.compose.project"}}'
docker inspect goclaw-goclaw-1 --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}'

# image đang chạy — ĐÂY LÀ ĐƯỜNG LÙI
docker inspect goclaw-goclaw-1 --format '{{.Config.Image}}'

# volume + port
docker inspect goclaw-goclaw-1 --format '{{range .Mounts}}{{.Name}} -> {{.Destination}}{{"\n"}}{{end}}'
docker port goclaw-goclaw-1; docker port goclaw-postgres-1

# bản đang chạy (container cũ còn sống mới lấy được)
docker exec goclaw-goclaw-1 /app/goclaw version
```

Đặt biến, thay bộ `-f` bằng đúng kết quả ở trên. **Chưa có `-f docker-compose.override.yml`** — file đó Phase 2 mới tạo; thêm sớm là mọi lệnh compose chết với `no such file or directory`:

```bash
DC="docker compose -f docker-compose.yml -f docker-compose.postgres.yml"
```

Thử ngay để chắc bộ `-f` đúng, trước khi động vào backup:

```bash
$DC ps
```

Ghi lại số liệu để đối chiếu:

```bash
docker exec -i goclaw-postgres-1 psql -U goclaw -d goclaw -c "SELECT 'agents' t,count(*) FROM agents UNION ALL SELECT 'sessions',count(*) FROM sessions UNION ALL SELECT 'vault_docs',count(*) FROM vault_documents UNION ALL SELECT 'skills',count(*) FROM skills;"
```

---

## Phase 1 — Backup 3 lớp

**Lớp 1 — dump SQL.** Bắt buộc. Ảnh mới tự chạy `goclaw upgrade` lúc khởi động; migration không lùi được.

```bash
mkdir -p ~/backups
docker exec goclaw-postgres-1 pg_dump -U goclaw goclaw > ~/backups/goclaw_$(date +%F-%H%M).sql
ls -lh ~/backups/
```

**Lớp 2 — ghim image cũ** để không bị prune mất đường lùi. Dùng đúng chuỗi image ở Phase 0:

```bash
docker tag <image-cũ> <image-cũ-không-tag>:pre-image-switch
docker images | grep goclaw
```

Stack build tại chỗ thì image cũ tên `goclaw-goclaw:latest`. Stack pull sẵn thì là `ghcr.io/nextlevelbuilder/goclaw:latest`.

**Lớp 3 — bản sao nguội volume Postgres.** Dừng DB vài giây. Chạy **từng lệnh một** và xác nhận `$DC stop` thành công trước khi `tar` — Postgres còn chạy thì tar ra bản sao nóng, có thể rách giữa chừng và vô dụng lúc cần:

```bash
$DC stop
```
```bash
docker ps --format '{{.Names}}\t{{.Status}}'      # phải KHÔNG còn container của stack
```
```bash
docker run --rm -v goclaw_postgres-data:/v -v ~/backups:/b alpine tar czf /b/goclaw-pgdata-$(date +%F).tgz -C /v .
```
```bash
$DC start
```

```bash
cp .env ~/backups/goclaw.env.bak
```

---

## Phase 2 — Đổi image

Ghi file override bằng **3 lệnh `echo` riêng lẻ**, không heredoc, không `printf` dài (xem "Bẫy đã gặp" #2):

```bash
echo 'services:' > docker-compose.override.yml
```
```bash
echo '  goclaw:' >> docker-compose.override.yml
```
```bash
echo '    image: ghcr.io/justintruong29/goclaw:build-YYYYMMDD-HHMM-xxxxxxx' >> docker-compose.override.yml
```

Ghim tag có ngày cho lần chuyển đầu, không dùng `:latest` — để bản đang test không nhảy khi bạn build bản khác.

```bash
cat -A docker-compose.override.yml     # đúng 3 dòng, mỗi dòng kết bằng $, không dòng trống
```

Giờ mới thêm override vào `$DC` — từ đây mọi lệnh compose ở thư mục này phải có đủ cờ:

```bash
DC="docker compose -f docker-compose.yml -f docker-compose.postgres.yml -f docker-compose.override.yml"
```

Kiểm compose đọc đúng — **so cả 3: image mới, port cũ, volume cũ**:

```bash
$DC config | grep -E "image:|published"
$DC config | grep "name: goclaw_"
```

Chạy:

```bash
$DC pull goclaw
$DC up -d --no-build goclaw
docker logs goclaw-goclaw-1 --tail 80
```

> Không chạy `$DC up -d` trống (đụng cả service postgres). Không bao giờ `down -v`.

---

## Phase 3 — Nghiệm thu

```bash
docker logs goclaw-goclaw-1 2>&1 | head -40      # phần "Running database upgrade..."
curl -fsS http://127.0.0.1:<port>/health && echo
docker exec goclaw-goclaw-1 /app/goclaw version
```

Trong log phải thấy migration kết thúc gọn và `schema check passed current=N required=N`:

```
Applying SQL migrations... OK (v93 -> v96)
Running data hooks... none pending
Upgrade complete.
```

Số liệu so với Phase 0 (hoặc so với dump):

```bash
docker exec -i goclaw-postgres-1 psql -U goclaw -d goclaw -c "SELECT 'agents' t,count(*) FROM agents UNION ALL SELECT 'sessions',count(*) FROM sessions UNION ALL SELECT 'vault_docs',count(*) FROM vault_documents UNION ALL SELECT 'skills',count(*) FROM skills;"
```
```bash
awk '$1=="COPY"&&$2=="public.vault_documents"{f=1;next} f&&$0=="\\."{exit} f{c++} END{print c+0}' ~/backups/<file>.sql
```

Test hành vi thật trên bot — 3 câu:

1. **Chat thường** → có trả lời, log không ERROR provider.
2. **Câu chỉ trả lời được nếu đọc tài liệu vault** → test kép `vault_search` (embedding) + `vault_read` (đường dẫn tenant).
3. **Kích 1 skill nội bộ của agent** → test patch skill-visibility (fork-only).

Xuất xứ patch **không kiểm bằng `strings`** — kiểm ở tầng git (xem "Bẫy đã gặp" #3):

```bash
git branch -r --contains <sha-ảnh> | grep fork/release
git merge-base --is-ancestor 8bf10520 fork/release && echo OK    # skill-visibility
```

---

## Phase 4 — Rollback

**Nếu migration CHƯA chạy** (app chết trước khi upgrade xong) — chỉ đổi image lại:

```bash
$DC stop goclaw
# sửa dòng image trong override về <image>:pre-image-switch
$DC up -d --no-build goclaw
```

**Nếu migration ĐÃ chạy** (thường là vậy) — bắt buộc khôi phục DB trước. Binary cũ gặp schema mới hơn sẽ **từ chối khởi động**, không phải crash ngẫu nhiên:

```go
// internal/upgrade/checker.go:56-62 — Compatible chỉ khi version == RequiredSchemaVersion
// cmd/upgrade.go:229-231 — CurrentVersion > RequiredVersion → chặn khởi động
```

```bash
$DC stop goclaw
docker exec -i goclaw-postgres-1 psql -U goclaw -d postgres -c "DROP DATABASE goclaw; CREATE DATABASE goclaw OWNER goclaw;"
docker exec -i goclaw-postgres-1 psql -U goclaw -d goclaw < ~/backups/goclaw_<ngày>.sql
# sửa dòng image trong override về <image>:pre-image-switch
$DC up -d --no-build goclaw
```

**Nếu cả dump cũng hỏng** — khôi phục volume nguội:

```bash
$DC down                      # KHÔNG có -v
docker run --rm -v goclaw_postgres-data:/v -v ~/backups:/b alpine sh -c 'rm -rf /v/* && tar xzf /b/goclaw-pgdata-<ngày>.tgz -C /v'
$DC up -d
```

> Dump chụp tại thời điểm Phase 1. Mỗi tin nhắn bot xử lý sau đó là dữ liệu sẽ mất nếu rollback. Test dứt điểm trong ngày, đừng để lửng lơ.

---

## Phase 5 — Sau khi ổn

1. Đổi override sang `:latest` nếu muốn deploy nhanh (`pull && up -d`), hoặc giữ tag ghim nếu ưu tiên an toàn.
2. Ghi digest mỗi lần deploy: `docker inspect goclaw-goclaw-1 --format '{{.Image}}' >> deploy.log`
3. Deploy lần sau: Actions → `fork release image` (move_latest ✔) → trên VPS `$DC pull goclaw && $DC up -d --no-build goclaw`.
4. Chỉ khi chạy ổn nhiều ngày mới tính dọn source ra khỏi thư mục deploy. Đổi thư mục = đổi project name = đổi tên volume → phải set `COMPOSE_PROJECT_NAME=goclaw` trong `.env`, quên là DB trông như rỗng.

---

## Bẫy đã gặp

**1. `-f` tường minh thì compose KHÔNG tự nạp `docker-compose.override.yml`.**
Auto-load chỉ xảy ra khi chạy `docker compose` không có cờ `-f`. Có `-f` mà thiếu override → compose im lặng dùng compose gốc, `$DC config` vẫn ra image cũ. Phải thêm `-f docker-compose.override.yml` vào **mọi** lệnh compose ở thư mục đó.

**2. Heredoc và `printf` dài bị terminal cắt.**
Paste `cat > file <<'EOF'` nhiều dòng dính bracketed-paste (`^[[200~`); `printf` một dòng dài bị wrap thành 2 dòng → YAML sai indent. Dùng nhiều lệnh `echo` ngắn, rồi `cat -A` kiểm.

**3. Grep chuỗi trong binary để xác minh patch là không đáng tin.**
`strings /app/goclaw | grep "tenant workspace root"` ra 0 mà build vẫn đúng — vì trong bản upstream đã merge, chuỗi đó là **comment** (`internal/tools/vault_read.go:155`), comment không vào binary. Build với `-s -w` cũng xoá symbol table (tên hàm còn trong pclntab nhưng đừng dựa vào). Xác minh ở tầng git: tag ảnh ⇄ commit ⇄ nhánh.

**4. Migration là cửa một chiều.**
Nhảy từ ảnh release ổn định của upstream sang dòng dev gần như chắc chắn kéo theo migration. Backup Phase 1 là bắt buộc, không phải tuỳ chọn.

**5. Volume mount path của Postgres.**
Compose của repo mount `postgres-data:/var/lib/postgresql` (cả thư mục). Đừng đổi thành `/var/lib/postgresql/data` — Postgres sẽ thấy dir rỗng và init DB mới.

**6. `ENABLE_FULL_SKILLS=false` trong ảnh CI.**
Gói cài lúc chạy vẫn còn (entrypoint đọc lại `/app/data/.runtime/apk-packages` trong volume), nhưng skill cần thư viện Python nặng thì nên kiểm lại sau khi đổi.
