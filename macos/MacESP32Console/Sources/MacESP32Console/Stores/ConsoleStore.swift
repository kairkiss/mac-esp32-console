import AppKit
import Foundation

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

    @Published var telegramToken = "" { didSet { saveSecret(telegramToken, account: "telegramToken") } }
    @Published var telegramAllowedChatId = "" { didSet { savePreference(telegramAllowedChatId, for: "telegramAllowedChatId") } }
    @Published var telegramAutoStart = false { didSet { savePreference(telegramAutoStart, for: "telegramAutoStart") } }
    @Published var isTelegramRunning = false
    @Published var telegramLogs: [TelegramLogEntry] = []

    @Published var deviceStatus = DeviceStatusSnapshot()
    @Published var isDeviceStatusRefreshing = false
    @Published var displayQueue: [DisplayQueueItem] = []
    @Published var activeDisplayItem: DisplayQueueItem?

    @Published var wifiSSID = "" { didSet { savePreference(wifiSSID, for: "wifiSSID") } }
    @Published var wifiPassword = "" { didSet { saveSecret(wifiPassword, account: "wifiPassword") } }
    @Published var macMqttHost = "192.168.1.100" { didSet { savePreference(macMqttHost, for: "macMqttHost") } }
    @Published var mqttPort = 1883 { didSet { savePreference(mqttPort, for: "mqttPort") } }
    @Published var configPortalURL = "http://192.168.4.1" { didSet { savePreference(configPortalURL, for: "configPortalURL") } }
    @Published var isDeviceBusy = false

    @Published var logs: [String] = []

    private var telegramTask: Task<Void, Never>?
    private var performanceTask: Task<Void, Never>?
    private var displayQueueTask: Task<Void, Never>?
    private var lastStreamSend = Date.distantPast
    private var isRestoringPreferences = true

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
        wifiSSID = defaults.string(forKey: "wifiSSID") ?? wifiSSID
        wifiPassword = KeychainStore.read("wifiPassword")
        macMqttHost = defaults.string(forKey: "macMqttHost") ?? macMqttHost
        mqttPort = defaults.object(forKey: "mqttPort") as? Int ?? mqttPort
        configPortalURL = defaults.string(forKey: "configPortalURL") ?? configPortalURL
        bitmap = OLEDRenderer.render(text: text, style: style)
        isRestoringPreferences = false
        log("Console ready")
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
                await self?.refreshDeviceStatus()
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
        let status = oledPerformanceText(performance)
        enqueueDisplayText(status, style: .full, durationMs: 6000, source: .performance)
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

        isTelegramRunning = true
        telegramLog("Telegram polling started")
        telegramTask = Task { [weak self] in
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
        var offset: Int?
        while !Task.isCancelled {
            do {
                let updates = try await client.getUpdates(offset: offset)
                for update in updates {
                    offset = update.updateId + 1
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
        } else if text == "/wake" {
            await wakeDevice()
            try? await client.sendMessage(chatId: chatId, text: "已发送唤醒命令")
        } else {
            try? await client.sendMessage(
                chatId: chatId,
                text: "命令：\n/show 文字\n/ask 问题\n/status\n/device\n/wake"
            )
        }
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
