//
//  Permissions.swift
//  MiniUnikey
//
//  Quyền Accessibility (AX) để cài event tap toàn cục.
//
import AppKit

enum Permissions {
    static func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Nhờ hệ thống tự hiện hộp thoại "MiniUnikey muốn kiểm soát máy tính của bạn"
    /// (gồm nút mở Cài đặt hệ thống). Đây là luồng chuẩn & đỡ lắt nhắt nhất.
    static func requestAccessibilityPrompt() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Poll cái quyền AX vô thời hạn (2 giây/lần), gọi `onGranted` đúng một lần
    /// khi người dùng gạt quyền xong. Log heartbeat để biết poll còn sống.
    static func watchUntilGranted(onGranted: @escaping () -> Void) {
        var beats = 0
        let timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { t in
            beats += 1
            if isAccessibilityGranted() {
                t.invalidate()
                onGranted()
            } else if beats % 10 == 0 {
                EventTapController.diagLog("đang chờ quyền Accessibility... (poll còn sống, đợt \(beats))")
            }
        }
        timer.fire()
    }
}
