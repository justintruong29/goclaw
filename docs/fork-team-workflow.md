# Quy trình Git cho fork goclaw (làm việc nhóm)

> Bản thống nhất ngày 2026-08-03. Áp dụng cho fork `justintruong29/goclaw` phát triển song song với upstream `nextlevelbuilder/goclaw`.
>
> File này là hợp đồng làm việc chung. Sửa quy trình = sửa file này qua PR, không truyền miệng.

---

## 1. Bối cảnh

- **upstream** = `nextlevelbuilder/goclaw` — repo open source gốc, chạy rất nhanh (~14 bản beta trong 1 tuần).
- **origin** = `justintruong29/goclaw` — fork của team.
- Upstream phát triển trên nhánh **`dev`**, còn `main` là nhánh stable đã đóng băng (theo `CONTRIBUTING.md` của upstream). Mọi PR đóng góp ngược đều nhắm vào `upstream/dev`.
- Patch riêng của team là các bản vá bên trong `internal/` (tenant scope, vault, provider adapter) — không tách ra thư mục `custom/` được. Cách duy nhất giữ chi phí bảo trì thấp là **đẩy PR ngược lên upstream sớm**, để phần khác biệt riêng luôn tiến về 0.

---

## 2. Mô hình nhánh

```text
upstream/dev ──fast-forward──▶ origin/dev        (bản sao thuần, CẤM commit trực tiếp)
                                   │
                    feat/*, fix/*  │ cắt từ origin/dev
                                   ├──▶ PR lên upstream/dev      (đóng góp cộng đồng)
                                   └──▶ PR vào origin/release    (triển khai nội bộ)
                                   │
                                   ▼
                            origin/release  =  dev  +  patch nội bộ
                                   │  merge (KHÔNG BAO GIỜ rebase / force-push)
                                   ▼
                     GHCR image  ──▶  VPS (docker pull)
```

| Nhánh | Vai trò | Ai được ghi | Cách cập nhật |
|---|---|---|---|
| `dev` | Bản sao thuần của `upstream/dev` | không ai commit tay | `git push origin upstream/dev:dev` (chỉ fast-forward) |
| `release` | Nhánh triển khai = `dev` + patch nội bộ | chỉ qua PR + 1 review | `git merge origin/dev` |
| `feat/*`, `fix/*` | Việc mới, cắt từ `dev` | người tạo nhánh | rebase thoải mái (nhánh riêng); giữ lại chừng nào PR upstream còn mở |
| `hotfix/*` | Vá gấp production, cắt từ `release` | người tạo nhánh | PR vào `release` |
| `main` | Bản sao `upstream/main`, không dùng | không ai | để nguyên |

### Vì sao merge chứ không rebase nhánh chung

`--force-with-lease` chỉ chặn việc ghi đè commit người khác **trên remote**; nó không cứu clone local của đồng đội. Rebase + force-push nhánh chung hằng tuần đồng nghĩa cả team phải `reset --hard` hằng tuần và ai đang làm dở thì mất commit. Ngoài ra mỗi lần rebase là mỗi lần **giải lại đúng conflict cũ**, vì commit bị viết lại liên tục. Merge giữ conflict đã giải trong merge commit, lần sau không lặp.

Rebase vẫn dùng bình thường — nhưng chỉ trên nhánh riêng chưa ai pull.

---

## 3. Bốn quy tắc bất di bất dịch

1. **Không commit trực tiếp lên `dev`.** `dev` chỉ được cập nhật bằng fast-forward từ `upstream/dev`. Nếu một lệnh push lên `dev` bị từ chối vì không fast-forward, nghĩa là ai đó đã commit sai chỗ — sửa bằng cách chuyển commit đó sang nhánh `fix/*`, không dùng `--force`.
2. **Không `push --force` / `--force-with-lease` lên `dev`, `release`, `main`.**
3. **Mọi thay đổi vào `release` đều qua PR và phải có CI xanh.** Không push thẳng. Số approve bắt buộc hiện là 0 (xem nhật ký quyết định) — nhưng review vẫn là mặc định về mặt thói quen, chỉ là máy không chặn.
4. **Không push tag của upstream (`v*`) lên fork.** Tag upstream chỉ fetch về local để tham chiếu. Fork chỉ tự đẩy tag `fork-v*`.

---

## 4. Thiết lập lần đầu (mỗi thành viên làm 1 lần)

