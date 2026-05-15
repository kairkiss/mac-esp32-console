import AppKit
import Foundation

struct WindowContextProvider {
    func snapshot() async -> MacContextSnapshot {
        async let window = foregroundWindowTitle()
        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        return MacContextSnapshot(app: app, windowTitle: await window, nowPlaying: nil, nextEvent: nil, updatedAt: Date())
    }

    private func foregroundWindowTitle() async -> String {
        await Task.detached {
            let script = """
            tell application "System Events"
              set frontApp to first application process whose frontmost is true
              try
                return name of front window of frontApp
              on error
                return ""
              end try
            end tell
            """
            var error: NSDictionary?
            let appleScript = NSAppleScript(source: script)
            let result = appleScript?.executeAndReturnError(&error).stringValue ?? ""
            return result
        }.value
    }
}
