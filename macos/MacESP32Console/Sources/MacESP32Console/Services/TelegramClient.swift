import Foundation

struct TelegramClient {
    var token: String

    func getUpdates(offset: Int?) async throws -> [TelegramUpdate] {
        var components = URLComponents(string: "https://api.telegram.org/bot\(token)/getUpdates")!
        var items = [
            URLQueryItem(name: "timeout", value: "20"),
            URLQueryItem(name: "allowed_updates", value: "[\"message\"]")
        ]
        if let offset {
            items.append(URLQueryItem(name: "offset", value: String(offset)))
        }
        components.queryItems = items
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        try validate(response)
        return try JSONDecoder().decode(TelegramUpdatesResponse.self, from: data).result
    }

    func sendMessage(chatId: Int64, text: String) async throws {
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/sendMessage") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "chat_id": chatId,
            "text": text
        ])
        let (_, response) = try await URLSession.shared.data(for: request)
        try validate(response)
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}

struct TelegramUpdatesResponse: Decodable {
    let result: [TelegramUpdate]
}

struct TelegramUpdate: Decodable {
    let updateId: Int
    let message: TelegramMessage?

    enum CodingKeys: String, CodingKey {
        case updateId = "update_id"
        case message
    }
}

struct TelegramMessage: Decodable {
    let chat: TelegramChat
    let text: String?
}

struct TelegramChat: Decodable {
    let id: Int64
}
