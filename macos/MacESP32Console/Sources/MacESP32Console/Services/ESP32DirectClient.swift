import Foundation

struct ESP32DirectClient {
    var host: String

    func fetchOTAStatus() async throws -> OTAStatusSnapshot {
        let root = normalizedRoot()
        guard let url = URL(string: "\(root)/ota/status") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(OTAStatusSnapshot.self, from: data)
    }

    func uploadFirmware(fileURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        let root = normalizedRoot()
        guard let url = URL(string: "\(root)/ota/upload") else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/octet-stream", forHTTPHeaderField: "content-type")
        request.setValue(fileURL.lastPathComponent, forHTTPHeaderField: "x-firmware-name")

        progress(0.05)
        let (_, response) = try await URLSession.shared.upload(for: request, from: data)
        progress(1.0)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private func normalizedRoot() -> String {
        if host.hasPrefix("http://") || host.hasPrefix("https://") {
            return host.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return "http://\(host)"
    }
}
