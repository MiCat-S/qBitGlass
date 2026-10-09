import Foundation

enum AuthMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case password, apiKey, none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .password: return "帳號密碼"
        case .apiKey: return "API Key"
        case .none: return "免驗證"
        }
    }
}

struct ServerConfig: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String = ""
    var url: String = ""
    var username: String = "admin"
    var authMode: AuthMode = .password
    var trustSelfSigned: Bool = false

    var displayName: String { name.isEmpty ? (baseURL?.host ?? url) : name }

    /// 正規化後的 WebUI 根網址，可含子路徑（反向代理），結尾不含 /。
    var baseURL: URL? {
        var s = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        guard let u = URL(string: s), let scheme = u.scheme?.lowercased(),
              scheme == "http" || scheme == "https", u.host != nil else { return nil }
        return u
    }

    var secretAccount: String {
        "\(id.uuidString).\(authMode == .apiKey ? "apikey" : "password")"
    }
}
