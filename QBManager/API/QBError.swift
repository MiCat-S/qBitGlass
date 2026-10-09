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
