//
//  main.swift + AppDelegate
//  MiniUnikey
//  Bộ gõ tiếng Việt kiểu VNI cho macOS — menu bar, không Dock.
//
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppCoordinator.shared.start()
        NSApp.activate(ignoringOtherApps: false)
    }

    func application(_ application: NSApplication, open urls: [URL]) {}
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
