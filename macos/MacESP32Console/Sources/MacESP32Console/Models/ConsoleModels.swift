import AppKit
import Foundation

enum ConsoleSection: String, CaseIterable, Identifiable {
    case screen
    case deepseek
    case performance
    case device
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screen: return "屏幕显示"
        case .deepseek: return "DeepSeek 对话"
        case .performance: return "Mac 状态"
        case .device: return "设备与配网"
        case .diagnostics: return "诊断与向导"
        }
    }

    var subtitle: String {
        switch self {
        case .screen: return "输入文字并显示到 OLED"
        case .deepseek: return "短句回复，流式上屏"
        case .performance: return "CPU、内存、温度、存储"
        case .device: return "唤醒、重启、Wi-Fi/MQTT"
        case .diagnostics: return "系统检查、首次配置"
        }
    }

    var systemImage: String {
        switch self {
        case .screen: return "display"
        case .deepseek: return "sparkles"
        case .performance: return "gauge.with.dots.needle.67percent"
        case .device: return "wifi.router"
        case .diagnostics: return "stethoscope"
        }
    }
}

enum DisplayQueueSource: String, Codable {
    case console
    case deepseek
    case telegram
    case performance

    var label: String {
        switch self {
        case .console: return "屏幕"
        case .deepseek: return "DeepSeek"
        case .telegram: return "Telegram"
        case .performance: return "Mac 状态"
        }
    }
}

struct DisplayQueueItem: Identifiable {
    let id = UUID()
    var text: String
    var style: ConsoleStyle
    var durationMs: Int
    var source: DisplayQueueSource
    var createdAt = Date()

    var preview: String {
        text.replacingOccurrences(of: "\n", with: " ").prefixText(30)
    }
}

enum ConsoleStyle: String, CaseIterable, Identifiable {
    case full
    case bubble
    case caption

    var id: String { rawValue }
}

struct DeviceStatusSnapshot {
    var online = false
    var petState: [String: String] = [:]
    var macState: [String: String] = [:]
    var updatedAt = Date.distantPast

    var firmware: String { petState["fw"] ?? "--" }
    var ip: String { petState["ip"] ?? "--" }
    var rssi: String { petState["rssi"] ?? "--" }
    var mqttConnected: String { petState["mqtt_connected"] ?? "--" }
    var macLink: String {
        if let value = petState["mac_link"] { return value }
        if let ageText = petState["last_mac_state_age_ms"], let age = Int(ageText) {
            return age < 10_000 ? "ok" : "stale"
        }
        return "--"
    }
    var mood: String { petState["current_mood"] ?? petState["mood"] ?? "--" }
    var scene: String { petState["current_scene"] ?? petState["scene"] ?? "--" }
    var screenOn: String { petState["screen_on"] ?? "--" }
    var fanPct: String { petState["fan_pct"] ?? "--" }
    var reason: String { petState["mood_reason"] ?? "--" }
}

struct OLEDBitmap {
    let id: String
    let bytes: [UInt8]
    let previewImage: NSImage

    var base64: String {
        Data(bytes).base64EncodedString()
    }
}

struct BitmapCommand: Encodable {
    let v: Int
    let id: String
    let w: Int
    let h: Int
    let format: String
    let encoding: String
    let durationMs: Int
    let data: String

    enum CodingKeys: String, CodingKey {
        case v, id, w, h, format, encoding, data
        case durationMs = "duration_ms"
    }
}

struct BitmapPageCommand: Encodable {
    let v: Int
    let id: String
    let pageIndex: Int
    let pageCount: Int
    let w: Int
    let h: Int
    let format: String
    let encoding: String
    let durationMs: Int
    let source: String
    let data: String

    enum CodingKeys: String, CodingKey {
        case v, id, w, h, format, encoding, source, data
        case pageIndex = "page_index"
        case pageCount = "page_count"
        case durationMs = "duration_ms"
    }
}

struct SceneCommand: Encodable {
    let v: Int
    let scene: String
    let durationMs: Int
    let source: String

    enum CodingKeys: String, CodingKey {
        case v, scene, source
        case durationMs = "duration_ms"
    }
}

struct DeviceCommand: Encodable {
    let v: Int
    let action: String
}

struct NetworkConfigCommand: Encodable {
    let v: Int
    let ssid: String
    let password: String
    let mqttHost: String
    let mqttPort: Int

    enum CodingKeys: String, CodingKey {
        case v, ssid, password
        case mqttHost = "mqtt_host"
        case mqttPort = "mqtt_port"
    }
}

struct ChatMessage: Identifiable {
    enum Role: Equatable {
        case user
        case assistant
        case system
    }

    let id = UUID()
    var role: Role
    var text: String
}

struct MacPerformanceSnapshot {
    var cpuPct: Int = 0
    var memPct: Int = 0
    var memoryUsedGB: Double = 0
    var memoryTotalGB: Double = 0
    var tempC: Int?
    var thermalSource: String = "unavailable"
    var storageUsedGB: Double = 0
    var storageTotalGB: Double = 0
    var app: String = "Unknown"
    var idleS: Int = 0
    var time: String = "--:--"
    var updatedAt = Date()
}

struct TelegramLogEntry: Identifiable {
    let id = UUID()
    var text: String
    var date = Date()
}

enum DiagnosticStatus: String {
    case pass
    case warn
    case fail
    case checking

    var label: String {
        switch self {
        case .pass: return "PASS"
        case .warn: return "WARN"
        case .fail: return "FAIL"
        case .checking: return "CHECK"
        }
    }
}

struct DiagnosticItem: Identifiable {
    let id = UUID()
    var title: String
    var status: DiagnosticStatus
    var detail: String
    var fix: String
}

struct DiagnosticReport {
    var items: [DiagnosticItem] = []
    var macIPs: [String] = []
    var updatedAt = Date.distantPast

    var hasFailure: Bool {
        items.contains { $0.status == .fail }
    }

    var summary: String {
        let passCount = items.filter { $0.status == .pass }.count
        let warnCount = items.filter { $0.status == .warn }.count
        let failCount = items.filter { $0.status == .fail }.count
        return "\(passCount) pass / \(warnCount) warn / \(failCount) fail"
    }
}

private extension StringProtocol {
    func prefixText(_ length: Int) -> String {
        let result = String(prefix(length))
        return count > length ? result + "..." : result
    }
}
