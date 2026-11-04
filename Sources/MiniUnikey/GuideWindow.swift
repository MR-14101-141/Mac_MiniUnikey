//
//  GuideWindow.swift
//  MiniUnikey
//
//  Cửa sổ "Hướng dẫn & gõ thử" — liệt kê quy tắc kiểu VNI và các bước cấp quyền.
//
import AppKit

final class GuideWindow: NSWindow {
    init() {
        let view = GuideView()
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        isReleasedWhenClosed = false
        title = "MiniUnikey — Hướng dẫn & gõ thử"
        contentView = view
        center()
    }
}

final class GuideView: NSView {
    private let scrollView = NSScrollView()
    private let textView = NSTextView(frame: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        textView.isEditable = false
        textView.isRichText = true
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 18, height: 16)

        scrollView.documentView = textView
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        if let container = textView.textContainer {
            container.widthTracksTextView = true
        }

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        configure(permissionLine: "", highlight: false)
    }

    private func append(_ text: String, font: NSFont = .systemFont(ofSize: 13), color: NSColor = .labelColor) {
        let attr = NSMutableAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: color])
        textView.textStorage?.append(attr)
    }

    func configure(permissionLine: String, highlight: Bool) {
        guard let storage = textView.textStorage else { return }
        storage.beginEditing()
        storage.setAttributedString(NSAttributedString(string: ""))

        append("MiniUnikey — Bộ gõ tiếng Việt kiểu VNI cho macOS\n", font: .systemFont(ofSize: 17, weight: .bold), color: .controlAccentColor)
        append("Chạy trên Apple Silicon (M1/M2/M3/M4) và Intel — macOS 13 trở lên.\n\n")

        if !permissionLine.isEmpty {
            append(permissionLine + "\n\n", font: .systemFont(ofSize: 14, weight: .semibold),
                   color: highlight ? .systemRed : .systemGreen)
        }

        let p1 = NSAttributedString(
            string: "CÁCH CÀI QUYỀN (lần đầu)\n",
            attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .bold), .foregroundColor: NSColor.labelColor])
        storage.append(p1)
        append("1. Mở menu MiniUnikey trên thanh menu → “Hướng dẫn & gõ thử…” (cửa sổ này).\n")
        append("2. Cài đặt hệ thống (System Settings) → Quyền riêng tư & bảo mật (Privacy & Security).\n")
        append("3. Kéo xuống phần Accessibility → bật (dùng nút +) để thêm MiniUnikey vào danh sách.\n")
        append("4. Thoát và mở lại app nếu chưa thấy hoạt động ngay.\n\n")

        let p2 = NSAttributedString(
            string: "CÁCH GÕ — tuỳ “Kiểu gõ” chọn trong menu (VNI mặc định)\n",
            attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .bold), .foregroundColor: NSColor.labelColor])
        storage.append(p2)

        append("[Kiểu VNI — mặc định]\n")
        append("• Dấu thanh — gõ SỐ ngay sau từ (hoặc ngay sau nguyên âm):\n")
        append("      a1 → á      a2 → à      a3 → ả      a4 → ã      a5 → ạ\n")
        append("      oa2 → òa (hoặc “hoà” nếu bật “Kiểu dấu mới”)\n")
        append("      tie6ng → tiếng      ngan62 → ngần      tuan62 → tuần     khan8 → khăn     d9 → đ\n")
        append("• Dấu hình dạng — gõ SỐ ngay sau nguyên âm: a6 → â   e6 → ê   o6 → ô   u7 → ư   o7 → ơ   a8 → ă   d9 → đ\n\n")

        append("[Kiểu Telex]\n")
        append("• Dấu thanh — gõ CHỮ ngay sau từ:  s → sắc   f → huyền   r → hỏi   x → ngã   j → nặng   z → xoá dấu\n")
        append("      hoaif → hoài      sachs → sách      nganx → ngã?? — đúng cặp “-an-ngã” là “nganx”\n")
        append("• Dấu hình dạng — gõ CHỮ sau nguyên âm: aa → â   ee → ê   oo → ô   aw → ă   aa?? — chuẩn: aa â, ee ê, oo ô, aw ă, dd đ, uw ư, ow ơ\n")
        append("      aan → ân      awnh → ănh      dduwong → đương\n")
        append("• w = móc ư/ơ khi có nguyên âm trước (đứng một mình giữ nguyên chữ w).\n\n")

        let p3 = NSAttributedString(
            string: "CÚ PHỮM SỰ KIỆN ĐẶC BIỆT\n",
            attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .bold), .foregroundColor: NSColor.labelColor])
        storage.append(p3)
        append("• Số 0 gõ LIỀN sau từ đã có dấu: xoá dấu thanh (sach10 → sach).\n")
        append("• Bấm lại cùng một số: huỷ dấu vừa áp dụng (a66 → a; ca11 → ca).\n")
        append("• Muốn gõ chữ số nghĩa: bấm số sau dấu cách/háy chữ đợi — hoặc bấm 2 lần.\n")
        append("• Phím tắt Cmd/Option/Ctrl, điều hướng, chuột… sẽ tự làm mới bộ đệm từ.\n\n")

        let p4 = NSAttributedString(
            string: "GÕ THỬ NGAY TRONG Ô NÀY (hộp nhập)!\n",
            attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .bold), .foregroundColor: NSColor.labelColor])
        storage.append(p4)
        append("Gõ ngay vào ô này để thử:  tie6ng → tiếng,  nguoi7 → ngươi,  tuan62 → tuần…\n")
        append("Thử cả:  chao4 buoi4  từng chữ; muốn gõ số thật hãy bấm số 2 lần liền.\n\n")

        append("— MiniUnikey dựa trên thuật toán engine UniKey (Phạm Kim Long, LGPL; nguồn: fcitx5-unikey).\n", font: .systemFont(ofSize: 11), color: .secondaryLabelColor)

        storage.endEditing()
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
    }
}
