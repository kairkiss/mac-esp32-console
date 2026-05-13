import SwiftUI

struct ContentView: View {
    @StateObject private var store = ConsoleStore()

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
        } detail: {
            DetailShellView(store: store)
        }
        .background(VisualEffectView(material: .windowBackground, blendingMode: .behindWindow))
        .task {
            store.startPerformanceLoop()
        }
        .sheet(isPresented: $store.setupWizardPresented) {
            SetupWizardView(store: store)
                .frame(width: 760, height: 620)
        }
    }
}

struct SidebarView: View {
    @ObservedObject var store: ConsoleStore

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $store.selection) {
                Section {
                    ForEach(ConsoleSection.allCases) { item in
                        HStack(spacing: 10) {
                            Image(systemName: item.systemImage)
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                Text(item.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .tag(item)
                    }
                } header: {
                    Text("Console")
                }
            }
            .listStyle(.sidebar)

            TelegramRemoteCard(store: store)
                .padding(14)
        }
    }
}

struct DetailShellView: View {
    @ObservedObject var store: ConsoleStore

    var body: some View {
        ZStack {
            VisualEffectView(material: .underWindowBackground, blendingMode: .withinWindow)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HeaderView(section: store.selection)

                    switch store.selection {
                    case .screen:
                        ScreenComposerPanel(store: store)
                    case .deepseek:
                        DeepSeekPanel(store: store)
                    case .performance:
                        PerformancePanel(store: store)
                    case .device:
                        DevicePanel(store: store)
                    case .diagnostics:
                        DiagnosticsPanel(store: store)
                    }
                }
                .padding(24)
                .frame(maxWidth: 980, alignment: .topLeading)
            }
        }
    }
}

private struct DiagnosticsPanel: View {
    @ObservedObject var store: ConsoleStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GlassPanel {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        PanelTitle("系统诊断", systemImage: "stethoscope")
                        Text("检查 Mosquitto、Node-RED、Hammerspoon、Mac 状态脚本、ESP32 在线状态和 Mac MQTT IP。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        if diagnosticReady {
                            Text("上次检查：\(store.diagnosticReport.updatedAt.formatted(date: .omitted, time: .standard)) · \(store.diagnosticReport.summary)")
                                .font(.caption)
                                .foregroundStyle(store.diagnosticReport.hasFailure ? .red : .secondary)
                        }
                    }
                    Spacer()
                    Button {
                        Task { await store.runDiagnostics() }
                    } label: {
                        if store.isDiagnosticsRunning {
                            ProgressView().controlSize(.small)
                        }
                        Label("运行检查", systemImage: "play.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(store.isDiagnosticsRunning)
                }
            }

            if !store.diagnosticReport.macIPs.isEmpty {
                GlassPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        PanelTitle("检测到的 Mac IP", systemImage: "network")
                        ForEach(store.diagnosticReport.macIPs, id: \.self) { ip in
                            HStack {
                                Text(ip)
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                                Button {
                                    store.applyDetectedMacIP(ip)
                                } label: {
                                    Label("设为 MQTT_HOST", systemImage: "checkmark.circle")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }

            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(store.diagnosticReport.items) { item in
                    DiagnosticRow(item: item)
                }
            }

            GlassPanel {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        PanelTitle("首次配置向导", systemImage: "wand.and.stars")
                        Text("重新打开分步设置：Node-RED、Wi-Fi/MQTT、DeepSeek、Telegram 和最终诊断。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        store.reopenSetupWizard()
                    } label: {
                        Label("打开向导", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.bordered)
                }
            }

            LogPanel(logs: store.logs)
        }
        .task {
            if store.diagnosticReport.items.isEmpty {
                await store.runDiagnostics()
            }
        }
    }

    private var diagnosticReady: Bool {
        !store.diagnosticReport.items.isEmpty
    }
}

private struct DiagnosticRow: View {
    let item: DiagnosticItem

