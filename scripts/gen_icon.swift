// gen_icon.swift — vẽ icon 1024x1024 cho MiniUnikey bằng AppKit/CoreGraphics
// Chạy: swift scripts/gen_icon.swift  (xuất assets/icon-1024.png)
import AppKit

let size = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: size, height: size)

NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx

let S = CGFloat(size)

// 1. Hình vuông bo tròn kiểu macOS (squircle ~22.5%)
let radius = S * 0.225
let squircle = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: S, height: S),
                            xRadius: radius, yRadius: radius)
squircle.addClip()

// 2. Nền gradient tím → xanh dương
let colors = [
    NSColor(calibratedRed: 0.30, green: 0.27, blue: 0.90, alpha: 1).cgColor,   // #4C45E6
    NSColor(calibratedRed: 0.10, green: 0.20, blue: 0.62, alpha: 1).cgColor,   // #1A339E
] as CFArray
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
let cg = ctx.cgContext
cg.drawLinearGradient(grad,
                      start: CGPoint(x: 0, y: S),          // trên
                      end: CGPoint(x: S, y: 0),            // dưới
                      options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

// 3. Ánh sáng mềm ở góc trên trái
cg.setBlendMode(.softLight)
let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [NSColor(white: 1, alpha: 0.55).cgColor,
                               NSColor(white: 1, alpha: 0.0).cgColor] as CFArray,
                      locations: [0, 1])!
cg.drawRadialGradient(glow, startCenter: CGPoint(x: S * 0.25, y: S * 0.85), startRadius: 0,
                      endCenter: CGPoint(x: S * 0.25, y: S * 0.85), endRadius: S * 0.75,
                      options: [])
cg.setBlendMode(.normal)

// 4. Dải "phím bàn phím" trang trí ở dưới (phím(keycaps) mờ)
let keyAlpha: CGFloat = 0.10
let keyFont = NSFont.monospacedSystemFont(ofSize: 92, weight: .bold)
let pluckKeys = ["a", "ă", "â", "ê", "ô", "ư", "ơ", "đ"]
var kx = S * 0.06
for k in pluckKeys {
    let suffix = NSAttributedString(string: k, attributes: [
        .font: keyFont,
        .foregroundColor: NSColor(white: 1, alpha: keyAlpha),
    ])
    suffix.draw(at: NSPoint(x: kx, y: S * 0.055))
    kx += 105 + 8
}

// 5. Chữ "VN" trắng đậm giữa icon
let bigFont = NSFont.systemFont(ofSize: 430, weight: .heavy)
let attrs: [NSAttributedString.Key: Any] = [
    .font: bigFont,
    .foregroundColor: NSColor.white,
]
let sV = NSAttributedString(string: "V", attributes: attrs)
let sN = NSAttributedString(string: "N", attributes: attrs)
let wV = sV.size().width, wN = sN.size().width
let gap = -S * 0.010   // chữ heavy tự có giãn
let total = wV + gap + wN
let xV = (S - total) / 2
let xN = xV + wV + gap
let capH = bigFont.capHeight
let yText = (S - capH) / 2 - S * 0.02

// bóng đổ nhẹ
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -10), blur: 30,
             color: NSColor(white: 0, alpha: 0.25).cgColor)
sV.draw(at: NSPoint(x: xV, y: yText))
sN.draw(at: NSPoint(x: xN, y: yText))
cg.restoreGState()

// 6. Dấu sắc (hoa thị) trên chữ N — nét nghiêng sắc kiểu tiếng Việt
let nCenter = xN + wN / 2
let accentBase = yText + capH + S * 0.012
let accentPath = NSBezierPath()
let thick = S * 0.052
accentPath.move(to: NSPoint(x: nCenter - S * 0.075, y: accentBase + thick * 0.35))
accentPath.line(to: NSPoint(x: nCenter + S * 0.045, y: accentBase + thick * 2.1))
accentPath.line(to: NSPoint(x: nCenter + S * 0.045 - thick, y: accentBase + thick * 2.35))
accentPath.line(to: NSPoint(x: nCenter - S * 0.075 - thick * 0.55, y: accentBase - thick * 0.15))
accentPath.close()
NSColor.systemYellow.setFill()
accentPath.fill()
// viền nhẹ cho nổi
accentPath.lineWidth = 1
NSColor(white: 1, alpha: 0.6).setStroke()

// ALSO: điểm nhỏ dấu móc ngược ("huyền") gợi ý thêm phía sau V? — giữ gọn, bỏ qua.

NSGraphicsContext.restoreGraphicsState()

// 7. Xuất PNG
if let png = rep.representation(using: .png, properties: [:]) {
    let out = URL(fileURLWithPath: "assets/icon-1024.png")
    try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! png.write(to: out)
    print("✅ Đã vẽ \(out.path)")
}