```bash
git clone https://github.com/justintruong29/goclaw.git
cd goclaw
git remote add upstream https://github.com/nextlevelbuilder/goclaw.git
git fetch upstream --tags
git remote -v
```

Rồi cài bộ script (xem mục 12 để biết vì sao phải cài ra ngoài repo):

```bat
git checkout release
scripts\fork\install.bat
```

Kết quả mong muốn:

```text
origin    https://github.com/justintruong29/goclaw.git (fetch/push)
upstream  https://github.com/nextlevelbuilder/goclaw.git (fetch/push)
```

Chặn lỡ tay push nhầm lên upstream:

```bash
git remote set-url --push upstream DISABLED
```

---

## 5. Luồng làm việc hằng ngày

### Tạo việc mới — luôn cắt từ `dev`

```bash
git fetch origin
git checkout -b fix/ten-mo-ta origin/dev
```

Cắt từ `dev` (không phải `release`) để diff của nhánh luôn sạch với upstream — PR ngược lên upstream dùng lại được ngay, không lẫn commit nội bộ.

### Đặt tên nhánh (theo đúng quy ước upstream)

- `feat/mo-ta` — tính năng mới
- `fix/mo-ta` — sửa lỗi
- `hotfix/mo-ta` — vá gấp production (cắt từ `release`)
- `refactor/mo-ta`, `docs/mo-ta`

### Trước khi mở PR — chạy đúng bộ kiểm tra của upstream

```bash
go build ./...
go build -tags sqliteonly ./...   # bản desktop, bắt buộc phải compile
go vet ./...
go test -race ./...
cd ui/web && pnpm build           # chỉ khi đụng web UI
```

### Commit

Dùng conventional commit, một commit = một ý:

```bash
git commit -m "fix(vault): resolve vault_read paths under tenant workspace root"
```

Không commit log tạm, không commit rồi revert trong cùng nhánh — dọn bằng `git rebase -i` trước khi mở PR (nhánh riêng nên rebase thoải mái).

### Mở PR

```bash
git push -u origin fix/ten-mo-ta
gh pr create --repo justintruong29/goclaw --base release --fill
```

PR phải mô tả **sửa gì, vì sao phải sửa, test thế nào** — phần "vì sao" là phần có giá trị nhất về sau, khi không ai còn nhớ bối cảnh. CI phải xanh mới merge được. Merge bằng **Squash** nếu nhánh nhiều commit lặt vặt, **Merge commit** nếu các commit đã sạch và muốn giữ để PR ngược lên upstream.

---

## 6. Đồng bộ upstream (mỗi tuần, 1 người phụ trách)

### Bước 1 — cập nhật bản sao `dev`

```bash
git fetch upstream
git push origin upstream/dev:dev
```

Không cần checkout. Lệnh này chỉ thành công khi fast-forward — đó chính là chốt an toàn.

### Bước 2 — merge `dev` vào `release`

```bash
git fetch origin
git checkout release
git merge --no-ff origin/dev
```

Nếu conflict: sửa file, `git add`, `git commit`. Conflict đã giải được ghi lại trong merge commit nên lần sync sau không phải giải lại.

### Bước 3 — kiểm tra rồi đẩy

```bash
go build ./... && go build -tags sqliteonly ./... && go vet ./... && go test -race ./...
git push origin release
```

### Xem phần khác biệt riêng của fork bất cứ lúc nào

```bash
git log --oneline origin/dev..origin/release      # commit riêng
git diff --stat origin/dev...origin/release       # file bị đụng
```

Danh sách này càng ngắn càng tốt. Commit nào đã được upstream merge thì lần sync sau nó tự biến mất khỏi danh sách.

---

## 7. Vá lỗi production gấp

```bash
git fetch origin
git checkout -b hotfix/ten-loi origin/release
# sửa lỗi + thêm test
git commit -m "fix(scope): mo ta ngan"
git push -u origin hotfix/ten-loi
gh pr create --base release --fill
```

Merge xong thì phát hành theo mục 8.

**Sau khi vá xong, đưa fix lên upstream:**

```bash
git checkout -b fix/ten-loi origin/dev
git cherry-pick <sha-cua-hotfix>
git push -u origin fix/ten-loi
gh pr create --repo nextlevelbuilder/goclaw --base dev --fill
```

---

## 8. Phát hành và triển khai

### Quy ước phiên bản

Tag của fork bám theo bản `dev` đang mirror, cộng ngày phát hành:

```text
fork-v<tag-upstream-dev>-<YYYYMMDD>

ví dụ:  fork-v3.15.0-beta.188-20260803
```

