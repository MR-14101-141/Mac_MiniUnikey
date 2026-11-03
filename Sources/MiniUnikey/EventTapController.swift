//
//  EventTapController.swift
//  MiniUnikey
//
//  Cài đặt CGEventTap toàn cục để gõ tiếng Việt kiểu VNI.
//  Kỹ thuật (giống OpenKey/EVKey): tra ký tự mà app sẽ nhận từ keyDown,
//  đưa vào engine; nếu engine yêu cầu biến đổi — nuốt phím gốc, gửi lại
//  N lần backspace rồi chèn chuỗi ký tự mới (NFC).
//  Event tự post được đánh dấu qua .eventSourceUserData để callback tự bỏ qua.
//
import AppKit
import Carbon.HIToolbox

final class EventTapController {
    static let shared = EventTapController()

    private static let eventMarkerValue: Int64 = 0x4D49_4E55  // "MINU"

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var eventSource: CGEventSource?
    private var retryCount = 0

    private let engine = VietKeyboardEngine()

    /// Trạng thái để menu hiển thị
    private(set) var isWaitingPermission = true

    private init() {
        applySettings()
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged),
                                               name: SettingsStore.changedNotification, object: nil)
    }

    @objc private func settingsChanged() { applySettings() }

    private func applySettings() {
        let store = SettingsStore.shared
        engine.options.vietKey = store.vietnameseOn
        engine.options.spellCheckEnabled = store.spellCheckEnabled
        engine.options.freeMarking = store.freeMarkingEnabled
        engine.options.modernStyle = store.modernStyleEnabled
        engine.reset()
    }

    // MARK: - xử lý gỡ lỗi ra file

    static func diagLog(_ message: String) {
        let line = "[\(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))] \(message)\n"
        if let data = line.data(using: .utf8) {
            let url = diagLogURL()
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: data)
            } else {
                if let handle = try? FileHandle(forWritingTo: url) {
                    _ = try? handle.seekToEnd()
                    handle.write(data)
                    try? handle.close()
                }
            }
        }
    }

    static func diagLogURL() -> URL {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("MiniUnikey-diag.log")
    }

    // MARK: - Bật/tắt tap

    func start() {
        isWaitingPermission = false
        guard tap == nil else { return }

        if !Permissions.isAccessibilityGranted() {
            isWaitingPermission = true
            EventTapController.diagLog("chần quyền Accessibility — nhờ hệ thống hiện hộp thoại")
            NotificationCenter.default.post(name: .miniUnikeyStatusChanged, object: nil)
            Permissions.requestAccessibilityPrompt()
            Permissions.watchUntilGranted { [weak self] in
                DispatchQueue.main.async {
                    EventTapController.diagLog("quyền Accessibility ĐÃ ĐƯỢC CẤP ✅")
                    self?.retryCount = 0
                    self?.startTapNow()
                }
            }
            return
        }
        startTapNow()
    }

    private func startTapNow() {
        isWaitingPermission = false
        guard tap == nil else { return }

        guard let stateID = CGEventSourceStateID(rawValue: -1) /* kCGEventSourceStatePrivate */,
              let source = CGEventSource(stateID: stateID) else {
            EventTapController.diagLog("❌ không tạo được CGEventSource")
            return
        }
        eventSource = source

        let keyDownMask = CGEventMask(1 << UInt64(CGEventType.keyDown.rawValue))
        let leftUpMask = CGEventMask(1 << UInt64(CGEventType.leftMouseUp.rawValue))
        let rightUpMask = CGEventMask(1 << UInt64(CGEventType.rightMouseUp.rawValue))
        let interest: CGEventMask = keyDownMask | leftUpMask | rightUpMask

        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,          // phải là 'default' để được nuốt/thay event
            eventsOfInterest: interest,
            callback: { _, type, evt, _ in
                EventTapController.shared.handle(type: type, event: evt)
            },
            userInfo: nil) else {
            retryCount += 1
            EventTapController.diagLog("❌ tapCreate thất bại (lần \(retryCount)) — mô phỏng thử lại 3 giây nữa")
            NotificationCenter.default.post(name: .miniUnikeyStatusChanged, object: nil)
            if retryCount <= 10 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    self?.startTapNow()
                }
            }
            return
        }

        tap = newTap
        let rlSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        runLoopSource = rlSource
        CFRunLoopAddSource(CFRunLoopGetMain(), rlSource, .defaultMode)
        CGEvent.tapEnable(tap: newTap, enable: true)

        EventTapController.diagLog("✅ event tap đã hoạt động — gõ thử: tuan62 / ngay2 / hai9")
        NotificationCenter.default.post(name: .miniUnikeyStatusChanged, object: nil)
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        if let t = tap {
            CGEvent.tapEnable(tap: t, enable: false)
        }
        tap = nil
        runLoopSource = nil
        NotificationCenter.default.post(name: .miniUnikeyStatusChanged, object: nil)
    }

    /// Tắt rồi bật lại (menu "Thử lại")
    func restart() {
        stop()
        retryCount = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.start()
        }
    }

    var isRunning: Bool { tap != nil }

    private func restartTap() {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.start()
        }
    }

    /// Log lần phím đầu tiên để biết event có chạm tới tap không
    private static var firstKeyDownLogged = false
    private static var firstTransformLogged = false

    // MARK: - handler

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // event do chính mình post: bỏ qua
        if event.getIntegerValueField(.eventSourceUserData) == EventTapController.eventMarkerValue {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            return handleKeyDown(event)
        case .leftMouseUp, .rightMouseUp:
            engine.reset()  // di chuyển con trỏ bằng chuột → về trạng thái "không có từ"
            return Unmanaged.passUnretained(event)
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            EventTapController.diagLog("⚠️ tap bị tạm dừng (timeout) — bật lại")
            restartTap()
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        // Nếu bộ gõ English/lỗi gì đó: cứ để nguyên
        let flags = event.flags
        // Cmd/Option/Control → phím tắt hệ thống: không can thiệp
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            engine.reset()
            return Unmanaged.passUnretained(event)
        }

        let vk = event.getIntegerValueField(.keyboardEventKeycode)

        // Backspace: giúp engine tính việc dời lại dấu thanh sau khi xoá
        if vk == kVK_Delete {
            let result = engine.processBackspace()
            if result.changed && result.backs > 0 {
                postBackspaces(count: result.backs)
                if !result.output.isEmpty {
                    postText(result.output)
                }
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        var actualLength: Int = 0
        var chars = [UniChar](repeating: 0, count: 4)
        chars.withUnsafeMutableBufferPointer { buf in
            event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &actualLength, unicodeString: buf.baseAddress)
        }

        // Không có ký tự (F1..F12, navigation, media): reset bộ đệm từ, đi tiếp
        if actualLength == 0 {
            engine.reset()
            return Unmanaged.passUnretained(event)
        }
        let units = Array(chars.prefix(actualLength))
        let scalars = String(utf16CodeUnits: units, count: units.count)
        let unicodeScalars = Array(scalars.unicodeScalars)
        // Chuỗi phức (IME/dead-key): bỏ qua khỏi engine
        guard unicodeScalars.count == 1, unicodeScalars[0].value != 0 else {
            engine.reset()
            return Unmanaged.passUnretained(event)
        }
        let scalar = unicodeScalars[0]

        if !EventTapController.firstKeyDownLogged {
            EventTapController.firstKeyDownLogged = true
            EventTapController.diagLog("✓ nhận được phím đầu tiên ('\(String(Character(scalar)))') — tap đang sống")
        }

        let result = engine.process(scalar.value)
        guard result.changed, result.backs > 0 else {
            return Unmanaged.passUnretained(event)
        }

        if !EventTapController.firstTransformLogged {
            EventTapController.firstTransformLogged = true
            EventTapController.diagLog("✓ biến đổi phím đầu tiên thành '\(result.output)'")
        }

        let appID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        let useSelection = EventTapController.shouldUseSelection(for: appID, enabled: SettingsStore.shared.selectionModeEnabled)
        if !EventTapController.firstTransformLogged {
            EventTapController.firstTransformLogged = true
            EventTapController.diagLog("✓ biến đổi trong '\(appName)' (\(appID)) — chế độ \(useSelection ? "chọn-thay-thế" : "backspace")")
        }

        // phím gây biến đổi: nuốt, xoá rồi chèn thay thế
        if useSelection {
            postSelectionRewind(count: result.backs)
        } else {
            postBackspaces(count: result.backs)
        }
        if result.output.isEmpty {
            // Trả lại chính ký tự gốc (số literal như 6/7/8/9 không hợp lệ...)
            postText(String(Character(scalar)))
        } else {
            postText(result.output)
        }
        return nil
    }

    // MARK: - chiến lược tương thích

    /// Trình duyệt/Electron bỏ qua BackSpace tổng hợp — cần chọn-ngược rồi gõ đè.
    private static func shouldUseSelection(for appID: String, enabled: Bool) -> Bool {
        guard enabled else { return false }
        let id = appID.lowercased()
        let needSelection = [
            "chrome", "chromium", "brave", "edge", "vivaldi", "opera",
            "thebrowser",          // Arc
            "firefox",
            "vscode", "cursor",    // Electron editors
            "slack", "discord", "whatsapp", "notion", "obsidian",
            "figma", "postman", "linear", "zen",
        ]
        return needSelection.contains { id.contains($0) }
    }

    /// Chọn `count` ký tự phía bên trái (Shift + ←) — gõ đè sẽ thay vùng chọn.
    private func postSelectionRewind(count: Int) {
        guard count > 0 else { return }
        guard let source = eventSource else { return }
        let left = CGKeyCode(kVK_LeftArrow)
        for _ in 0..<count {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: left, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: left, keyDown: false) else { continue }
            down.flags = .maskShift
            up.flags = .maskShift
            markOwn(down)
            markOwn(up)
            down.post(tap: .cgSessionEventTap)
            up.post(tap: .cgSessionEventTap)
        }
    }

    // MARK: - post lại văn bản/backspace

    private func markOwn(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: EventTapController.eventMarkerValue)
    }

    private func postBackspaces(count: Int) {
        guard let source = eventSource, count > 0 else { return }
        let key = CGKeyCode(kVK_Delete)
        for _ in 0..<count {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { continue }
            markOwn(down)
            markOwn(up)
            down.post(tap: .cgSessionEventTap)
            up.post(tap: .cgSessionEventTap)
        }
    }

    private func postText(_ text: String) {
        guard let source = eventSource, !text.isEmpty else { return }
        for scalar in text.unicodeScalars {
            let units = Array(String(scalar).utf16)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { continue }
            markOwn(down)
            markOwn(up)
            down.keyboardSetUnicodeString(stringLength: Int(units.count), unicodeString: units)
            down.post(tap: .cgSessionEventTap)
            up.post(tap: .cgSessionEventTap)
        }
    }
}
