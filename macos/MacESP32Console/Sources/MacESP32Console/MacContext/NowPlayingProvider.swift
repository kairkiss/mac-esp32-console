import Foundation

struct NowPlayingProvider {
    func snapshot() async -> NowPlayingSnapshot? {
        if let music = await appleMusic() { return music }
        if let spotify = await spotify() { return spotify }
        return nil
    }

    private func appleMusic() async -> NowPlayingSnapshot? {
        await runScript(appName: "Music")
    }

    private func spotify() async -> NowPlayingSnapshot? {
        await runScript(appName: "Spotify")
    }

    private func runScript(appName: String) async -> NowPlayingSnapshot? {
        await Task.detached {
            let script = """
            if application "\(appName)" is running then
              tell application "\(appName)"
                try
                  if player state is playing then
                    return name of current track & "|||SEP|||" & artist of current track
                  end if
                end try
              end tell
            end if
            return ""
            """
            var error: NSDictionary?
            let value = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue ?? ""
            let parts = value.components(separatedBy: "|||SEP|||")
            guard parts.count >= 2, !parts[0].isEmpty else { return nil }
            return NowPlayingSnapshot(title: parts[0], artist: parts[1], progress: 0.35)
        }.value
    }
}
