//
//  AppCoordinator.swift
//  MiniUnikey
//
//  Icon menu bar + menu + cửa sổ hướng dẫn. Nối SettingsStore với EventTapController.
//
import AppKit

extension Notification.Name {
    static let miniUnikeyStatusChanged = Notification.Name("MiniUnikeyStatusChanged")
}

final class AppCoordinator: NSObject {
    static let shared = AppCoordinator()

    private var statusItem: NSStatusItem?
    private var guideWindow: NSWindow?

    func start() {
        buildStatusItem()
        refreshMenu()
        refreshStatusText()
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged),
            name: SettingsStore.changedNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(tapStatusChanged),
            name: .miniUnikeyStatusChanged, object: nil)
        EventTapController.shared.start()
        SettingsStore.shared.applyLaunchAtLogin()

        // Chưa có quyền → tự bật cửa sổ hướng dẫn cho người dùng nhìn thấy ngay
        if !Permissions.isAccessibilityGranted() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.showGuide(highlightPermission: true)
            }
        }
    }

    // MARK: - status item

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
    }

    private func refreshStatusText() {
        guard let button = statusItem?.button else { return }
        button.title = SettingsStore.shared.vietnameseOn ? "VN" : "en"
        if SettingsStore.shared.vietnameseOn {
            button.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
        } else {
            button.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        }
        button.toolTip = SettingsStore.shared.vietnameseOn
            ? "MiniUnikey: đang gõ tiếng Việt (kiểu VNI) — bấm để mở menu"
            : "MiniUnikey: đang gõ tiếng Anh/macOS — bấm để mở menu"
    }

    @objc private func refreshMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()

        let toggle = NSMenuItem(
            title: SettingsStore.shared.vietnameseOn
                ? "Tắt gõ tiếng Việt"
                : "Bật gõ tiếng Việt",
            action: #selector(toggleVietnamese), keyEquivalent: "v")
        toggle.keyEquivalentModifierMask = [.command]
        toggle.target = self
        menu.addItem(toggle)

        menu.addItem(.separator())

        // Trạng thái thu phím
        let tap = EventTapController.shared
        let stateText: String
        if Permissions.isAccessibilityGranted() && tap.isRunning {
            stateText = "✓ Đang thu phím — gõ thử: tuan62"
        } else if Permissions.isAccessibilityGranted() {
            stateText = "⏳ Đã có quyền — bấm “Thử lại”"
        } else {
            stateText = "⚠️ Chưa có quyền Accessibility"
        }
        let state = NSMenuItem(title: stateText, action: nil, keyEquivalent: "")
        menu.addItem(state)
        menu.addItem(.separator())

        // Kiểu gõ: VNI / Telex
        let methodTitle = NSMenuItem(title: "Kiểu gõ:", action: nil, keyEquivalent: "")
        methodTitle.isEnabled = false
        menu.addItem(methodTitle)

        let vni = NSMenuItem(title: "⦿ VNI (số cuối từ: sach1)", action: #selector(pickVNI), keyEquivalent: "")
        vni.state = SettingsStore.shared.inputMethod == "vni" ? .on : .off
        vni.target = self
        menu.addItem(vni)

        let telex = NSMenuItem(title: "⦿ Telex (s/f/r/x/j + aa/dd: sach1 s?", action: #selector(pickTelex), keyEquivalent: "")
        telex.title = "Telex (s f r x j — dấu thanh, aa â, dd đ)"
        telex.state = SettingsStore.shared.inputMethod == "telex" ? .on : .off
        telex.target = self
        menu.addItem(telex)

        menu.addItem(.separator())

        let selection = NSMenuItem(title: "Chế độ tương thích trình duyệt (chọn-ký-tự thay backspace)",
                                   action: #selector(toggleSelection), keyEquivalent: "")
        selection.state = SettingsStore.shared.selectionModeEnabled ? .on : .off
        selection.target = self
        menu.addItem(selection)

        menu.addItem(.separator())

        let spell = NSMenuItem(title: "Kiểm tra chính tả", action: #selector(toggleSpell), keyEquivalent: "")
        spell.state = SettingsStore.shared.spellCheckEnabled ? .on : .off
        spell.target = self
        menu.addItem(spell)

        let modern = NSMenuItem(title: "Kiểu dấu mới (oà thay vì òa)", action: #selector(toggleModern), keyEquivalent: "")
        modern.state = SettingsStore.shared.modernStyleEnabled ? .on : .off
        modern.target = self
        menu.addItem(modern)

        let free = NSMenuItem(title: "Gõ tự do", action: #selector(toggleFree), keyEquivalent: "")
        free.state = SettingsStore.shared.freeMarkingEnabled ? .on : .off
        free.target = self
        menu.addItem(free)

        menu.addItem(.separator())

        let retry = NSMenuItem(title: "Thử lại (khởi động lại bộ thu phím)", action: #selector(retryTap), keyEquivalent: "r")
        retry.keyEquivalentModifierMask = [.command]
        retry.target = self
        menu.addItem(retry)

        let log = NSMenuItem(title: "Mở nhật ký chẩn đoán…", action: #selector(openDiagLog), keyEquivalent: "")
        log.target = self
        menu.addItem(log)

        menu.addItem(.separator())

        let login = NSMenuItem(title: "Khởi động cùng macOS", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = SettingsStore.shared.launchAtLoginEnabled ? .on : .off
        login.target = self
        menu.addItem(login)

        let guide = NSMenuItem(title: "Hướng dẫn & gõ thử…", action: #selector(showGuide), keyEquivalent: "?")
        guide.keyEquivalentModifierMask = [.command]
        guide.target = self
        menu.addItem(guide)

        menu.addItem(.separator())

        let axg: NSMenuItem
        if Permissions.isAccessibilityGranted() {
            axg = NSMenuItem(title: "Quyền Accessibility: ✓", action: nil, keyEquivalent: "")
        } else {
            axg = NSMenuItem(title: "⚠️ Cần cấp quyền Accessibility…", action: #selector(requestPermission), keyEquivalent: "")
            axg.target = self
        }
        menu.addItem(axg)

        let quit = NSMenuItem(title: "Thoát MiniUnikey", action: #selector(quit), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
    }

    // MARK: - hành động

    @objc private func settingsChanged() {
        refreshMenu()
        refreshStatusText()
        SettingsStore.shared.applyLaunchAtLogin()
        // Nếu đang tắt bộ gõ thì cũng ngừng tap cho nhẹ
        if SettingsStore.shared.vietnameseOn {
            EventTapController.shared.start()
        }
    }

    @objc private func tapStatusChanged() {
        refreshMenu()
        refreshStatusText()
    }

    @objc private func toggleVietnamese() {
        SettingsStore.shared.vietnameseOn.toggle()
    }

    @objc private func toggleSpell() {
        SettingsStore.shared.spellCheckEnabled.toggle()
    }

    @objc private func toggleSelection() {
        SettingsStore.shared.selectionModeEnabled.toggle()
    }

    @objc private func pickVNI() {
        SettingsStore.shared.inputMethod = "vni"
    }

    @objc private func pickTelex() {
        SettingsStore.shared.inputMethod = "telex"
    }

    @objc private func toggleModern() {
        SettingsStore.shared.modernStyleEnabled.toggle()
    }

    @objc private func toggleFree() {
        SettingsStore.shared.freeMarkingEnabled.toggle()
    }

    @objc private func toggleLogin() {
        SettingsStore.shared.launchAtLoginEnabled.toggle()
    }

    @objc private func requestPermission() {
        Permissions.requestAccessibilityPrompt()
        Permissions.openSystemSettings()
        showGuide(highlightPermission: true)
    }

    @objc private func retryTap() {
        EventTapController.diagLog("người dùng bấm “Thử lại”")
        EventTapController.shared.restart()
        SettingsStore.shared.notifyForTest()
    }

    @objc private func openDiagLog() {
        let url = EventTapController.diagLogURL()
        if !FileManager.default.fileExists(atPath: url.path) {
            EventTapController.diagLog("(nhật ký mới)")
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc func showGuide(highlightPermission: Bool = false) {
        if guideWindow == nil {
            let window = GuideWindow()
            guideWindow = window
        }
        let hasAX = Permissions.isAccessibilityGranted()
        let permissionLine = hasAX
            ? "✓ Quyền Accessibility đã cấp."
            : "⚠️ Chưa cấp quyền Accessibility. Bước 1–2 dưới đây là bắt buộc."
        (guideWindow?.contentView as? GuideView)?.configure(permissionLine: permissionLine, highlight: highlightPermission)
        guideWindow?.orderFrontRegardless()
        guideWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func showGuide() {
        showGuide(highlightPermission: false)
    }
}
