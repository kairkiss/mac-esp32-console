import Foundation

struct NodeRedClient {
    var baseURL: String

    func send(bitmap: OLEDBitmap, durationMs: Int) async throws {
        let root = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(root)/mac-esp32/console/bitmap") else {
            throw URLError(.badURL)
        }

        let payload = BitmapCommand(
            v: 1,
            id: bitmap.id,
            w: OLEDRenderer.width,
            h: OLEDRenderer.height,
            format: "1bpp",
            encoding: "base64",
            durationMs: durationMs,
            data: bitmap.base64
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    func sendRenderedText(_ text: String, style: ConsoleStyle, durationMs: Int) async throws {
        let bitmap = OLEDRenderer.render(text: text, style: style)
        try await send(bitmap: bitmap, durationMs: durationMs)
    }

    func sendScene(_ scene: String, durationMs: Int, source: String) async throws {
        let root = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(root)/mac-esp32/console/scene") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(SceneCommand(v: 1, scene: scene, durationMs: durationMs, source: source))
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    func sendPages(_ pages: [OLEDBitmap], durationMs: Int, source: String) async throws {
        guard !pages.isEmpty else { return }
        let root = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(root)/mac-esp32/console/bitmap/page") else { throw URLError(.badURL) }
        let batchId = "msg-\(Int(Date().timeIntervalSince1970))"
        for (index, page) in pages.enumerated() {
            let payload = BitmapPageCommand(
                v: 1,
                id: batchId,
                pageIndex: index,
                pageCount: pages.count,
                w: OLEDRenderer.width,
                h: OLEDRenderer.height,
                format: "1bpp",
                encoding: "base64",
                durationMs: max(6000, durationMs),
                source: source,
                data: page.base64
            )
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try JSONEncoder().encode(payload)
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            try await Task.sleep(nanoseconds: 120_000_000)
        }
    }

    func sendDeviceAction(_ action: String) async throws {
        let root = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(root)/mac-esp32/console/device") else { throw URLError(.badURL) }
        try await post(DeviceCommand(v: 1, action: action), to: url)
    }

    func sendNetworkConfig(ssid: String, password: String, mqttHost: String, mqttPort: Int) async throws {
        let root = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(root)/mac-esp32/console/netconfig") else { throw URLError(.badURL) }
        try await post(NetworkConfigCommand(v: 1, ssid: ssid, password: password, mqttHost: mqttHost, mqttPort: mqttPort), to: url)
    }

    func sendNetworkConfigDirect(configURL: String, ssid: String, password: String, mqttHost: String, mqttPort: Int) async throws {
        let root = configURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(root)/config") else { throw URLError(.badURL) }
        try await post(NetworkConfigCommand(v: 1, ssid: ssid, password: password, mqttHost: mqttHost, mqttPort: mqttPort), to: url)
    }

    func fetchDeviceStatus() async throws -> DeviceStatusSnapshot {
        let root = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(root)/mac-esp32/console/status") else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let online = raw["online"] as? Bool ?? false
        let petState = stringify(raw["pet_state"] as? [String: Any] ?? [:])
        let macState = stringify(raw["mac_state"] as? [String: Any] ?? [:])
        return DeviceStatusSnapshot(online: online, petState: petState, macState: macState, updatedAt: Date())
    }

    private func post<T: Encodable>(_ payload: T, to url: URL) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(payload)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private func stringify(_ value: [String: Any]) -> [String: String] {
        value.reduce(into: [:]) { result, pair in
            switch pair.value {
            case let string as String:
                result[pair.key] = string
            case let bool as Bool:
                result[pair.key] = bool ? "true" : "false"
            case let number as NSNumber:
                result[pair.key] = number.stringValue
            case _ as NSNull:
                result[pair.key] = "null"
            default:
                result[pair.key] = String(describing: pair.value)
            }
        }
    }
}
