# MiniUnikey — Bộ gõ tiếng Việt kiểu VNI cho macOS

Bộ gõ tiếng Việt hỗ trợ **kiểu viết VNI** cho Mac (Apple Silicon M1/M2/M3/M4 và cả Intel), macOS 13 Ventura trở lên. Lõi engine port **1:1** từ bộ **UniKey** (ukengine — Phạm Kim Long, nguồn `fcitx5-unikey`) sang Swift và được kiểm chứng với **10.776/10.776 ca testing khớp 100%** engine C++ gốc.

## Xây dựng & chạy

```bash
./scripts/build-app.sh                              # tạo .app
open .build/out/Products/Release/MiniUnikey.app     # chạy
swift test                                          # 10.776 ca parity — 100% khớp
```

Lần đầu chạy, cần cấp quyền **Accessibility**:
`Cài đặt hệ thống → Quyền riêng tư & bảo mật → Accessibility` → thêm MiniUnikey.
Menu trên thanh trạng thái (icon **VN**) sẽ hướng dẫn lại.

## Cách gõ

### Kiểu VNI (mặc định)

| Phím | Công dụng | Ví dụ |
|------|----------------|-------|
| `1` `2` `3` `4` `5` | sắc, huyền, hỏi, ngã, nặng *(gõ cuối từ)* | `sach1` → sách, `sach5` → sạch |
| `0` | xoá dấu thanh *(gõ liền ngay sau từ)* | `sach10` → sach |
| `6` | mũ â ê ô *(gõ ngay sau nguyên âm; hoặc cuối từ khi bật "Gõ tự do")* | `ho6ng` → hông, `tuan62` → tuần |
| `7` | móc ư ơ (gõ sau nguyên âm hoặc sau từ) | `nguoi7` → ngươi, `ngua7` → ngưa |
| `8` | trăng ă | `da8ng` → dăng, `ka8n` → kăn |
| `9` | gạch đ | `d9` → đ |
| gõ lại phím số | huỷ dấu vừa áp dụng | `a6 6` → a |

Ví dụ chuẩn (được kiểm chứng trên engine gốc): `nguoi7 → ngươi` • `ngu7oi5 → ngượi` • `tuan62 → tuần` • `sach1 → sách` • `sach10 → sach` • `ngan62 → ngần`

### Kiểu Telex (chọn trong menu → "Kiểu gõ")

| Phím | Công dụng | Ví dụ (đã kiểm chứng trên engine gốc) |
|------|----------------|-------|
| `s` `f` `r` `x` `j` | sắc, huyền, hỏi, ngã, nặng *(gõ sau từ)* | `hoaif` → hoài, `sachs` → sách, `toof` → tô, `tuanf` → tuần |
| `z` | xoá dấu thanh | `sachsz` → sach |
| `aa` `ee` `oo` | â ê ô *(gõ sau nguyên âm)* | `aan` → ân, `toof` → tô |
| `aw` | ă *(gõ sau nguyên âm)* | `awnh` → ănh |
| `uw` `ow` | ư ơ *(khi có nguyên âm trước)* | `dduwong` → đương |
| `dd` | đ | `dduwong` → đương |
| `w` | móc ư/ơ — không có nguyên âm trước thì giữ nguyên `w` | `cw` → `cư` • `w` một mình → `w` |

> Chữ số giữ nguyên trong Telex (`1..9` gõ literal — muốn gõ dấu dùng chữ s/f/r/x/j).

> Lưu ý chữ số: bộ gõ chỉ biến đổi khi tạo ra tổ hợp hợp lệ (với "Kiểm tra chính tả" bật), vì vậy gõ số bình thường sau dấu cách/ký tự lạ luôn an toàn. Muốn chắc chắn không biến đổi, có thể bấm số 2 lần liền (bấm 2 lần = huỷ trạng thái vừa áp dụng).

## Tuỳ chọn trong menu

- **Tắt/bật gõ tiếng Việt** — chuyển nhanh qua lại VN/EN.
- **Kiểm tra chính tả** — chỉ biến đổi khi từ lo tạo tiếng Việt hợp lệ theo bảng vần UniKey.
- **Kiểu dấu mới** — `oà` thay `òa` (modern style, tuỳ chọn của UniKey).
- **Gõ tự do** — cho phép chỉnh dấu ở nguyên âm trước đó, không chỉ ngay sau nguyên âm.
- **Khởi động cùng macOS** — SMAppService (macOS 13+).

## Kiến trúc

```
Sources/
├── MiniUnikeyEngine/               # engine VNI+Telex (port UniKey) — thư viện Swift thuần
│   ├── VniTables.swift             # bảng vần/ký tự (sinh từ dump C, 1:1)
│   ├── VnTablesHelper.swift        # bảng nguyên âm
│   ├── VnCharsetMaps.swift         # ánh xạ ký tự ↔ lexeme, bảng ngắt từ
│   └── VietKeyboardEngine.swift    # state machine (Tone/Roof/Hook/Dd/TelexW…)
└── MiniUnikey/                     # app macOS
    ├── EventTapController.swift    # CGEventTap: nuốt event, phát lại (backspace|chọn-ký-tự)+text
    ├── AppCoordinator.swift        # menu bar: VNI/Telex, tuỳ chọn — icon VN
    ├── GuideWindow.swift           # cửa sổ hướng dẫn & gõ thử
    ├── Permissions.swift           # quyền Accessibility
    ├── SettingsStore.swift         # UserDefaults (method, spell check, free marking…)
    └── main.swift                  # NSApplication (LSUIElement — không Dock)

Tools/engine-cli/                   # CLI debug engine: swift run engine-cli --telex hoaif

Tests/MiniUnikeyTests/
├── corpus.jsonl                    # 10.776 ca VNI (từ engine C++ tham chiếu)
├── corpus_telex.jsonl              # 3.212 ca Telex/Simple-Telex (fuzz + curated)
└── ParityTests.swift               # kiểm chứng Swift ≡ C++: swift test

scripts/
├── build-app.sh                    # tạo .app (ad-hoc codesign)
├── gen_tables.py                   # sinh bảng từ JSON dump của ukengine
├── gen_corpus.py                   # sinh corpus bằng reference engine C
└── gen_icon.swift                  # vẽ icon app (CoreGraphics)
```

Quy trình kiểm chứng:
1. Biên dịch engine C gốc (`unikey` của `fcitx5-unikey`) thành CLI tham chiếu (`ref_engine`).
2. Dump bảng vần/ký tự 1:1 (kịch bản `unikey_dump.cpp`), sinh Swift table.
3. Port logic processTone/processRoof/processHook/processDd/processBackspace... sang Swift.
4. Sinh corpus (chọn tay + fuzz ngẫu nhiên, 4 tổ hợp cấu hình), chạy parity Swift ↔ C.

## Ranh giới (v1)

- Không hoạt động trong sick input (trường mật khẩu) và một số window cực biệt lập.
- Di chuyển con trỏ bằng chuột/paste không được phát hiện trong v1 — bộ đệm được reset khi bấm phím điều hướng, dấu cách, hoặc ký tự lạ.
- VNI đúng chuẩn engine UniKey (`free marking` + `spell check` + `old style` mặc định như chính phần mềm UniKey Windows).

## Giấy phép

- Thuật toán bảng vần + khung engine lấy từ **UniKey / fcitx5-unikey** (Phạm Kim Long, Fcitx Team) — **LGPL-2.0-or-later**.
- Mọi phần UI/app viết mới bằng Swift — phát hành theo LGPL-2.1 compatible.
