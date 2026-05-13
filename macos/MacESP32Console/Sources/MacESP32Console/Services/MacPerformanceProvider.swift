import Foundation

struct MacPerformanceProvider {
    func snapshot() async -> MacPerformanceSnapshot {
        var snap = MacPerformanceSnapshot()
        if let status = await readMacbrainStatus() {
            snap.cpuPct = status.cpuPct
            snap.memPct = status.memPct
            snap.tempC = status.tempC
            snap.thermalSource = status.thermalSource
            snap.app = status.app
            snap.idleS = status.idleS
            snap.time = status.time
        }

        let totalMemory = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
        snap.memoryTotalGB = totalMemory
        snap.memoryUsedGB = totalMemory * Double(snap.memPct) / 100.0

        if let disk = diskUsage() {
            snap.storageTotalGB = disk.total
            snap.storageUsedGB = disk.used
        }

        snap.updatedAt = Date()
        return snap
    }

    private func readMacbrainStatus() async -> MacbrainStatus? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let scriptURL = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("bin/macbrain_status_v6.sh")
                process.executableURL = scriptURL
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let status = try? JSONDecoder().decode(MacbrainStatus.self, from: data)
                    continuation.resume(returning: status)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func diskUsage() -> (used: Double, total: Double)? {
        do {
            let values = try URL(fileURLWithPath: "/").resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey
            ])
            guard let totalBytes = values.volumeTotalCapacity else { return nil }
            let availableBytes = values.volumeAvailableCapacityForImportantUsage ?? 0
            let total = Double(totalBytes) / 1_073_741_824.0
            let available = Double(availableBytes) / 1_073_741_824.0
            return (max(0, total - available), total)
        } catch {
            return nil
        }
    }
}

private struct MacbrainStatus: Decodable {
    let cpuPct: Int
    let memPct: Int
    let tempC: Int?
    let thermalSource: String
    let app: String
    let idleS: Int
    let time: String

    enum CodingKeys: String, CodingKey {
        case cpuPct = "cpu_pct"
        case memPct = "mem_pct"
        case tempC = "temp_c"
        case thermalSource = "thermal_source"
        case app
        case idleS = "idle_s"
        case time
    }
}
