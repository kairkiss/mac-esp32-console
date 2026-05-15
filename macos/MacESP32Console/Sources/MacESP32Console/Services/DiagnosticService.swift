import Foundation

struct DiagnosticService {
    var nodeRedURL: String

    func run(deviceStatus: DeviceStatusSnapshot) async -> DiagnosticReport {
        async let mosquitto = checkCommand("Mosquitto", command: "/usr/bin/env", arguments: ["which", "mosquitto"])
        async let nodeRedCommand = checkCommand("Node-RED CLI", command: "/usr/bin/env", arguments: ["which", "node-red"])
        async let arduinoCLI = checkArduinoCLI()
        async let hammerspoon = checkProcess("Hammerspoon", pattern: "Hammerspoon")
        async let nodeRedProcess = checkProcess("Node-RED process", pattern: "node-red")
        async let brokerPort = checkPort(host: "127.0.0.1", port: 1883)
        async let configuredBrokerPort = checkConfiguredBrokerPort()
        async let nodeRedHTTP = checkNodeRedHTTP()
        async let setupPortal = checkSetupPortal()
        async let macScript = checkMacStatusScript()
        async let ips = localIPAddresses()

        var items = await [
            mosquitto,
            nodeRedCommand,
            arduinoCLI,
            hammerspoon,
            nodeRedProcess,
            brokerPort,
            configuredBrokerPort,
            nodeRedHTTP,
            setupPortal,
            macScript,
            checkConfiguredMQTTHost(await ips),
            checkESP32(deviceStatus)
        ]

        if deviceStatus.online && deviceStatus.macLink != "ok" {
            items.append(DiagnosticItem(
                title: "ESP32 MacLink",
                status: .warn,
                detail: "ESP32 在线，但 MacLink 当前为 \(deviceStatus.macLink)",
                fix: "等待 Node-RED 发布 mac/state；如果持续异常，检查 Hammerspoon 和 macbrain_status_v6.sh。"
            ))
        }

        return DiagnosticReport(items: items, macIPs: await ips, updatedAt: Date())
    }

