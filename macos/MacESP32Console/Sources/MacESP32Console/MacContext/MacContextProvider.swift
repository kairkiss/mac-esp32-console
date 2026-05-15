import Foundation

struct MacContextProvider {
    func snapshot() async -> MacContextSnapshot {
        var snap = await WindowContextProvider().snapshot()
        snap.nowPlaying = await NowPlayingProvider().snapshot()
        snap.nextEvent = await CalendarContextProvider().snapshot()
        snap.updatedAt = Date()
        return snap
    }
}
