import Foundation

struct MacContextSnapshot {
    var app: String = "Unknown"
    var windowTitle: String = ""
    var nowPlaying: NowPlayingSnapshot?
    var nextEvent: CalendarEventSnapshot?
    var updatedAt = Date()
}

struct NowPlayingSnapshot {
    var title: String
    var artist: String
    var progress: Double
}

struct CalendarEventSnapshot {
    var title: String
    var time: String
    var minutesLeft: Int?
}