Nếu phát hành nhiều lần trong cùng một ngày thì thêm hậu tố thứ tự: `...-20260803.2`, `...-20260803.3`.

Tiền tố `fork-` giữ tag của fork tách hẳn khỏi họ tag `v3.15.0-beta.NNN` mà upstream tự sinh, nên không bao giờ đụng nhau và nhìn tag là biết ngay bản đó dựng trên bản upstream nào, ngày nào.

### Tạo bản phát hành

```bash
git fetch upstream --tags
git checkout release && git pull

BASE=$(git describe --tags --abbrev=0 upstream/dev)   # v3.15.0-beta.188
TAG="fork-${BASE}-$(date +%Y%m%d)"

git tag -a "$TAG" -m "release $TAG"
git push origin "$TAG"
```

PowerShell:

```powershell
$BASE = git describe --tags --abbrev=0 upstream/dev
$TAG  = "fork-$BASE-" + (Get-Date -Format "yyyyMMdd")
git tag -a $TAG -m "release $TAG"
git push origin $TAG
```

### Ảnh Docker do CI dựng

Workflow `.github/workflows/fork-release-image.yaml` (file riêng của fork, nằm trên nhánh `release`) đẩy lên GHCR:

| Tag ảnh | Ý nghĩa |
|---|---|
| `ghcr.io/justintruong29/goclaw:release` | con trỏ động, luôn trỏ bản mới nhất của `release` |
| `ghcr.io/justintruong29/goclaw:release-<sha>` | bất biến, theo từng commit |
| `ghcr.io/justintruong29/goclaw:fork-v3.15.0-beta.188-20260803` | bất biến, theo tag phát hành |

### Triển khai lên VPS

VPS **không build từ source** — chỉ pull ảnh CI đã dựng và test, để thứ đang chạy đúng bằng thứ đã kiểm.

`.env` trên VPS ghim tag bất biến:

```dotenv
GOCLAW_IMAGE=ghcr.io/justintruong29/goclaw:fork-v3.15.0-beta.188-20260803
```

Triển khai:

```bash
docker login ghcr.io -u <github-user>    # 1 lần, dùng PAT có scope read:packages
docker compose -f docker-compose.yml \
               -f docker-compose.postgres.yml \
               -f docker-compose.fork.yml pull
docker compose -f docker-compose.yml \
               -f docker-compose.postgres.yml \
               -f docker-compose.fork.yml up -d
```

### Quay lui (rollback)

Sửa `GOCLAW_IMAGE` trong `.env` về tag cũ rồi chạy lại đúng 2 lệnh trên. Không cần đụng git trên VPS, không cần build lại — quay lui trong vài chục giây.

---

## 9. Đóng góp ngược lên upstream

Mặc định: **mọi fix không mang tính riêng tư đều gửi PR lên `upstream/dev`.** Delta riêng càng nhỏ thì sync càng ít conflict, và bản thân việc deploy nội bộ không phải chờ upstream.

```bash
git checkout -b fix/ten-mo-ta origin/dev
# hoặc cherry-pick commit đã có
git push -u origin fix/ten-mo-ta
gh pr create --repo nextlevelbuilder/goclaw --base dev --fill
```

Yêu cầu của upstream cần chú ý khi mở PR (trích `CONTRIBUTING.md` upstream):

- Query phải scope theo `tenant_id`; ghi vào bảng **global** (không có cột `tenant_id`) phải qua `requireMasterScope`, bảng **tenant-scoped** phải qua `requireTenantAdmin` + `WHERE tenant_id = $N`.
- Chuỗi hiển thị cho người dùng phải có đủ 3 locale `en/vi/zh`.
- Phải compile được với `-tags sqliteonly`.
- UI mobile: dùng `h-dvh` không dùng `h-screen`, font input 16px.

PR ngược upstream và việc deploy nội bộ là **hai việc độc lập** — không chờ nhau.

### Cảnh báo: đừng xoá nhánh khi nó còn là head của PR upstream

PR gửi lên upstream trỏ vào nhánh nằm trên fork. Khi merge PR nội bộ vào `release`, nếu tiện tay xoá nhánh thì **PR trên upstream tự động bị đóng**:

```bash
gh pr merge <n> --merge --delete-branch    # SAI khi nhánh đang có PR upstream
gh pr merge <n> --merge                    # đúng: giữ nhánh lại
```

