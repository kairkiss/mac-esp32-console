import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ConsoleStore: ObservableObject {
    @Published var selection: ConsoleSection = .screen

    @Published var nodeRedURL = "http://127.0.0.1:1880" { didSet { savePreference(nodeRedURL, for: "nodeRedURL") } }
    @Published var text = "你好，卞恺" { didSet { savePreference(text, for: "lastScreenText") } }
    @Published var durationMs = 6000 { didSet { savePreference(durationMs, for: "durationMs") } }
    @Published var style: ConsoleStyle = .bubble { didSet { savePreference(style.rawValue, for: "style") } }
    @Published var bitmap = OLEDRenderer.render(text: "你好，卞恺", style: .bubble)
    @Published var isSending = false

    @Published var deepSeekAPIKey = "" { didSet { saveSecret(deepSeekAPIKey, account: "deepSeekAPIKey") } }
    @Published var deepSeekModel = "deepseek-chat" { didSet { savePreference(deepSeekModel, for: "deepSeekModel") } }
    @Published var prompt = ""
    @Published var chatMessages: [ChatMessage] = [
        ChatMessage(role: .system, text: "DeepSeek 会用短句流式显示到 OLED。")
    ]
    @Published var isDeepSeekRunning = false
    @Published var liveAssistantText = ""

    @Published var performance = MacPerformanceSnapshot()
    @Published var isPerformanceRefreshing = false
    @Published var macContext = MacContextSnapshot()

    @Published var telegramToken = "" { didSet { saveSecret(telegramToken, account: "telegramToken") } }
    @Published var telegramAllowedChatId = "" { didSet { savePreference(telegramAllowedChatId, for: "telegramAllowedChatId") } }
    @Published var telegramAutoStart = false { didSet { savePreference(telegramAutoStart, for: "telegramAutoStart") } }
    @Published var isTelegramRunning = false
    @Published var telegramLogs: [TelegramLogEntry] = []

    @Published var deviceStatus = DeviceStatusSnapshot()
    @Published var isDeviceStatusRefreshing = false
    @Published var diagnosticReport = DiagnosticReport()
    @Published var isDiagnosticsRunning = false
    @Published var isRepairingConnection = false
    @Published var setupWizardPresented = false
    @Published var setupCompleted = false { didSet { savePreference(setupCompleted, for: "setupCompleted") } }
    @Published var displayQueue: [DisplayQueueItem] = []
    @Published var activeDisplayItem: DisplayQueueItem?

    @Published var wifiSSID = "" { didSet { savePreference(wifiSSID, for: "wifiSSID") } }
    @Published var wifiPassword = "" { didSet { saveSecret(wifiPassword, account: "wifiPassword") } }
    @Published var macMqttHost = "192.168.1.100" { didSet { savePreference(macMqttHost, for: "macMqttHost") } }
    @Published var mqttPort = 1883 { didSet { savePreference(mqttPort, for: "mqttPort") } }
    @Published var configPortalURL = "http://192.168.4.1" { didSet { savePreference(configPortalURL, for: "configPortalURL") } }
    @Published var isDeviceBusy = false
    @Published var autoUpdateMQTTHost = false { didSet { savePreference(autoUpdateMQTTHost, for: "autoUpdateMQTTHost") } }
    @Published var currentMacIPHint = ""
    @Published var otaStatus = OTAStatusSnapshot.empty
    @Published var otaSelectedFile: URL?
    @Published var otaProgress = 0.0
    @Published var otaMessage = "未检查"
    @Published var isOTAWorking = false

    @Published var logs: [String] = []

    private var telegramTask: Task<Void, Never>?
    private var performanceTask: Task<Void, Never>?
    private var displayQueueTask: Task<Void, Never>?
    private var lastStreamSend = Date.distantPast
    private var isRestoringPreferences = true
    private var isStartingTelegram = false

    init() {
        let defaults = UserDefaults.standard
        nodeRedURL = defaults.string(forKey: "nodeRedURL") ?? nodeRedURL
        text = defaults.string(forKey: "lastScreenText") ?? text
        durationMs = defaults.object(forKey: "durationMs") as? Int ?? durationMs
        if let rawStyle = defaults.string(forKey: "style"), let savedStyle = ConsoleStyle(rawValue: rawStyle) {
            style = savedStyle
        }
        deepSeekAPIKey = KeychainStore.read("deepSeekAPIKey")
        deepSeekModel = defaults.string(forKey: "deepSeekModel") ?? deepSeekModel
        telegramToken = KeychainStore.read("telegramToken")
        telegramAllowedChatId = defaults.string(forKey: "telegramAllowedChatId") ?? telegramAllowedChatId
        telegramAutoStart = defaults.object(forKey: "telegramAutoStart") as? Bool ?? telegramAutoStart
        setupCompleted = defaults.object(forKey: "setupCompleted") as? Bool ?? setupCompleted
        wifiSSID = defaults.string(forKey: "wifiSSID") ?? wifiSSID
        wifiPassword = KeychainStore.read("wifiPassword")
        macMqttHost = defaults.string(forKey: "macMqttHost") ?? macMqttHost
        mqttPort = defaults.object(forKey: "mqttPort") as? Int ?? mqttPort
        configPortalURL = defaults.string(forKey: "configPortalURL") ?? configPortalURL
        autoUpdateMQTTHost = defaults.object(forKey: "autoUpdateMQTTHost") as? Bool ?? autoUpdateMQTTHost
        bitmap = OLEDRenderer.render(text: text, style: style)
        isRestoringPreferences = false
        log("Console ready")
        setupWizardPresented = !setupCompleted
        if telegramAutoStart, !telegramToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 800_000_000)
                self?.toggleTelegram()
            }
        }
    }

    deinit {
        telegramTask?.cancel()
        performanceTask?.cancel()
        displayQueueTask?.cancel()
    }

    func startPerformanceLoop() {
        guard performanceTask == nil else { return }
        performanceTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshPerformance()
                await self?.refreshMacContext()
                await self?.refreshDeviceStatus()
                await self?.checkMacIPDrift()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func renderPreview() {
        bitmap = OLEDRenderer.render(text: text, style: style)
    }

    func sendToDevice() async {
        renderPreview()
        enqueueDisplayText(text, style: style, durationMs: durationMs, source: .console)
    }

    func askDeepSeek() async {
        let key = deepSeekAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            log("DeepSeek API key is empty")
            return
        }
        guard !input.isEmpty else { return }

        isDeepSeekRunning = true
        liveAssistantText = ""
        chatMessages.append(ChatMessage(role: .user, text: input))
        chatMessages.append(ChatMessage(role: .assistant, text: ""))
        prompt = ""
        lastStreamSend = .distantPast

        do {
            try await NodeRedClient(baseURL: nodeRedURL).sendScene("thinking", durationMs: 12000, source: "deepseek")
            let client = DeepSeekClient(apiKey: key, model: deepSeekModel)
            try await client.streamReply(prompt: input) { [weak self] delta in
                guard let self else { return }
                self.liveAssistantText += delta
                self.chatMessages[self.chatMessages.count - 1].text = self.liveAssistantText
                Task { await self.streamAssistantToOLED(force: false) }
            }
            enqueueDisplayText(liveAssistantText, style: .full, durationMs: max(6000, durationMs), source: .deepseek)
            log("DeepSeek response complete")
        } catch {
            log("DeepSeek failed: \(error.localizedDescription)")
            if let last = chatMessages.indices.last, chatMessages[last].role == .assistant {
                chatMessages[last].text = "请求失败：\(error.localizedDescription)"
            }
        }
        isDeepSeekRunning = false
    }

    func refreshPerformance() async {
        isPerformanceRefreshing = true
        performance = await MacPerformanceProvider().snapshot()
        isPerformanceRefreshing = false
    }

    func showPerformanceOnOLED() async {
        bitmap = OLEDWidgetRenderer.renderMetricDashboard(
            cpu: performance.cpuPct,
            mem: performance.memPct,
            temp: performance.tempC,
            fan: deviceStatus.fanPct,
            app: performance.app
        )
        await sendBitmapToOLED(bitmap, durationMs: 7000, source: "performance", logPrefix: "Mac 状态 Dashboard")
    }

    func refreshMacContext() async {
        macContext = await MacContextProvider().snapshot()
    }

    func refreshDeviceStatus() async {
        isDeviceStatusRefreshing = true
        defer { isDeviceStatusRefreshing = false }
        do {
            deviceStatus = try await NodeRedClient(baseURL: nodeRedURL).fetchDeviceStatus()
        } catch {
            deviceStatus = DeviceStatusSnapshot(
                online: false,
                petState: deviceStatus.petState,
                macState: deviceStatus.macState,
                updatedAt: Date()
            )
        }
    }

    func clearDisplayQueue() {
        displayQueue.removeAll()
        log("Display queue cleared")
    }

    func runDiagnostics() async {
        isDiagnosticsRunning = true
        defer { isDiagnosticsRunning = false }
        await refreshDeviceStatus()
        diagnosticReport = await DiagnosticService(nodeRedURL: nodeRedURL).run(deviceStatus: deviceStatus)
        log("Diagnostics complete: \(diagnosticReport.summary)")
    }

    func repairConnection() async {
        guard !isRepairingConnection else { return }
        isRepairingConnection = true
        defer { isRepairingConnection = false }

        log("Connection repair started")
        await refreshDeviceStatus()
        diagnosticReport = await DiagnosticService(nodeRedURL: nodeRedURL).run(deviceStatus: deviceStatus)

        let preferredIP = diagnosticReport.macIPs.first { !$0.hasPrefix("192.168.4.") } ?? diagnosticReport.macIPs.first
        if let preferredIP, macMqttHost != preferredIP {
            macMqttHost = preferredIP
            log("Mac MQTT IP updated to \(preferredIP)")
        }

        if deviceStatus.online {
            log("ESP32 is online; refreshing network config through MQTT")
            await applyNetworkConfigOnline()
        } else {
            log("ESP32 is offline; trying setup portal at \(configPortalURL)")
            await applyNetworkConfigDirect()
        }

        try? await Task.sleep(nanoseconds: 8_000_000_000)
        await refreshDeviceStatus()
        diagnosticReport = await DiagnosticService(nodeRedURL: nodeRedURL).run(deviceStatus: deviceStatus)
        log("Connection repair finished: \(diagnosticReport.summary)")
    }

    func checkMacIPDrift() async {
        let report = await DiagnosticService(nodeRedURL: nodeRedURL).run(deviceStatus: deviceStatus)
        guard let ip = report.macIPs.first(where: { !$0.hasPrefix("192.168.4.") }) ?? report.macIPs.first else { return }
        currentMacIPHint = ip
        if autoUpdateMQTTHost && macMqttHost != ip {
            macMqttHost = ip
            log("Mac IP changed; auto updating MQTT_HOST to \(ip)")
            if deviceStatus.online {
                await applyNetworkConfigOnline()
            }
        }
    }

    func applyDetectedMacIP(_ ip: String) {
        macMqttHost = ip
        log("Mac MQTT IP set to \(ip)")
    }

    func finishSetupWizard() {
        setupCompleted = true
        setupWizardPresented = false
        log("Setup wizard completed")
    }

    func reopenSetupWizard() {
        setupWizardPresented = true
    }

    func toggleTelegram() {
        if isTelegramRunning {
            telegramTask?.cancel()
            telegramTask = nil
            isTelegramRunning = false
            telegramLog("Telegram stopped")
            return
        }

        let token = telegramToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            telegramLog("Token is empty")
            return
        }
        guard telegramTask == nil, !isStartingTelegram else {
            telegramLog("Telegram polling is already running")
            return
        }

        isStartingTelegram = true
        isTelegramRunning = true
        telegramLog("Telegram polling started")
        telegramTask = Task { [weak self] in
            await MainActor.run { self?.isStartingTelegram = false }
            await self?.pollTelegram(token: token)
        }
    }

    func wakeDevice() async {
        await sendDeviceAction("wake", label: "Wake")
    }

    func screenOffDevice() async {
        await sendDeviceAction("screen_off", label: "Screen off")
    }

    func clearSceneDevice() async {
        await sendDeviceAction("clear_scene", label: "Clear scene")
    }

    func testPatternDevice() async {
        await sendDeviceAction("test_pattern", label: "Test pattern")
    }

    func rebootDevice() async {
        await sendDeviceAction("reboot", label: "Reboot")
    }

    func startConfigPortal() async {
        await sendDeviceAction("config_portal", label: "Config portal")
    }

    func applyNetworkConfigOnline() async {
        isDeviceBusy = true
        defer { isDeviceBusy = false }
        do {
            try await NodeRedClient(baseURL: nodeRedURL).sendNetworkConfig(
                ssid: wifiSSID,
                password: wifiPassword,
                mqttHost: macMqttHost,
                mqttPort: mqttPort
            )
            log("Network config sent through MQTT; ESP32 will restart")
        } catch {
            log("Online network config failed: \(error.localizedDescription)")
        }
    }

    func applyNetworkConfigDirect() async {
        isDeviceBusy = true
        defer { isDeviceBusy = false }
        do {
            try await NodeRedClient(baseURL: nodeRedURL).sendNetworkConfigDirect(
                configURL: configPortalURL,
                ssid: wifiSSID,
                password: wifiPassword,
                mqttHost: macMqttHost,
                mqttPort: mqttPort
            )
            log("Network config sent to setup portal; ESP32 will restart")
        } catch {
            log("Setup portal config failed: \(error.localizedDescription)")
        }
    }

    func openConfigPortal() {
        if let url = URL(string: configPortalURL) {
            NSWorkspace.shared.open(url)
        }
    }

    func copyCurrentDeviceStatus() {
        let summary = """
        # Mac-ESP32 Device Status

        - Online: \(deviceStatus.online)
        - Firmware: \(deviceStatus.firmware)
        - IP: \(deviceStatus.ip)
        - RSSI: \(deviceStatus.rssi)
        - MQTT: \(deviceStatus.mqttConnected)
        - MQTT Host: \(deviceStatus.mqttHost)
        - MacLink: \(deviceStatus.macLink)
        - Network Reason: \(deviceStatus.networkReason)
        - Mood: \(deviceStatus.mood)
        - Scene: \(deviceStatus.scene)
        - Screen: \(deviceStatus.screenOn)
        - Fan: \(deviceStatus.fanPct)%
        - Temp Seen: \(deviceStatus.tempSeen)
        - Last Mac State Age: \(deviceStatus.lastMacStateAgeMs) ms
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
        log("Device status copied")
    }

    func exportDiagnostics() async {
        await refreshPerformance()
        await refreshDeviceStatus()
        if diagnosticReport.items.isEmpty {
            diagnosticReport = await DiagnosticService(nodeRedURL: nodeRedURL).run(deviceStatus: deviceStatus)
        }
        do {
            let url = try DiagnosticExportService().export(
                deviceStatus: deviceStatus,
                diagnosticReport: diagnosticReport,
                appLogs: logs,
                telegramLogs: telegramLogs,
                performance: performance
            )
            log("Diagnostic package exported: \(url.path)")
        } catch {
            log("Diagnostic export failed: \(error.localizedDescription)")
        }
    }

    func sendTestExpression(_ name: String) async {
        let text = "Expression\n\(name.uppercased())\nMac-ESP32"
        enqueueDisplayText(text, style: .bubble, durationMs: 6000, source: .console)
    }

    func sendMetricDashboardWidget() async {
        await showPerformanceOnOLED()
    }

    func sendScenePreset(_ preset: DisplayScenePreset) async {
        let image: OLEDBitmap
        switch preset.id {
        case .coding:
            image = OLEDWidgetRenderer.renderMetricDashboard(cpu: performance.cpuPct, mem: performance.memPct, temp: performance.tempC, fan: deviceStatus.fanPct, app: macContext.app)
        case .music:
            let playing = macContext.nowPlaying ?? NowPlayingSnapshot(title: "No track", artist: "Apple Music", progress: 0.2)
            image = OLEDWidgetRenderer.renderNowPlaying(title: playing.title, artist: playing.artist, progress: playing.progress)
        case .calendar:
            let event = macContext.nextEvent ?? CalendarEventSnapshot(title: "Calendar ready", time: "No access", minutesLeft: nil)
            image = OLEDWidgetRenderer.renderCalendarNext(title: event.title, time: event.time, minutesLeft: event.minutesLeft)
        case .night:
            image = OLEDWidgetRenderer.renderDreamcoreText(["夜深了", "屏幕轻一点", "我还醒着"])
        case .dreamcore:
            image = OLEDWidgetRenderer.renderDreamcoreText(["旧窗口在发光", "风从像素里来", "别忘了保存"])
        case .diagnostics:
            image = OLEDWidgetRenderer.renderNetworkError(reason: deviceStatus.networkReason, detail: deviceStatus.ip)
        case .ota:
            image = OLEDWidgetRenderer.renderOTAProgress(percent: 42, phase: "testing")
        case .networkError:
            image = OLEDWidgetRenderer.renderNetworkError(reason: "mqtt_failed", detail: macMqttHost)
        case .dashboard:
            image = OLEDWidgetRenderer.renderMetricDashboard(cpu: performance.cpuPct, mem: performance.memPct, temp: performance.tempC, fan: deviceStatus.fanPct, app: performance.app)
        }
        bitmap = image
        await sendBitmapToOLED(image, durationMs: preset.durationMs, source: preset.source, logPrefix: preset.title)
    }

    func queryOTAStatus() async {
        guard deviceStatus.online else {
            otaMessage = "ESP32 离线，无法查询 OTA"
            return
        }
        isOTAWorking = true
        defer { isOTAWorking = false }
        do {
            otaStatus = try await ESP32DirectClient(host: deviceStatus.ip).fetchOTAStatus()
            otaMessage = otaStatus.otaSupported ? "OTA 可用" : "OTA 不可用：\(otaStatus.reason)"
            log("OTA status: \(otaMessage)")
        } catch {
            otaMessage = "OTA 查询失败：\(error.localizedDescription)"
            log(otaMessage)
        }
    }

    func chooseFirmwareFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            guard url.pathExtension.lowercased() == "bin" else {
                otaMessage = "请选择 .bin 固件文件"
                return
            }
            otaSelectedFile = url
            otaMessage = "已选择 \(url.lastPathComponent)"
        }
    }

    func uploadFirmwareOTA() async {
        guard let file = otaSelectedFile else {
            otaMessage = "请先选择 .bin 文件"
            return
        }
        guard deviceStatus.online else {
            otaMessage = "ESP32 离线，不能 OTA"
            return
        }
        isOTAWorking = true
        otaProgress = 0
        defer { isOTAWorking = false }
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
            let size = attrs[.size] as? NSNumber
            if (size?.intValue ?? 0) <= 0 {
                otaMessage = "固件文件为空"
                return
            }
            let status = try await ESP32DirectClient(host: deviceStatus.ip).fetchOTAStatus()
            guard status.otaSupported else {
                otaMessage = "当前分区不支持 OTA：\(status.reason)"
                return
            }
            if let size, size.intValue > status.freeSketchSpace {
                otaMessage = "固件过大：\(size.intValue) > \(status.freeSketchSpace)"
                return
            }
            otaMessage = "正在上传 OTA..."
            try await ESP32DirectClient(host: deviceStatus.ip).uploadFirmware(fileURL: file) { [weak self] value in
                Task { @MainActor in self?.otaProgress = value }
            }
            otaMessage = "OTA 上传完成，ESP32 将重启"
            log(otaMessage)
        } catch {
            otaMessage = "OTA 失败：\(error.localizedDescription)"
            log(otaMessage)
        }
    }

    func log(_ message: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.insert("[\(ts)] \(message)", at: 0)
        logs = Array(logs.prefix(100))
    }

    private func enqueueDisplayText(_ value: String, style: ConsoleStyle, durationMs: Int, source: DisplayQueueSource) {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        displayQueue.append(DisplayQueueItem(text: clean, style: style, durationMs: max(6000, durationMs), source: source))
        log("\(source.label) queued; queue \(displayQueue.count)")
        startDisplayQueue()
    }

    private func startDisplayQueue() {
        guard displayQueueTask == nil else { return }
        displayQueueTask = Task { [weak self] in
            await self?.processDisplayQueue()
        }
    }

    private func processDisplayQueue() async {
        while !Task.isCancelled {
            guard !displayQueue.isEmpty else {
                displayQueueTask = nil
                activeDisplayItem = nil
                return
            }
            let item = displayQueue.removeFirst()
            activeDisplayItem = item
            isSending = true
            await sendPagedTextToOLED(item.text, style: item.style, durationMs: item.durationMs, source: item.source.rawValue, logPrefix: item.source.label)
            isSending = false
            let pageCount = max(1, OLEDRenderer.renderPages(text: limitSentenceLength(item.text), style: item.style).count)
            let waitMs = min(max(item.durationMs * pageCount, 1200), 45_000)
            try? await Task.sleep(nanoseconds: UInt64(waitMs) * 1_000_000)
        }
    }

    private func sendDeviceAction(_ action: String, label: String) async {
        isDeviceBusy = true
        defer { isDeviceBusy = false }
        do {
            try await NodeRedClient(baseURL: nodeRedURL).sendDeviceAction(action)
            log("\(label) command sent")
        } catch {
            log("\(label) command failed: \(error.localizedDescription)")
        }
    }

    private func sendPagedTextToOLED(_ value: String, style: ConsoleStyle, durationMs: Int, source: String, logPrefix: String) async {
        do {
            let pages = OLEDRenderer.renderPages(text: limitSentenceLength(value), style: style)
            bitmap = pages.first ?? OLEDRenderer.render(text: "", style: style)
            if pages.count == 1 {
                try await NodeRedClient(baseURL: nodeRedURL).send(bitmap: bitmap, durationMs: max(6000, durationMs))
            } else {
                try await NodeRedClient(baseURL: nodeRedURL).sendPages(pages, durationMs: max(6000, durationMs), source: source)
            }
            log("\(logPrefix) sent \(pages.count) page(s) to ESP32")
        } catch {
            log("\(logPrefix) send failed: \(error.localizedDescription)")
        }
    }

    private func sendBitmapToOLED(_ bitmap: OLEDBitmap, durationMs: Int, source: String, logPrefix: String) async {
        do {
            try await NodeRedClient(baseURL: nodeRedURL).send(bitmap: bitmap, durationMs: durationMs)
            log("\(logPrefix) sent to ESP32")
        } catch {
            log("\(logPrefix) send failed: \(error.localizedDescription)")
        }
    }

    private func streamAssistantToOLED(force: Bool) async {
        let now = Date()
        guard force || now.timeIntervalSince(lastStreamSend) > 0.65 else { return }
        lastStreamSend = now
        let window = displayWindow(for: liveAssistantText, maxLines: 4)
        guard !window.isEmpty else { return }
        do {
            bitmap = OLEDRenderer.render(text: window, style: .full)
            try await NodeRedClient(baseURL: nodeRedURL).send(bitmap: bitmap, durationMs: 6000)
        } catch {
            log("DeepSeek OLED stream failed: \(error.localizedDescription)")
        }
    }

    private func displayWindow(for value: String, maxLines: Int) -> String {
        let lines = wrapForOLED(limitSentenceLength(value))
        return lines.suffix(maxLines).joined(separator: "\n")
    }

    private func limitSentenceLength(_ value: String) -> String {
        let separators = CharacterSet(charactersIn: "。！？!?；;\n")
        var output: [String] = []
        var current = ""
        for scalar in value.unicodeScalars {
            let ch = String(scalar)
            if separators.contains(scalar) {
                if !current.isEmpty { output.append(current) }
                current = ""
            } else {
                current += ch
                if current.count >= 12 {
                    output.append(current)
                    current = ""
                }
            }
        }
        if !current.isEmpty { output.append(current) }
        return output.joined(separator: "\n")
    }

    private func wrapForOLED(_ value: String) -> [String] {
        value
            .split(separator: "\n", omittingEmptySubsequences: false)
            .flatMap { line -> [String] in
                var chunks: [String] = []
                var current = ""
                for char in line {
                    current.append(char)
                    if current.count >= 9 {
                        chunks.append(current)
                        current = ""
                    }
                }
                if !current.isEmpty || chunks.isEmpty { chunks.append(current) }
                return chunks
            }
    }

    private func oledPerformanceText(_ snapshot: MacPerformanceSnapshot) -> String {
        let temp = snapshot.tempC.map { "\($0)C" } ?? "--"
        return """
        CPU \(snapshot.cpuPct)% \(temp)
        MEM \(snapshot.memPct)%
        \(String(format: "%.1f", snapshot.memoryUsedGB))/\(String(format: "%.0f", snapshot.memoryTotalGB))GB
        SSD \(Int(storagePct(snapshot)))%
        """
    }

    private func storagePct(_ snapshot: MacPerformanceSnapshot) -> Double {
        guard snapshot.storageTotalGB > 0 else { return 0 }
        return snapshot.storageUsedGB / snapshot.storageTotalGB * 100
    }

    private func formatPerformanceForTelegram(_ snapshot: MacPerformanceSnapshot) -> String {
        let temp = snapshot.tempC.map { "\($0)C" } ?? "unknown"
        return """
        卞恺 Mac Status
        CPU: \(snapshot.cpuPct)%
        Memory: \(snapshot.memPct)% (\(String(format: "%.1f", snapshot.memoryUsedGB))/\(String(format: "%.1f", snapshot.memoryTotalGB)) GB)
        Temp: \(temp)
        Storage: \(Int(storagePct(snapshot)))% used
        App: \(snapshot.app)
        """
    }

    private func pollTelegram(token: String) async {
        let client = TelegramClient(token: token)
        var offset = UserDefaults.standard.object(forKey: "telegramLastUpdateId") as? Int
        if let saved = offset {
            offset = saved + 1
            telegramLog("Telegram resume from update_id \(saved)")
        } else {
            do {
                let pending = try await client.getUpdates(offset: nil)
                if let latest = pending.map(\.updateId).max() {
                    UserDefaults.standard.set(latest, forKey: "telegramLastUpdateId")
                    offset = latest + 1
                    telegramLog("Telegram skipped \(pending.count) old update(s)")
                }
            } catch {
                telegramLog("Telegram initial sync failed: \(error.localizedDescription)")
            }
        }
        defer {
            telegramTask = nil
            isTelegramRunning = false
            isStartingTelegram = false
        }
        while !Task.isCancelled {
            do {
                let updates = try await client.getUpdates(offset: offset)
                for update in updates {
                    offset = update.updateId + 1
                    UserDefaults.standard.set(update.updateId, forKey: "telegramLastUpdateId")
                    guard let message = update.message, let text = message.text else { continue }
                    await handleTelegram(text: text, chatId: message.chat.id, client: client)
                }
            } catch {
                telegramLog("Telegram error: \(error.localizedDescription)")
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
    }

    private func handleTelegram(text: String, chatId: Int64, client: TelegramClient) async {
        if !telegramChatAllowed(chatId) {
            telegramLog("TG blocked chat_id \(chatId)")
            try? await client.sendMessage(chatId: chatId, text: "未授权 chat_id：\(chatId)")
            return
        }
        telegramLog("TG: \(text)")
        if text.hasPrefix("/show ") {
            let body = String(text.dropFirst(6))
            enqueueDisplayText(body, style: .bubble, durationMs: durationMs, source: .telegram)
            try? await client.sendMessage(chatId: chatId, text: "已显示到 OLED")
        } else if text.hasPrefix("/ask ") {
            prompt = String(text.dropFirst(5))
            await askDeepSeek()
            let reply = liveAssistantText.isEmpty ? "没有回复" : liveAssistantText
            try? await client.sendMessage(chatId: chatId, text: String(reply.prefix(900)))
        } else if text == "/status" {
            await refreshPerformance()
            await showPerformanceOnOLED()
            try? await client.sendMessage(chatId: chatId, text: formatPerformanceForTelegram(performance))
        } else if text == "/device" {
            await refreshDeviceStatus()
            try? await client.sendMessage(chatId: chatId, text: formatDeviceForTelegram(deviceStatus))
        } else if text == "/wake" || text == "/screen_on" {
            await handleTelegramWake(chatId: chatId, client: client)
        } else if text == "/screen_off" {
            await refreshDeviceStatus()
            guard deviceStatus.online else {
                try? await client.sendMessage(chatId: chatId, text: "设备离线，无法熄屏。可发送 /repair。")
                return
            }
            await screenOffDevice()
            try? await client.sendMessage(chatId: chatId, text: "OLED 已熄屏。")
        } else if text == "/repair" {
            await repairConnection()
            await refreshDeviceStatus()
            try? await client.sendMessage(chatId: chatId, text: deviceStatus.online ? "连接修复已完成，设备在线。" : "已尝试修复，但设备仍离线。请在 App 里检查配网。")
        } else if text == "/help" {
            try? await client.sendMessage(chatId: chatId, text: telegramHelpText)
        } else {
            try? await client.sendMessage(chatId: chatId, text: telegramHelpText)
        }
    }

    private var telegramHelpText: String {
        "命令：/show 文字｜/ask 问题｜/status｜/device｜/wake｜/screen_on｜/screen_off｜/repair"
    }

    private func handleTelegramWake(chatId: Int64, client: TelegramClient) async {
        await refreshDeviceStatus()
        guard deviceStatus.online else {
            try? await client.sendMessage(chatId: chatId, text: "设备当前离线，无法直接唤醒屏幕。可发送 /repair 或在 App 里点一键修复连接。")
            return
        }
        let wasOn = deviceStatus.screenOn == "true"
        await wakeDevice()
        await clearSceneDevice()
        enqueueDisplayText("你好\nOLED 已点亮", style: .bubble, durationMs: 6000, source: .telegram)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await refreshDeviceStatus()
        let reply = wasOn ? "小屏幕已经亮着，我帮你刷新了一下状态。" : "已唤醒小屏幕，OLED 已点亮。"
        try? await client.sendMessage(chatId: chatId, text: reply)
    }

    private func telegramChatAllowed(_ chatId: Int64) -> Bool {
        let allowed = telegramAllowedChatId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !allowed.isEmpty else { return true }
        return allowed
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains(String(chatId))
    }

    private func formatDeviceForTelegram(_ snapshot: DeviceStatusSnapshot) -> String {
        """
        Mac-esp32 Device
        Online: \(snapshot.online ? "yes" : "no")
        FW: \(snapshot.firmware)
        IP: \(snapshot.ip)
        Mood: \(snapshot.mood)
        Scene: \(snapshot.scene)
        Screen: \(snapshot.screenOn)
        Fan: \(snapshot.fanPct)%
        Net: \(snapshot.networkReason)
        """
    }

    private func telegramLog(_ message: String) {
        telegramLogs.insert(TelegramLogEntry(text: message), at: 0)
        telegramLogs = Array(telegramLogs.prefix(80))
        log(message)
    }

    private func savePreference(_ value: String, for key: String) {
        guard !isRestoringPreferences else { return }
        UserDefaults.standard.set(value, forKey: key)
    }

    private func savePreference(_ value: Int, for key: String) {
        guard !isRestoringPreferences else { return }
        UserDefaults.standard.set(value, forKey: key)
    }

    private func savePreference(_ value: Bool, for key: String) {
        guard !isRestoringPreferences else { return }
        UserDefaults.standard.set(value, forKey: key)
    }

    private func saveSecret(_ value: String, account: String) {
        guard !isRestoringPreferences else { return }
        KeychainStore.save(value, account: account)
    }
}
