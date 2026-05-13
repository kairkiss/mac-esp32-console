import Foundation

struct DeepSeekClient {
    var apiKey: String
    var model: String = "deepseek-chat"

    func streamReply(prompt: String, onDelta: @escaping @MainActor (String) -> Void) async throws {
        guard let url = URL(string: "https://api.deepseek.com/chat/completions") else {
            throw URLError(.badURL)
        }

        let systemPrompt = """
        你是卞恺的桌面 OLED 宠物屏幕助手。回复必须适合 128x64 单色小屏。
        严格要求：每句不超过 12 个中文字符；不要长段落；优先 1 到 4 行；语气温柔、简洁、有陪伴感。
        如果内容较长，请拆成很多短句，每句独立成行。
        """

        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "temperature": 0.7,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prompt]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }
            guard
                let data = payload.data(using: .utf8),
                let chunk = try? JSONDecoder().decode(DeepSeekStreamChunk.self, from: data)
            else { continue }
            let delta = chunk.choices.compactMap { $0.delta.content }.joined()
            if !delta.isEmpty {
                await onDelta(delta)
            }
        }
    }
}

private struct DeepSeekStreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }

        let delta: Delta
    }

    let choices: [Choice]
}
