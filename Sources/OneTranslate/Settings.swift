import Foundation
import Security

struct AppSettings: Sendable {
    var endpoint = "http://localhost:11434/v1/chat/completions"
    var apiKey = ""
    var model = "llama3.2"
    var sourceLanguage = "Auto"
    var targetLanguage = "English"
    var mode = "Elegant"
    var style = "Friendly"
    var reverseLanguage = "Source language"

    var reverseTarget: String {
        if reverseLanguage != "Source language" { return reverseLanguage }
        if sourceLanguage != "Auto" { return sourceLanguage }
        return Locale(identifier: "en").localizedString(forIdentifier: Locale.preferredLanguages.first ?? "en") ?? "English"
    }

    func direction(forSelection selected: Bool) -> (source: String, target: String) {
        selected ? ("Auto", reverseTarget) : (sourceLanguage, targetLanguage)
    }

    static let languages = [
        "English", "Chinese (Simplified)", "Chinese (Traditional)", "Japanese", "Korean", "French", "Spanish", "German",
        "Russian", "Arabic", "Portuguese", "Vietnamese", "Thai",
        "Indonesian", "Italian"
    ]

    static let modes = ["Direct", "Elegant"]
    static let styles = ["Formal", "Casual", "Friendly", "Direct"]

    init() {}

    init(defaults: UserDefaults) {
        endpoint = defaults.string(forKey: "endpoint") ?? endpoint
        apiKey = Keychain.read()
        model = defaults.string(forKey: "model") ?? model
        sourceLanguage = defaults.string(forKey: "sourceLanguage") ?? sourceLanguage
        targetLanguage = defaults.string(forKey: "targetLanguage") ?? targetLanguage
        mode = defaults.string(forKey: "mode") ?? mode
        style = defaults.string(forKey: "style") ?? style
        reverseLanguage = defaults.string(forKey: "reverseLanguage") ?? reverseLanguage
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(endpoint.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "endpoint")
        Keychain.save(apiKey)
        defaults.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "model")
        defaults.set(sourceLanguage, forKey: "sourceLanguage")
        defaults.set(targetLanguage, forKey: "targetLanguage")
        defaults.set(mode, forKey: "mode")
        defaults.set(style, forKey: "style")
        defaults.set(reverseLanguage, forKey: "reverseLanguage")
    }
}

private enum Keychain {
    private static let service = "local.onetranslate.app"
    private static let account = "translation-api-key"

    static func read() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func save(_ value: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        guard !value.isEmpty else {
            SecItemDelete(query as CFDictionary)
            return
        }
        let attributes = [kSecValueData as String: Data(value.utf8)]
        let result = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard result == errSecItemNotFound else { return }

        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }
}

enum TranslationError: LocalizedError {
    case invalidEndpoint
    case missingModel
    case httpStatus(Int)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Use an HTTPS endpoint, or HTTP on localhost for a local model. Do not include credentials in the URL."
        case .missingModel:
            return "Set a model name in Settings."
        case let .httpStatus(status):
            return "Translation server returned HTTP \(status). Check your endpoint, model, and API key."
        case .emptyResponse:
            return "The translation model returned no text."
        }
    }
}

struct TranslationService: Sendable {
    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
    private struct Message: Encodable {
        let role: String
        let content: String
    }

    private struct RequestBody: Encodable {
        let model: String
        let messages: [Message]
        let temperature: Double
        let stream: Bool
    }

    private struct ResponseBody: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String
            }

            let message: Message
        }

        let choices: [Choice]
    }

    func translate(_ text: String, settings: AppSettings) async throws -> String {
        guard let url = URL(string: settings.endpoint),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              url.user == nil, url.password == nil,
              scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host)) else {
            throw TranslationError.invalidEndpoint
        }

        let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw TranslationError.missingModel }

        let modeInstruction = settings.mode == "Direct"
            ? "Translate accurately and concisely. Preserve meaning, formatting, line breaks, names, numbers, and punctuation."
            : "Translate naturally so it sounds like a fluent native speaker. Preserve meaning, formatting, line breaks, names, numbers, and punctuation."
        let styleInstruction = "Use a \(settings.style.lowercased()) tone."
        let source = settings.sourceLanguage == "Auto" ? "the source language" : settings.sourceLanguage
        let system = "You are a careful translation assistant. Translate from \(source) to \(settings.targetLanguage). \(modeInstruction) \(styleInstruction) Return only the translated text, with no explanation or quotation marks."
        let user = "<text>\n\(text)\n</text>"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !settings.apiKey.isEmpty {
            request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(RequestBody(
            model: model,
            messages: [Message(role: "system", content: system), Message(role: "user", content: user)],
            temperature: settings.mode == "Direct" ? 0.1 : 0.4,
            stream: false
        ))

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TranslationError.httpStatus(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let content = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw TranslationError.emptyResponse
        }
        return content
    }
}
