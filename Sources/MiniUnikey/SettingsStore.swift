//
//  SettingsStore.swift
//  MiniUnikey
//
//  Lưu cấu hình người dùng (UserDefaults), thông báo khi thay đổi.
//
import Foundation
import ServiceManagement

final class SettingsStore {
    static let shared = SettingsStore()

    static let changedNotification = Notification.Name("MiniUnikeySettingsChanged")

    enum Keys {
        static let vietnameseOn = "vietnameseOn"
        static let spellCheck = "spellCheckEnabled"
        static let freeMarking = "freeMarkingEnabled"
        static let modernStyle = "modernStyleEnabled"
        static let launchAtLogin = "launchAtLoginEnabled"
        static let selectionMode = "selectionModeEnabled"
        static let inputMethod = "inputMethod"
    }

    private let defaults = UserDefaults.standard

    var vietnameseOn: Bool {
        get { defaults.object(forKey: Keys.vietnameseOn) == nil ? true : defaults.bool(forKey: Keys.vietnameseOn) }
        set { defaults.set(newValue, forKey: Keys.vietnameseOn); notify() }
    }

    var spellCheckEnabled: Bool {
        get { defaults.object(forKey: Keys.spellCheck) == nil ? true : defaults.bool(forKey: Keys.spellCheck) }
        set { defaults.set(newValue, forKey: Keys.spellCheck); notify() }
    }

    var freeMarkingEnabled: Bool {
        get { defaults.object(forKey: Keys.freeMarking) == nil ? true : defaults.bool(forKey: Keys.freeMarking) }
        set { defaults.set(newValue, forKey: Keys.freeMarking); notify() }
    }

    var modernStyleEnabled: Bool {
        get { defaults.bool(forKey: Keys.modernStyle) }
        set { defaults.set(newValue, forKey: Keys.modernStyle); notify() }
    }

    var launchAtLoginEnabled: Bool {
        get { defaults.object(forKey: Keys.launchAtLogin) == nil ? false : defaults.bool(forKey: Keys.launchAtLogin) }
        set { defaults.set(newValue, forKey: Keys.launchAtLogin); notify() }
    }

    /// Chế độ tương thích trình duyệt: chọn-ký-tự-ngược rồi gõ đè thay vì backspace
    var selectionModeEnabled: Bool {
        get { defaults.object(forKey: Keys.selectionMode) == nil ? true : defaults.bool(forKey: Keys.selectionMode) }
        set { defaults.set(newValue, forKey: Keys.selectionMode); notify() }
    }

    /// Kiểu gõ: "vni" hoặc "telex"
    var inputMethod: String {
        get { defaults.string(forKey: Keys.inputMethod) ?? "vni" }
        set { defaults.set(newValue, forKey: Keys.inputMethod); notify() }
    }

    func applyLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if launchAtLoginEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Tạm thời bỏ qua lỗi (thường xảy ra khi chạy qua swift build trực tiếp)
        }
    }

    private func notify() {
        NotificationCenter.default.post(name: SettingsStore.changedNotification, object: nil)
    }

    /// Đưa thông báo thay đổi (dùng bởi menu để làm mới trạng thái)
    func notifyForTest() {
        notify()
    }}