Chỉ xoá nhánh sau khi upstream đã merge hoặc đã từ chối PR. Lỡ xoá rồi thì cứu được: đẩy lại nhánh đúng commit cũ rồi `gh pr reopen <n> --repo nextlevelbuilder/goclaw` — nội dung PR và bình luận vẫn còn nguyên.

---

## 10. GitHub Actions trên fork

Fork kế thừa toàn bộ workflow của upstream. Một số cái phải tắt, nếu không chúng sẽ tự chạy khi ta sync `dev` và gây rác:

| Workflow | Trạng thái trên fork | Lý do |
|---|---|---|
| `Dev CI and Beta Release` (`dev-beta-release.yaml`) | **TẮT** | chạy khi push `dev` → tự sinh tag `v3.15.0-beta.NNN` trên fork, đụng họ tag upstream |
| `fork image` (`fork-image.yaml`) | **TẮT** | dựng `:latest` từ `dev` chưa có patch nội bộ; ta thay bằng workflow riêng trên `release` |
| `Release`, `Release Beta` | **TẮT** | kích hoạt bởi tag `v*`; tắt để tránh rủi ro ai đó lỡ `git push --tags` |
| `Claude Code`, `Claude Code Review` | TẮT (trừ khi cấu hình secret) | thiếu secret sẽ fail đỏ mọi PR |
| `CI` (`ci.yaml`) | giữ nguyên | CI của upstream cho PR vào `main`/`dev` |
| `fork ci` (`fork-ci.yaml`) | **BẬT** (file riêng của fork) | CI cho PR vào `release` |
| `fork release image` (`fork-release-image.yaml`) | **BẬT** (file riêng của fork) | dựng và đẩy ảnh khi push `release` hoặc tag `fork-v*` |

**Nguyên tắc chống conflict:** mọi file riêng của fork phải mang tên riêng (`fork-*.yaml`, `docker-compose.fork.yml`, `docs/fork-team-workflow.md`). Không sửa file có sẵn của upstream chỉ để phục vụ quy trình fork — sửa file upstream là tự chuốc conflict ở mỗi lần sync.

---

## 11. Bảo vệ nhánh (ruleset trên fork)

| Nhánh / tag | Quy tắc |
|---|---|
| `release` | bắt buộc PR, CI xanh (`go` + `web`); 0 approve bắt buộc; cấm force-push; cấm xoá |
| `dev` | cấm force-push; cấm xoá; chỉ người phụ trách sync được push |
| `main` | cấm force-push; cấm xoá |
| tag `fork-v*` | cấm xoá, cấm sửa |

---

## 12. Script có sẵn

### Cài một lần (bắt buộc, không phải tuỳ chọn)

```bat
cd <thư-mục-repo>
scripts\fork\install.bat
```

Lệnh này chép bộ `.bat` ra `..\goclaw-tools` (cạnh repo) và ghi lại đường dẫn repo để script tự tìm. Thêm vào PATH cho gọn:

```bat
setx PATH "%PATH%;D:\goclaw-core\goclaw-tools"
```

**Vì sao phải cài ra ngoài repo:** nhánh feature cắt từ `dev`, mà `dev` là bản sao thuần của upstream nên **không bao giờ chứa `scripts/fork/`**. Chạy script từ trong repo thì lệnh `git checkout` sẽ xoá đúng file `.bat` đang chạy giữa chừng và cmd đứt ngang; tệ hơn, khi đang ở nhánh feature thì trong repo không có script nào cả, kể cả `check.bat`. Bản cài ở ngoài thì đổi nhánh kiểu gì cũng còn. `new.bat` tự chặn nếu phát hiện đang chạy bản nằm trong repo.

Chạy lại `install.bat` sau mỗi lần script được cập nhật trên `release`.

### Danh sách

| Script | Việc | Thay cho |
|---|---|---|
| `sync.bat` | Đồng bộ upstream: fetch → mirror `dev` → merge vào `release` | mục 6 |
| `new.bat <loại>/<mô-tả>` | Tạo nhánh việc mới trên nền `origin/dev` | mục 5 |
| `hotfix.bat <mô-tả>` | Tạo nhánh vá gấp trên nền `origin/release` | mục 7 |
| `check.bat [web]` | Chạy đủ bộ kiểm tra trước khi mở PR | mục 5 |
| `release.bat` | Tự tính tag `fork-v...-<ngày>` rồi tạo và đẩy | mục 8 |
| `delta.bat` | Xem patch riêng của fork + kiểm tra `dev` có lệch upstream không | mục 6 |
| `scripts/fork/deploy.sh` | Pull ảnh và triển khai trên VPS, cũng dùng để quay lui | mục 8 |

