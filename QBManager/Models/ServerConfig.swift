import Foundation
import Network

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

enum ProxyKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case http, socks5

    var id: String { rawValue }
    var label: String { self == .http ? "HTTP" : "SOCKS5" }
}

/// 連到這台伺服器時強制經過的代理。系統代理會略過區網與 Tailscale 等位址，
/// 開啟後這些位址的請求也一律交給代理（例如 Surge、Shadowrocket、Clash 在本機開的代理埠）
struct ProxySettings: Codable, Hashable, Sendable {
    var enabled = false
    var kind: ProxyKind = .http
    var host = "127.0.0.1"
    var port = ""

    /// 設定完整時的代理端點；未開啟或位址、連接埠不完整時為 nil
    var endpoint: NWEndpoint? {
        let h = host.trimmingCharacters(in: .whitespaces)
        guard enabled, !h.isEmpty, let p = UInt16(port.trimmingCharacters(in: .whitespaces)), p > 0,
              let nwPort = NWEndpoint.Port(rawValue: p) else { return nil }
        return .hostPort(host: NWEndpoint.Host(h), port: nwPort)
    }

    /// 開啟了但位址或連接埠不完整
    var isIncomplete: Bool { enabled && endpoint == nil }

    /// 系統目前的 HTTP 代理（例如代理 App 開著時的 127.0.0.1:6152）
    static var system: (host: String, port: Int)? {
        guard let dict = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any],
              (dict["HTTPEnable"] as? Int) == 1,
              let host = dict["HTTPProxy"] as? String, !host.isEmpty,
              let port = dict["HTTPPort"] as? Int else { return nil }
        return (host, port)
    }
}

struct ServerConfig: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String = ""
    var url: String = ""
    var username: String = "admin"
    var authMode: AuthMode = .password
    var trustSelfSigned: Bool = false
    var proxy = ProxySettings()

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

// 舊版存的設定沒有新欄位，缺少的一律用預設值，避免升級後伺服器清單讀不出來
extension ServerConfig {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? "admin"
        authMode = try c.decodeIfPresent(AuthMode.self, forKey: .authMode) ?? .password
        trustSelfSigned = try c.decodeIfPresent(Bool.self, forKey: .trustSelfSigned) ?? false
        proxy = try c.decodeIfPresent(ProxySettings.self, forKey: .proxy) ?? ProxySettings()
    }
}
