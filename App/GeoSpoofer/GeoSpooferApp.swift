import AppKit
import GeoSpooferCore
import SwiftUI

@main
struct GeoSpooferApp: App {
    @NSApplicationDelegateAdaptor(GeoSpooferDelegate.self) private var delegate
    @State private var model: AppModel

    init() {
        SingleInstance.handOffIfNeeded()
        do {
            _model = State(initialValue: try AppModel.live())
        } catch {
            _model = State(initialValue: AppModel.failed(error.localizedDescription))
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            MainView(model: model)
                .background(WindowBridge())
        }
        .defaultSize(width: 960, height: 640)
        Window("Location Log", id: "log") {
            LogView(model: model)
        }
        .defaultSize(width: 720, height: 420)
    }
}

private struct WindowBridge: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .geoSpooferOpenWindow)) { note in
                guard let id = note.object as? String else { return }
                openWindow(id: id)
            }
    }
}

final class GeoSpooferDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "location.fill", accessibilityDescription: "GeoSpoofer")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open GeoSpoofer", action: #selector(openMain), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Location Log", action: #selector(openLog), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Stop", action: #selector(stop), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit GeoSpoofer", action: #selector(quit), keyEquivalent: "q"))
        for entry in menu.items { entry.target = self }
        item.menu = menu
        statusItem = item
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openMain() {
        NotificationCenter.default.post(name: .geoSpooferOpenWindow, object: "main")
        NSApp.windows.first { $0.title == "GeoSpoofer" }?.makeKeyAndOrderFront(nil)
    }

    @objc private func openLog() {
        NotificationCenter.default.post(name: .geoSpooferOpenWindow, object: "log")
    }

    @objc private func stop() {
        NotificationCenter.default.post(name: .geoSpooferStop, object: nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension Notification.Name {
    static let geoSpooferOpenWindow = Notification.Name("geoSpooferOpenWindow")
    static let geoSpooferStop = Notification.Name("geoSpooferStop")
}

enum SingleInstance {
    static func handOffIfNeeded() {
        let directory = AppPaths.supportDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = AppPaths.lockFile(in: directory)
        let current = ProcessInfo.processInfo.processIdentifier
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            let existing = InstanceHandoff.pid(in: text)
            let alive = InstanceHandoff.shouldExit(existingPID: existing, currentPID: current) { pid in
                kill(pid, 0) == 0
            }
            if alive, let existing {
                NSRunningApplication(processIdentifier: existing)?.activate(options: [.activateAllWindows])
                exit(0)
            }
        }
        try? String(current).write(to: url, atomically: true, encoding: .utf8)
    }
}
