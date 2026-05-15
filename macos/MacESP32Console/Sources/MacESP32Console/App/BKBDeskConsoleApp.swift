import AppKit
import Darwin
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var lockFile: FileHandle?
    private let activationNotification = Notification.Name("com.biankai.macesp32console.activate")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        acquireSingleInstanceLock()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NotificationCenter.default.post(name: activationNotification, object: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    private func acquireSingleInstanceLock() {
        let lockURL = FileManager.default.temporaryDirectory.appendingPathComponent("com.biankai.macesp32console.lock")
        FileManager.default.createFile(atPath: lockURL.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: lockURL) else { return }
        if flock(handle.fileDescriptor, LOCK_EX | LOCK_NB) != 0 {
            DistributedNotificationCenter.default().post(name: activationNotification, object: nil)
            NSApp.terminate(nil)
            return
        }
        lockFile = handle
    }
}

@main
struct MacESP32ConsoleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ConsoleStore()
    @Environment(\.openWindow) private var openWindow
    private let menuSymbolName = NSImage(systemSymbolName: "robot", accessibilityDescription: nil) == nil ? "cpu" : "robot"

    var body: some Scene {
        WindowGroup("Mac-esp32控制台", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 980, minHeight: 680)
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("com.biankai.macesp32console.activate"))) { _ in
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .onReceive(DistributedNotificationCenter.default().publisher(for: Notification.Name("com.biankai.macesp32console.activate"))) { _ in
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 1180, height: 760)

        MenuBarExtra {
            MenuBarOverview(store: store)
        } label: {
            Image(systemName: menuSymbolName)
                .symbolRenderingMode(.hierarchical)
        }
    }
}

private struct MenuBarOverview: View {
    @ObservedObject var store: ConsoleStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Mac-ESP32 机器人", systemImage: NSImage(systemSymbolName: "robot", accessibilityDescription: nil) == nil ? "cpu" : "robot")
                .font(.headline)

            Divider()

            Label(store.deviceStatus.online ? "ESP32 在线" : "ESP32 离线", systemImage: store.deviceStatus.online ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            Text("Mood: \(store.deviceStatus.mood)")
            Text("Mac: CPU \(store.performance.cpuPct)% · MEM \(store.performance.memPct)%")
            if let temp = store.performance.tempC {
                Text("Temp: \(temp)C")
            }

            Divider()

            Button("打开主控制台") {
                openMainWindow()
            }
            Button("运行诊断") {
                openMainWindow()
                Task { await store.runDiagnostics() }
            }
            Button("修复连接") {
                openMainWindow()
                Task { await store.repairConnection() }
            }
            Button(store.isTelegramRunning ? "停止 Telegram" : "启动 Telegram") {
                store.toggleTelegram()
            }

            Divider()

            Button("退出") {
                NSApp.terminate(nil)
            }
        }
        .task {
            store.startPerformanceLoop()
        }
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
