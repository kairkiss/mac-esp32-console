import Foundation

enum DisplaySceneID: String, CaseIterable, Identifiable {
    case coding
    case music
    case calendar
    case night
    case dreamcore
    case diagnostics
    case ota
    case networkError = "network_error"
    case dashboard

    var id: String { rawValue }
}

enum DisplayRenderStrategy: String, Codable {
    case bitmap
    case nativeText = "native_text"
}

enum DisplayLayer: String, Codable {
    case background
    case faceHint
    case widget
    case caption
}

struct DisplayScenePreset: Identifiable {
    var id: DisplaySceneID
    var title: String
    var mood: String
    var durationMs: Int
    var priority: Int
    var source: String
    var renderStrategy: DisplayRenderStrategy
    var preview: String
}

enum ScenePresetLibrary {
    static let presets: [DisplayScenePreset] = [
        .init(id: .coding, title: "编程场景", mood: "focus", durationMs: 7000, priority: 30, source: "scene_center", renderStrategy: .bitmap, preview: "Code focus dashboard"),
        .init(id: .music, title: "音乐场景", mood: "happy", durationMs: 7000, priority: 25, source: "scene_center", renderStrategy: .bitmap, preview: "Now playing widget"),
        .init(id: .calendar, title: "日程场景", mood: "focus", durationMs: 7000, priority: 25, source: "scene_center", renderStrategy: .bitmap, preview: "Next calendar event"),
        .init(id: .night, title: "夜间场景", mood: "sleepy", durationMs: 8000, priority: 25, source: "scene_center", renderStrategy: .bitmap, preview: "Quiet night message"),
        .init(id: .dreamcore, title: "梦核场景", mood: "sleepy", durationMs: 9000, priority: 25, source: "scene_center", renderStrategy: .bitmap, preview: "Soft nostalgic text"),
        .init(id: .diagnostics, title: "诊断场景", mood: "thinking", durationMs: 7000, priority: 40, source: "scene_center", renderStrategy: .bitmap, preview: "Device diagnostics"),
        .init(id: .ota, title: "OTA 进度测试", mood: "thinking", durationMs: 7000, priority: 50, source: "scene_center", renderStrategy: .bitmap, preview: "OTA progress"),
        .init(id: .networkError, title: "网络错误测试", mood: "confused", durationMs: 7000, priority: 60, source: "scene_center", renderStrategy: .bitmap, preview: "Network error widget"),
        .init(id: .dashboard, title: "Mac 状态 Dashboard", mood: "focus", durationMs: 7000, priority: 35, source: "scene_center", renderStrategy: .bitmap, preview: "CPU MEM TEMP FAN")
    ]
}