    private func checkCommand(_ title: String, command: String, arguments: [String]) async -> DiagnosticItem {
        let result = await runCommand(command, arguments: arguments)
        if result.exitCode == 0 {
            return DiagnosticItem(title: title, status: .pass, detail: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), fix: "")
        }
        return DiagnosticItem(title: title, status: .warn, detail: "未在 PATH 中找到", fix: "如果你需要相关功能，请安装并确保命令在 PATH 中。")
    }

    private func checkArduinoCLI() async -> DiagnosticItem {
        let result = await runCommand("/usr/bin/env", arguments: ["which", "arduino-cli"])
        if result.exitCode == 0 {
            return DiagnosticItem(title: "Arduino CLI", status: .pass, detail: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), fix: "")
        }
        let bundled = "/Applications/Arduino IDE.app/Contents/Resources/app/lib/backend/resources/arduino-cli"
        if FileManager.default.isExecutableFile(atPath: bundled) {
            return DiagnosticItem(title: "Arduino CLI", status: .pass, detail: bundled, fix: "")
        }
        return DiagnosticItem(title: "Arduino CLI", status: .warn, detail: "未在 PATH 或 Arduino IDE 内置路径找到", fix: "安装 Arduino CLI，或安装 Arduino IDE。")
    }

    private func checkProcess(_ title: String, pattern: String) async -> DiagnosticItem {
        let result = await runCommand("/usr/bin/pgrep", arguments: ["-fl", pattern])
        if result.exitCode == 0 {
            return DiagnosticItem(title: title, status: .pass, detail: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), fix: "")
        }
        return DiagnosticItem(title: title, status: .fail, detail: "未发现运行进程", fix: "启动 \(pattern)，或检查 launchd service 是否正常。")
    }

    private func checkPort(host: String, port: Int) async -> DiagnosticItem {
        let result = await runCommand("/usr/bin/nc", arguments: ["-z", "-G", "2", host, String(port)])
        if result.exitCode == 0 {
            return DiagnosticItem(title: "MQTT broker", status: .pass, detail: "\(host):\(port) 可连接", fix: "")
        }
        return DiagnosticItem(title: "MQTT broker", status: .fail, detail: "\(host):\(port) 不可连接", fix: "启动 Mosquitto，并确认监听 1883。")
    }

    private func checkNodeRedHTTP() async -> DiagnosticItem {
        do {
            _ = try await NodeRedClient(baseURL: nodeRedURL).fetchDeviceStatus()
            return DiagnosticItem(title: "Node-RED HTTP", status: .pass, detail: "\(nodeRedURL)/mac-esp32/console/status 正常", fix: "")
        } catch {
            return DiagnosticItem(title: "Node-RED HTTP", status: .fail, detail: error.localizedDescription, fix: "确认 Node-RED 已启动，并部署 v6.5 flow。")
        }
    }

    private func checkConfiguredBrokerPort() async -> DiagnosticItem {
        let host = UserDefaults.standard.string(forKey: "macMqttHost") ?? "192.168.1.100"
        let port = UserDefaults.standard.object(forKey: "mqttPort") as? Int ?? 1883
        let result = await runCommand("/usr/bin/nc", arguments: ["-z", "-G", "2", host, String(port)])
        if result.exitCode == 0 {
            return DiagnosticItem(title: "MQTT LAN endpoint", status: .pass, detail: "\(host):\(port) 可连接", fix: "")
        }
        return DiagnosticItem(
            title: "MQTT LAN endpoint",
            status: .fail,
            detail: "\(host):\(port) 不可连接",
            fix: "ESP32 必须访问 Mac 的局域网 IP。确认 Mac IP、Mosquitto 监听 0.0.0.0:1883，且 Mac 防火墙未阻挡。"
        )
    }

    private func checkSetupPortal() async -> DiagnosticItem {
        let root = UserDefaults.standard.string(forKey: "configPortalURL") ?? "http://192.168.4.1"
        guard let url = URL(string: root.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/status") else {
            return DiagnosticItem(title: "ESP32 setup portal", status: .warn, detail: "配置热点 URL 无效", fix: "默认应为 http://192.168.4.1")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.5
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let text = String(data: data, encoding: .utf8) ?? "OK"
            return DiagnosticItem(title: "ESP32 setup portal", status: .pass, detail: text.prefixText(120), fix: "")
        } catch {
            return DiagnosticItem(
                title: "ESP32 setup portal",
                status: .warn,
                detail: "当前不可访问：\(error.localizedDescription)",
                fix: "只有 Mac 连接到 MacESP32-Setup 热点，或 ESP32 AP+STA 正常开启时才可访问。"
            )
        }
    }

    private func checkMacStatusScript() async -> DiagnosticItem {
        let script = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("bin/macbrain_status_v6.sh").path
        guard FileManager.default.isExecutableFile(atPath: script) else {
            return DiagnosticItem(title: "Mac 状态脚本", status: .fail, detail: "\(script) 不存在或不可执行", fix: "复制 mac/macbrain_status_v6.sh 到 ~/bin 并 chmod +x。")
        }
        let result = await runCommand(script, arguments: [])
        guard result.exitCode == 0, let data = result.stdout.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) != nil else {
            return DiagnosticItem(title: "Mac 状态脚本", status: .fail, detail: "输出不是合法 JSON", fix: "直接运行 ~/bin/macbrain_status_v6.sh 查看错误。")
        }
        return DiagnosticItem(title: "Mac 状态脚本", status: .pass, detail: "JSON 输出正常", fix: "")
    }

    private func checkConfiguredMQTTHost(_ ips: [String]) -> DiagnosticItem {
        let host = UserDefaults.standard.string(forKey: "macMqttHost") ?? "192.168.1.100"
        if ips.contains(host) {
            return DiagnosticItem(title: "Mac MQTT IP", status: .pass, detail: "配置值 \(host) 是当前 Mac IP", fix: "")
        }
        let detail = ips.isEmpty ? "未识别到局域网 IP；当前配置 \(host)" : "当前配置 \(host)，本机 IP：\(ips.joined(separator: ", "))"
        return DiagnosticItem(title: "Mac MQTT IP", status: .warn, detail: detail, fix: "如果 ESP32 连不上 MQTT，把 App 中 Mac MQTT IP 改成当前局域网 IP。")
    }

    private func checkESP32(_ status: DeviceStatusSnapshot) -> DiagnosticItem {
        if status.online {
            return DiagnosticItem(title: "ESP32", status: .pass, detail: "在线，IP \(status.ip)，fw \(status.firmware)", fix: "")
        }
        return DiagnosticItem(title: "ESP32", status: .fail, detail: "未在线或状态过期", fix: "确认 ESP32 供电、Wi-Fi、MQTT_HOST，必要时使用配网热点。")
    }

    private func localIPAddresses() async -> [String] {
        let result = await runCommand("/sbin/ifconfig", arguments: [])
        let pattern = #"inet (192\.168\.\d+\.\d+|10\.\d+\.\d+\.\d+|172\.(1[6-9]|2\d|3[0-1])\.\d+\.\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(result.stdout.startIndex..<result.stdout.endIndex, in: result.stdout)
        return regex.matches(in: result.stdout, range: range).compactMap { match in
            guard let r = Range(match.range(at: 1), in: result.stdout) else { return nil }
            return String(result.stdout[r])
        }
    }

    private func runCommand(_ command: String, arguments: [String]) async -> CommandResult {
        await Task.detached {
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments
            process.standardOutput = stdout
            process.standardError = stderr
            do {
                try process.run()
                process.waitUntilExit()
                let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                return CommandResult(exitCode: process.terminationStatus, stdout: out, stderr: err)
            } catch {
                return CommandResult(exitCode: 127, stdout: "", stderr: error.localizedDescription)
            }
        }.value
    }
}

private struct CommandResult {
    var exitCode: Int32
    var stdout: String
    var stderr: String
}

private extension StringProtocol {
    func prefixText(_ length: Int) -> String {
        let result = String(prefix(length))
        return count > length ? result + "..." : result
    }
}
