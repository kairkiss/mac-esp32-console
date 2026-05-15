import AppKit
import Foundation

struct DiagnosticExportService {
    func export(
        deviceStatus: DeviceStatusSnapshot,
        diagnosticReport: DiagnosticReport,
        appLogs: [String],
        telegramLogs: [TelegramLogEntry],
        performance: MacPerformanceSnapshot
    ) throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent("MacESP32-Diagnostics-\(stamp)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        try writeJSON(deviceStatus.dictionary, to: folder.appendingPathComponent("device_status.json"))
        try writeJSON(diagnosticReport.dictionary, to: folder.appendingPathComponent("diagnostic_report.json"))
        try writeJSON(performance.dictionary, to: folder.appendingPathComponent("mac_performance.json"))
        try appLogs.joined(separator: "\n").write(to: folder.appendingPathComponent("app_logs.txt"), atomically: true, encoding: .utf8)
        try telegramLogs.map(\.text).joined(separator: "\n").write(to: folder.appendingPathComponent("telegram_logs.txt"), atomically: true, encoding: .utf8)
        try """
        Mac-ESP32 Console diagnostics export

        Generated: \(Date())
        This package contains local status snapshots only. Secrets are not exported.
        """.write(to: folder.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)

        NSWorkspace.shared.activateFileViewerSelecting([folder])
        return folder
    }

    private func writeJSON(_ value: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }
}

private extension DeviceStatusSnapshot {
    var dictionary: [String: Any] {
        [
            "online": online,
            "updated_at": updatedAt.description,
            "pet_state": petState,
            "mac_state": macState
        ]
    }
}

private extension DiagnosticReport {
    var dictionary: [String: Any] {
        [
            "summary": summary,
            "updated_at": updatedAt.description,
            "mac_ips": macIPs,
            "items": items.map {
                [
                    "title": $0.title,
                    "status": $0.status.rawValue,
                    "detail": $0.detail,
                    "fix": $0.fix
                ]
            }
        ]
    }
}

private extension MacPerformanceSnapshot {
    var dictionary: [String: Any] {
        [
            "cpu_pct": cpuPct,
            "mem_pct": memPct,
            "memory_used_gb": memoryUsedGB,
            "memory_total_gb": memoryTotalGB,
            "temp_c": tempC.map { $0 as Any } ?? NSNull(),
            "thermal_source": thermalSource,
            "storage_used_gb": storageUsedGB,
            "storage_total_gb": storageTotalGB,
            "app": app,
            "idle_s": idleS,
            "time": time,
            "updated_at": updatedAt.description
        ]
    }
}
