import Foundation

enum QBError: LocalizedError {
    case invalidURL
    case loginFailed
    case banned
    case forbidden
    case notFound
    case conflict(String)
    case invalidTorrent
    case addFailed
    case badRequest(String)
    case http(Int, String)
    case badResponse
    /// 伺服器要求轉址；附上建議改用的 WebUI 根網址
    case redirected(String)
    /// 被 qBittorrent 的主機標頭驗證擋下（401）
    case hostRejected
    case apiKeyRejected
    case notQBittorrent(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "伺服器網址無效"
        case .loginFailed: return "登入失敗：帳號或密碼錯誤"
        case .banned: return "此 IP 因多次登入失敗已被 qBittorrent 封鎖，請稍後再試"
        case .forbidden: return "沒有權限（403），請確認帳號密碼或 API Key"
        case .notFound: return "找不到該種子或 API（404）"
        case .conflict(let m): return m.isEmpty ? "操作衝突（409）" : "操作失敗：\(m)"
        case .invalidTorrent: return "種子檔案無效"
        case .addFailed: return "新增種子失敗（可能已存在或連結無效）"
        case .badRequest(let m): return m.isEmpty ? "請求參數錯誤（400）" : "請求參數錯誤：\(m)"
        case .http(let code, let m): return "HTTP \(code)\(m.isEmpty ? "" : "：\(m)")"
        case .badResponse: return "伺服器回應格式無法解析"
        case .redirected(let url):
            return "伺服器要求轉址到 \(url)，請把伺服器網址改成這個位址（常見於反向代理把 http 轉到 https）"
        case .hostRejected:
            return "qBittorrent 拒絕了這個連線位址（401）。通常是被「主機標頭驗證」擋下：用 Docker 或路由器把外部連接埠對應到不同的內部連接埠時就會發生。請在 qBittorrent 的 Web UI 設定關閉「啟用主機標頭驗證」，或讓外部與內部連接埠相同。"
        case .apiKeyRejected:
            return "API Key 被拒絕（401／403），請確認金鑰正確且未被撤銷"
        case .notQBittorrent(let body):
            return "伺服器的回應不像 qBittorrent，請確認網址或反向代理設定。回應內容：\(body)"
        }
    }
}

/// 版本號比較，例如 WebAPI "2.11.2"
struct APIVersion: Comparable, Sendable, CustomStringConvertible {
    var parts: [Int]

    init(_ s: String) {
        parts = s.trimmingCharacters(in: CharacterSet(charactersIn: "v \n"))
            .split(separator: ".")
            .map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }

    var description: String { parts.map(String.init).joined(separator: ".") }

    static func < (a: APIVersion, b: APIVersion) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0
            let y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    static func == (a: APIVersion, b: APIVersion) -> Bool { !(a < b) && !(b < a) }
}