`deploy.sh` chạy trên VPS, mà VPS đứng yên trên nhánh `release` nên nó luôn có sẵn trong repo — không cần cài ra ngoài.

Các script đều tự chặn thao tác sai: `sync.bat` từ chối chạy khi cây làm việc bẩn và báo rõ phải làm gì nếu push `dev` không fast-forward; `new.bat` chỉ nhận tiền tố `feat/ fix/ refactor/ docs/`; `check.bat` báo luôn phiên bản Go cần cài nếu thiếu; `release.bat` chỉ chạy trên nhánh `release` và bắt buộc local phải khớp `origin/release` trước khi tạo tag.

## 13. Bảng tra nhanh

```bash
# Sync upstream (hàng tuần)
git fetch upstream
git push origin upstream/dev:dev
git checkout release && git merge --no-ff origin/dev && git push origin release

# Việc mới
git checkout -b fix/abc origin/dev

# Vá gấp production
git checkout -b hotfix/abc origin/release

# Xem delta riêng của fork
git log --oneline origin/dev..origin/release

# Phát hành
git tag -a fork-v3.15.0-beta.188-20260803 -m "release"
git push origin fork-v3.15.0-beta.188-20260803

# Triển khai / quay lui trên VPS  (sửa GOCLAW_IMAGE trong .env rồi:)
docker compose -f docker-compose.yml -f docker-compose.postgres.yml -f docker-compose.fork.yml pull
docker compose -f docker-compose.yml -f docker-compose.postgres.yml -f docker-compose.fork.yml up -d
```

---

## 14. Xử lý tình huống hay gặp

**Push lên `dev` bị từ chối (non-fast-forward)** — có commit lạ trên `dev`. Chuyển nó sang nhánh riêng rồi trả `dev` về đúng bản sao:

```bash
git checkout -b fix/cuu-commit origin/dev   # giữ lại việc đang làm
# báo người phụ trách repo reset dev về upstream/dev
```

Không tự ý `--force`.

**Merge `dev` vào `release` bị conflict ở file mình từng vá** — dấu hiệu upstream đã sửa cùng chỗ. Kiểm tra xem bản vá của mình còn cần không:

```bash
git log --oneline origin/dev -- <đường/dẫn/file>
```

Nếu upstream đã sửa rồi thì lấy bản upstream (`git checkout --theirs`) và bỏ patch riêng — delta của fork ngắn đi một dòng.

**Nhánh riêng đã cũ so với `dev`** — rebase (nhánh riêng, được phép):

```bash
git fetch origin && git rebase origin/dev
```

**Lỡ commit thẳng lên `release`** — chưa push thì chuyển sang nhánh mới:

```bash
git branch fix/abc && git reset --hard origin/release && git checkout fix/abc
```

---

## 15. Nhật ký quyết định

| Ngày | Quyết định | Lý do |
|---|---|---|
| 2026-08-03 | Mô hình A: `dev` là bản sao thuần + `release` là nhánh triển khai, sync bằng merge | không force-push nhánh chung; delta riêng liệt kê được bằng một lệnh; PR ngược upstream sạch |
| 2026-08-03 | Triển khai bằng ảnh GHCR dựng từ `release`, VPS chỉ `docker pull` | thứ chạy đúng bằng thứ CI đã test; quay lui bằng đổi tag ảnh |
| 2026-08-03 | Tag `fork-v<tag-upstream-dev>-<YYYYMMDD>` | tách khỏi họ tag `v*-beta.NNN` của upstream; nhìn tag biết ngay nền upstream và ngày |
| 2026-08-03 | Bắt buộc PR + CI xanh vào `release`; PR ngược upstream mọi fix dùng chung | tạo dấu vết review (fork trước đó chưa có PR nào) và giữ delta riêng tiến về 0 |
| 2026-08-03 | Hạ số approve bắt buộc từ 1 xuống **0**, giữ nguyên yêu cầu CI xanh | team 2 người và GitHub không cho tác giả tự approve PR của mình, nên yêu cầu 1 approve khiến chủ repo bị khoá cứng mỗi khi người kia bận. Đổi lại: máy không còn chặn code chưa ai xem — review trở thành thoả thuận giữa người với nhau, không phải rào chắn kỹ thuật |
| 2026-08-03 | File riêng của fork luôn mang tên `fork-*` | tránh conflict với upstream ở mỗi lần sync |