    var body: some View {
        GlassPanel {
            HStack(alignment: .top, spacing: 12) {
                StatusPill(text: item.status.label, isOn: item.status == .pass)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(.headline)
                    Text(item.detail.isEmpty ? "--" : item.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if !item.fix.isEmpty {
                        Text(item.fix)
                            .font(.caption)
                            .foregroundStyle(item.status == .fail ? .red : .secondary)
                    }
                }
                Spacer()
            }
        }
    }
}

private struct SetupWizardView: View {
    @ObservedObject var store: ConsoleStore
    @State private var step = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mac-esp32 控制台设置")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text(stepTitle)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    store.finishSetupWizard()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .font(.title3)
                .foregroundStyle(.secondary)
            }
            .padding(24)

            Divider()

            TabView(selection: $step) {
                WizardNodeRedStep(store: store).tag(0)
                WizardNetworkStep(store: store).tag(1)
                WizardAIAndTelegramStep(store: store).tag(2)
                WizardFinishStep(store: store).tag(3)
            }
            .tabViewStyle(.automatic)
            .padding(24)

            Divider()

            HStack {
                Text("\(step + 1) / 4")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("上一步") { step = max(0, step - 1) }
                    .disabled(step == 0)
                Button(step == 3 ? "完成" : "下一步") {
                    if step == 3 {
                        store.finishSetupWizard()
                    } else {
                        step += 1
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
    }

    private var stepTitle: String {
        switch step {
        case 0: return "确认 Node-RED 和本机服务"
        case 1: return "配置 Wi-Fi、MQTT 和 ESP32"
        case 2: return "配置 DeepSeek 和 Telegram"
        default: return "运行诊断并完成"
        }
    }
}

private struct WizardNodeRedStep: View {
    @ObservedObject var store: ConsoleStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PanelTitle("Node-RED", systemImage: "point.3.connected.trianglepath.dotted")
            TextField("Node-RED URL", text: $store.nodeRedURL)
                .textFieldStyle(.roundedBorder)
            Text("默认是 http://127.0.0.1:1880。App 通过它发送 OLED bitmap、设备控制命令，并读取 ESP32 状态。")
                .foregroundStyle(.secondary)
            Button {
                Task { await store.runDiagnostics() }
            } label: {
                Label("测试本机服务", systemImage: "checkmark.seal")
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }
}

private struct WizardNetworkStep: View {
    @ObservedObject var store: ConsoleStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PanelTitle("Wi-Fi / MQTT", systemImage: "wifi")
            TextField("Wi-Fi SSID", text: $store.wifiSSID)
                .textFieldStyle(.roundedBorder)
            SecureField("Wi-Fi Password", text: $store.wifiPassword)
                .textFieldStyle(.roundedBorder)
            HStack {
                TextField("Mac MQTT IP", text: $store.macMqttHost)
                    .textFieldStyle(.roundedBorder)
                TextField("Port", value: $store.mqttPort, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
            }
            if !store.diagnosticReport.macIPs.isEmpty {
                HStack {
                    Text("检测到：")
                        .foregroundStyle(.secondary)
                    ForEach(store.diagnosticReport.macIPs, id: \.self) { ip in
                        Button(ip) { store.applyDetectedMacIP(ip) }
                    }
                }
            }
            Text("ESP32 MQTT_HOST 必须是 Mac 的局域网 IP，不能是 127.0.0.1。")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

private struct WizardAIAndTelegramStep: View {
    @ObservedObject var store: ConsoleStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PanelTitle("AI / Telegram", systemImage: "sparkles")
            SecureField("DeepSeek API Key", text: $store.deepSeekAPIKey)
                .textFieldStyle(.roundedBorder)
            TextField("DeepSeek Model", text: $store.deepSeekModel)
                .textFieldStyle(.roundedBorder)
            Divider()
            SecureField("Telegram Bot Token", text: $store.telegramToken)
                .textFieldStyle(.roundedBorder)
            TextField("允许的 chat_id，多个用逗号分隔", text: $store.telegramAllowedChatId)
                .textFieldStyle(.roundedBorder)
            Toggle("启动 App 后自动监听 Telegram", isOn: $store.telegramAutoStart)
                .toggleStyle(.checkbox)
            Text("API Key、Bot Token 和 Wi-Fi 密码保存到 macOS Keychain，不写入仓库。")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

private struct WizardFinishStep: View {
    @ObservedObject var store: ConsoleStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                PanelTitle("最终检查", systemImage: "checklist")
                Spacer()
                Button {
                    Task { await store.runDiagnostics() }
                } label: {
                    Label("运行诊断", systemImage: "play.circle")
                }
                .buttonStyle(.borderedProminent)
            }
            Text(store.diagnosticReport.items.isEmpty ? "还没有运行诊断。" : store.diagnosticReport.summary)
                .font(.title3.weight(.semibold))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(store.diagnosticReport.items) { item in
                        HStack {
                            StatusPill(text: item.status.label, isOn: item.status == .pass)
                            VStack(alignment: .leading) {
                                Text(item.title)
                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                        }
                        .padding(8)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .task {
            if store.diagnosticReport.items.isEmpty {
                await store.runDiagnostics()
            }
        }
    }
}

private struct HeaderView: View {
    let section: ConsoleSection

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: section.systemImage)
                .font(.system(size: 28, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(section.title)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text(section.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

private struct ScreenComposerPanel: View {
    @ObservedObject var store: ConsoleStore

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            GlassPanel {
                VStack(alignment: .leading, spacing: 14) {
                    PanelTitle("输入内容", systemImage: "text.cursor")

                    TextEditor(text: $store.text)
                        .font(.system(size: 16))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 220)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.quaternary, lineWidth: 1)
                        }

                    Picker("样式", selection: $store.style) {
                        ForEach(ConsoleStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Label("显示时长", systemImage: "timer")
                            .foregroundStyle(.secondary)
                        Spacer()
                        TextField("Duration", value: $store.durationMs, format: .number)
                            .frame(width: 96)
                            .textFieldStyle(.roundedBorder)
                        Text("ms").foregroundStyle(.secondary)
                    }

                    Button {
                        Task { await store.sendToDevice() }
                    } label: {
                        Label("发送到开发板", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(store.isSending)
                }
            }

            VStack(spacing: 18) {
                PreviewCanvasView(image: store.bitmap.previewImage)
                    .onChange(of: store.text) { _ in store.renderPreview() }
                    .onChange(of: store.style) { _ in store.renderPreview() }

                DisplayQueuePanel(store: store)
                LogPanel(logs: store.logs)
            }
            .frame(minWidth: 360)
        }
    }
}

private struct DeepSeekPanel: View {
    @ObservedObject var store: ConsoleStore

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            GlassPanel {
                VStack(alignment: .leading, spacing: 14) {
                    PanelTitle("DeepSeek 设置", systemImage: "key")

                    SecureField("DeepSeek API Key", text: $store.deepSeekAPIKey)
                        .textFieldStyle(.roundedBorder)

                    TextField("Model", text: $store.deepSeekModel)
                        .textFieldStyle(.roundedBorder)

                    TextEditor(text: $store.prompt)
                        .font(.system(size: 16))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 150)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.quaternary, lineWidth: 1)
                        }

                    Button {
                        Task { await store.askDeepSeek() }
                    } label: {
                        if store.isDeepSeekRunning {
                            ProgressView().controlSize(.small)
                        }
                        Text("发送并流式上屏")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(store.isDeepSeekRunning || store.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Text("回复会被限制为短句，并持续滚动到 OLED。API Key 只在本机 App 内输入使用。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 330)

            GlassPanel {
                VStack(alignment: .leading, spacing: 14) {
                    PanelTitle("对话输出", systemImage: "bubble.left.and.bubble.right")
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(store.chatMessages) { message in
                                ChatBubble(message: message)
                            }
                        }
                    }
                    .frame(minHeight: 360)
                }
            }
        }
    }
}

private struct PerformancePanel: View {
    @ObservedObject var store: ConsoleStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
                MetricCard(title: "CPU", value: "\(store.performance.cpuPct)%", detail: "当前前台：\(store.performance.app)", systemImage: "cpu")
                MetricCard(title: "CPU 温度", value: store.performance.tempC.map { "\($0)C" } ?? "--", detail: store.performance.thermalSource, systemImage: "thermometer.medium")
                MetricCard(title: "内存", value: "\(store.performance.memPct)%", detail: "\(String(format: "%.1f", store.performance.memoryUsedGB)) / \(String(format: "%.1f", store.performance.memoryTotalGB)) GB", systemImage: "memorychip")
                MetricCard(title: "存储", value: "\(Int(storagePct(store.performance)))%", detail: "\(String(format: "%.0f", store.performance.storageUsedGB)) / \(String(format: "%.0f", store.performance.storageTotalGB)) GB", systemImage: "internaldrive")
            }

            GlassPanel {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        PanelTitle("Mac 当前消息", systemImage: "macbook")
                        Text("更新时间 \(store.performance.updatedAt.formatted(date: .omitted, time: .standard))，idle \(store.performance.idleS)s")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await store.refreshPerformance() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    Button {
                        Task { await store.showPerformanceOnOLED() }
                    } label: {
                        Label("显示到 OLED", systemImage: "display")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            LogPanel(logs: store.logs)
        }
    }

    private func storagePct(_ snapshot: MacPerformanceSnapshot) -> Double {
        guard snapshot.storageTotalGB > 0 else { return 0 }
        return snapshot.storageUsedGB / snapshot.storageTotalGB * 100
    }
}

private struct DevicePanel: View {
    @ObservedObject var store: ConsoleStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DeviceStatusPanel(store: store)

            HStack(alignment: .top, spacing: 18) {
                GlassPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        PanelTitle("设备控制", systemImage: "power")
                        Text("这些是软控制：ESP32 必须供电。物理断电后 App 不能隔空开机。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Button {
                                Task { await store.wakeDevice() }
                            } label: {
                                Label("唤醒屏幕", systemImage: "sun.max")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                Task { await store.startConfigPortal() }
                            } label: {
                                Label("开启配网热点", systemImage: "wifi.router")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }

                        HStack {
                            Button {
                                Task { await store.screenOffDevice() }
                            } label: {
                                Label("熄屏", systemImage: "moon")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                Task { await store.clearSceneDevice() }
                            } label: {
                                Label("回到表情", systemImage: "face.smiling")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }

                        Button {
                            Task { await store.testPatternDevice() }
                        } label: {
                            Label("显示测试图", systemImage: "rectangle.checkered")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            Task { await store.rebootDevice() }
                        } label: {
                            Label("重启 ESP32", systemImage: "restart")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                GlassPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        PanelTitle("当前 Mac MQTT", systemImage: "network")
                        TextField("Mac MQTT IP", text: $store.macMqttHost)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Text("Port").foregroundStyle(.secondary)
                            TextField("1883", value: $store.mqttPort, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                        }
                        Text("Mac 重启或换网络后，如果 IP 变化，把这里改成当前 Mac 局域网 IP。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            GlassPanel {
                VStack(alignment: .leading, spacing: 14) {
                    PanelTitle("Wi-Fi / MQTT 配网", systemImage: "wifi")
                    TextField("Wi-Fi SSID", text: $store.wifiSSID)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Wi-Fi Password", text: $store.wifiPassword)
                        .textFieldStyle(.roundedBorder)

                    Divider()

                    TextField("Setup Portal URL", text: $store.configPortalURL)
                        .textFieldStyle(.roundedBorder)
                    Text("如果设备离线：先用 Mac 连接 Wi-Fi 热点 MacESP32-Setup，密码 macesp32，然后点“通过配置热点写入”。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button {
                            Task { await store.applyNetworkConfigOnline() }
                        } label: {
                            Label("在线写入并重启", systemImage: "antenna.radiowaves.left.and.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            Task { await store.applyNetworkConfigDirect() }
                        } label: {
                            Label("通过配置热点写入", systemImage: "dot.radiowaves.left.and.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            store.openConfigPortal()
                        } label: {
                            Label("打开网页", systemImage: "safari")
                        }
                        .buttonStyle(.bordered)
                    }
                    .disabled(store.isDeviceBusy)
                }
            }

            LogPanel(logs: store.logs)
        }
    }
}

private struct DeviceStatusPanel: View {
    @ObservedObject var store: ConsoleStore

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    PanelTitle("设备状态", systemImage: "dot.radiowaves.left.and.right")
                    Spacer()
                    StatusPill(text: store.deviceStatus.online ? "ONLINE" : "OFFLINE", isOn: store.deviceStatus.online)
                    Button {
                        Task { await store.refreshDeviceStatus() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.isDeviceStatusRefreshing)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 10)], spacing: 10) {
                    DeviceFact(title: "Firmware", value: store.deviceStatus.firmware)
                    DeviceFact(title: "IP", value: store.deviceStatus.ip)
                    DeviceFact(title: "MQTT", value: store.deviceStatus.mqttConnected)
                    DeviceFact(title: "MacLink", value: store.deviceStatus.macLink)
                    DeviceFact(title: "Mood", value: store.deviceStatus.mood)
                    DeviceFact(title: "Scene", value: store.deviceStatus.scene)
                    DeviceFact(title: "Screen", value: store.deviceStatus.screenOn)
                    DeviceFact(title: "Fan", value: "\(store.deviceStatus.fanPct)%")
                }

                Text("Reason: \(store.deviceStatus.reason)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

private struct DisplayQueuePanel: View {
    @ObservedObject var store: ConsoleStore

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    PanelTitle("显示队列", systemImage: "rectangle.stack")
                    Spacer()
                    Button {
                        store.clearDisplayQueue()
                    } label: {
                        Label("清空", systemImage: "xmark.circle")
                    }
                    .disabled(store.displayQueue.isEmpty)
                }

                if let active = store.activeDisplayItem {
                    HStack {
                        StatusPill(text: "PLAYING", isOn: true)
                        Text("\(active.source.label)：\(active.preview)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Text("当前无播放任务")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !store.displayQueue.isEmpty {
                    ForEach(store.displayQueue.prefix(4)) { item in
                        HStack {
                            Text(item.source.label)
                                .font(.caption.weight(.semibold))
                                .frame(width: 68, alignment: .leading)
                            Text(item.preview)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text("\(item.durationMs / 1000)s")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }
}

private struct TelegramRemoteCard: View {
    @ObservedObject var store: ConsoleStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Telegram Remote", systemImage: "paperplane.circle")
                .font(.headline)

            SecureField("Bot token", text: $store.telegramToken)
                .textFieldStyle(.roundedBorder)

            TextField("允许的 chat_id，多个用逗号分隔", text: $store.telegramAllowedChatId)
                .textFieldStyle(.roundedBorder)

            Toggle("启动 App 后自动监听", isOn: $store.telegramAutoStart)
                .toggleStyle(.checkbox)

            Button {
                store.toggleTelegram()
            } label: {
                Label(store.isTelegramRunning ? "停止监听" : "开始监听", systemImage: store.isTelegramRunning ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Text("/show 文字  /ask 问题  /status  /device  /wake")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(store.telegramLogs) { entry in
                        Text(entry.text)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .frame(height: 88)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.quaternary)
        }
    }
}

private struct StatusPill: View {
    let text: String
    let isOn: Bool

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((isOn ? Color.green : Color.secondary).opacity(0.16), in: Capsule())
            .foregroundStyle(isOn ? .green : .secondary)
    }
}

private struct DeviceFact: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "--" : value)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct GlassPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(.white.opacity(0.16), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
    }
}

private struct PanelTitle: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 16, weight: .semibold))
    }
}

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .font(.system(size: 14))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(background, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(message.role == .system ? .secondary : .primary)
            if message.role != .user { Spacer(minLength: 40) }
        }
    }

    private var background: AnyShapeStyle {
        switch message.role {
        case .user: return AnyShapeStyle(.blue.opacity(0.18))
        case .assistant: return AnyShapeStyle(.regularMaterial)
        case .system: return AnyShapeStyle(.quaternary)
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(title, systemImage: systemImage)
                        .font(.headline)
                    Spacer()
                }
                Text(value)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

private struct LogPanel: View {
    let logs: [String]

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                PanelTitle("运行日志", systemImage: "list.bullet.rectangle")
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(logs.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(minHeight: 150)
            }
        }
    }
}
