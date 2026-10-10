import Foundation
import Network

struct TorrentUpload: Sendable, Hashable {
    var filename: String
    var data: Data
}

struct AddTorrentOptions: Sendable, Equatable {
    var urls: [String] = []
    var files: [TorrentUpload] = []
    var savePath = ""
    var category = ""
    var tags: [String] = []
    var startStopped = false
    var skipChecking = false
    var sequential = false
    var firstLastPiece = false
}

enum QueueMove: String, Sendable {
    case top = "topPrio", up = "increasePrio", down = "decreasePrio", bottom = "bottomPrio"
}

/// 處理自簽憑證；不自動跟隨轉址
private final class SessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let trustAll: Bool
    init(trustAll: Bool) { self.trustAll = trustAll }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if trustAll,
           challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    // 301/302 轉址會把 POST 改成 GET 並丟掉表單內容，導致登入失敗；不跟隨，改由上層提示正確網址
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// qBittorrent WebUI API v2 客戶端。
/// - 帳號密碼模式：POST /api/v2/auth/login 取得 SID cookie，403 時自動重新登入並重試一次。
/// - API Key 模式（qB ≥ 5.2）：每個請求帶 `Authorization: Bearer <key>`。
/// - WebAPI ≥ 2.11（qB 5.0）使用 torrents/start、torrents/stop，舊版使用 resume、pause。
actor QBClient {
    let config: ServerConfig
    private let base: URL
    private let secret: String
    private let session: URLSession
    private var authenticated = false
    private var loginTask: Task<Void, Error>?
    /// 帳密錯誤、IP 被封鎖、API Key 被拒之後不再送出請求：重試只會再失敗，
    /// 帳密錯誤累積幾次還會讓 qBittorrent 封鎖這個 IP。要再試就建立新的 QBClient（重新連線或改設定）
    private var authError: QBError?

    private(set) var apiVersion = APIVersion("0")
    private(set) var appVersion = ""

    init(config: ServerConfig, secret: String) throws {
        guard let base = config.baseURL else { throw QBError.invalidURL }
        self.config = config
        self.base = base
        self.secret = secret
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpShouldSetCookies = true
        cfg.waitsForConnectivity = false
        // 指定代理時，所有請求（包括區網與 Tailscale 位址）都經過它；代理連不上就直接報錯，不改走直連
        if let endpoint = config.proxy.endpoint {
            var proxy = config.proxy.kind == .socks5
                ? ProxyConfiguration(socksv5Proxy: endpoint)
                : ProxyConfiguration(httpCONNECTProxy: endpoint)
            proxy.allowFailover = false
            cfg.proxyConfigurations = [proxy]
        }
        session = URLSession(configuration: cfg,
                             delegate: SessionDelegate(trustAll: config.trustSelfSigned),
                             delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    /// qB 5.0（WebAPI 2.11）起暫停/繼續改名為停止/啟動
    var usesStopStart: Bool { apiVersion >= APIVersion("2.11") }

    // MARK: - 連線

    @discardableResult
    func connect() async throws -> (app: String, api: String) {
        try await ensureLogin(force: true)
        let api = try await text("app/webapiVersion")
        apiVersion = APIVersion(api)
        appVersion = (try? await text("app/version")) ?? ""
        return (appVersion, api)
    }

    func logout() async {
        guard config.authMode == .password else { return }
        _ = try? await perform("auth/logout", body: .form([:]))
        authenticated = false
    }

    // MARK: - 讀取

    func mainData(rid: Int) async throws -> Data {
        try await send("sync/maindata", query: ["rid": String(rid)])
    }

    func files(_ hash: String) async throws -> [TorrentFile] {
        let data = try await send("torrents/files", query: ["hash": hash])
        let list = try JSONDecoder().decode([[String: JSONValue]].self, from: data)
        return list.enumerated().map { TorrentFile(offset: $0.offset, dict: $0.element) }
    }

    func trackers(_ hash: String) async throws -> [TorrentTracker] {
        let data = try await send("torrents/trackers", query: ["hash": hash])
        let list = try JSONDecoder().decode([[String: JSONValue]].self, from: data)
        return list.map(TorrentTracker.init(dict:))
    }

    func properties(_ hash: String) async throws -> [String: JSONValue] {
        let data = try await send("torrents/properties", query: ["hash": hash])
        return try JSONDecoder().decode([String: JSONValue].self, from: data)
    }

    // MARK: - 種子操作

    func start(_ hashes: [String]) async throws {
        try await post(usesStopStart ? "torrents/start" : "torrents/resume", ["hashes": join(hashes)])
    }

    func stop(_ hashes: [String]) async throws {
        try await post(usesStopStart ? "torrents/stop" : "torrents/pause", ["hashes": join(hashes)])
    }

    func setForceStart(_ hashes: [String], _ value: Bool) async throws {
        try await post("torrents/setForceStart", ["hashes": join(hashes), "value": value ? "true" : "false"])
    }

    func delete(_ hashes: [String], deleteFiles: Bool) async throws {
        try await post("torrents/delete", ["hashes": join(hashes), "deleteFiles": deleteFiles ? "true" : "false"])
    }

    func recheck(_ hashes: [String]) async throws {
        try await post("torrents/recheck", ["hashes": join(hashes)])
    }

    func reannounce(_ hashes: [String]) async throws {
        try await post("torrents/reannounce", ["hashes": join(hashes)])
    }

    func setCategory(_ hashes: [String], _ category: String) async throws {
        try await post("torrents/setCategory", ["hashes": join(hashes), "category": category])
    }

    func createCategory(_ name: String, savePath: String = "") async throws {
        try await post("torrents/createCategory", ["category": name, "savePath": savePath])
    }

    func addTags(_ hashes: [String], _ tags: [String]) async throws {
        try await post("torrents/addTags", ["hashes": join(hashes), "tags": tags.joined(separator: ",")])
    }

    func removeTags(_ hashes: [String], _ tags: [String]) async throws {
        try await post("torrents/removeTags", ["hashes": join(hashes), "tags": tags.joined(separator: ",")])
    }

    func setLocation(_ hashes: [String], _ location: String) async throws {
        try await post("torrents/setLocation", ["hashes": join(hashes), "location": location])
    }

    func rename(_ hash: String, _ name: String) async throws {
        try await post("torrents/rename", ["hash": hash, "name": name])
    }

    func queue(_ move: QueueMove, _ hashes: [String]) async throws {
        try await post("torrents/\(move.rawValue)", ["hashes": join(hashes)])
    }

    func toggleSequential(_ hashes: [String]) async throws {
        try await post("torrents/toggleSequentialDownload", ["hashes": join(hashes)])
    }

    func toggleFirstLastPiece(_ hashes: [String]) async throws {
        try await post("torrents/toggleFirstLastPiecePrio", ["hashes": join(hashes)])
    }

    func setFilePriority(_ hash: String, ids: [Int], priority: Int) async throws {
        try await post("torrents/filePrio", [
            "hash": hash,
            "id": ids.map(String.init).joined(separator: "|"),
            "priority": String(priority),
        ])
    }

    func add(_ o: AddTorrentOptions) async throws {
        var form = MultipartForm()
        if !o.urls.isEmpty { form.add("urls", o.urls.joined(separator: "\n")) }
        for f in o.files {
            form.addFile("torrents", filename: f.filename, mime: "application/x-bittorrent", data: f.data)
        }
        if !o.savePath.isEmpty { form.add("savepath", o.savePath) }
        if !o.category.isEmpty { form.add("category", o.category) }
        if !o.tags.isEmpty { form.add("tags", o.tags.joined(separator: ",")) }
        if o.startStopped {
            form.add("paused", "true")
            form.add("stopped", "true")
        }
        if o.skipChecking { form.add("skip_checking", "true") }
        if o.sequential { form.add("sequentialDownload", "true") }
        if o.firstLastPiece { form.add("firstLastPiecePrio", "true") }

        let data = try await send("torrents/add", body: .multipart(form))
        if Self.text(data).hasPrefix("Fails") { throw QBError.addFailed }
    }

    func toggleAltSpeed() async throws {
        try await post("transfer/toggleSpeedLimitsMode", [:])
    }

    // MARK: - 傳輸層

    enum Body: Sendable {
        case none
        case form([String: String])
        case multipart(MultipartForm)
    }

    private func join(_ hashes: [String]) -> String { hashes.joined(separator: "|") }

    private func post(_ path: String, _ form: [String: String]) async throws {
        _ = try await send(path, body: .form(form))
    }

    private func text(_ path: String) async throws -> String {
        Self.text(try await send(path))
    }

    private static func text(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func send(_ path: String, query: [String: String] = [:], body: Body = .none) async throws -> Data {
        if let authError { throw authError }
        try await ensureLogin(force: false)
        var (data, resp) = try await perform(path, query: query, body: body)
        if resp.statusCode == 403, config.authMode == .password {
            // SID 過期：重新登入後重試一次
            authenticated = false
            try await ensureLogin(force: true)
            (data, resp) = try await perform(path, query: query, body: body)
        }
        do {
            try validate(resp, data)
        } catch QBError.apiKeyRejected {
            throw authFailed(.apiKeyRejected)
        }
        return data
    }

    private func authFailed(_ error: QBError) -> QBError {
        authError = error
        return error
    }

    private func ensureLogin(force: Bool) async throws {
        guard config.authMode == .password else { return }
        if authenticated && !force { return }
        if let loginTask {
            try await loginTask.value
            return
        }
        let task = Task { try await self.login() }
        loginTask = task
        defer { loginTask = nil }
        try await task.value
    }

    private func login() async throws {
        let (data, resp) = try await perform("auth/login",
                                             body: .form(["username": config.username, "password": secret]))
        let text = Self.text(data)
        switch resp.statusCode {
        case 200, 204:
            // qB ≤ 5.1：成功回 200「Ok.」、帳密錯誤回 200「Fails.」
            // qB ≥ 5.2：成功回 204（沒有內容）、帳密錯誤回 401
            if text.hasPrefix("Fails") { throw authFailed(.loginFailed) }
            guard text.isEmpty || text.hasPrefix("Ok") else {
                throw QBError.notQBittorrent(String(text.prefix(120)))
            }
            authenticated = true
        case 401:
            // 帳密錯誤（5.2+）與主機標頭驗證失敗都回 401。用不需登入的請求區分：
            // 被主機標頭驗證擋下時一樣回 401，否則會是 403（未登入）或 200
            let (_, probe) = try await perform("app/webapiVersion")
            throw probe.statusCode == 401 ? QBError.hostRejected : authFailed(.loginFailed)
        case 403:
            throw authFailed(.banned)
        default:
            try validate(resp, data)
            throw QBError.badResponse
        }
    }

    private func perform(_ path: String, query: [String: String] = [:], body: Body = .none) async throws -> (Data, HTTPURLResponse) {
        var url = base.appendingPathComponent("api/v2/" + path)
        if !query.isEmpty, var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            comps.percentEncodedQuery = Self.encode(query)
            url = comps.url ?? url
        }
        var req = URLRequest(url: url)
        req.setValue("QBManager-iOS", forHTTPHeaderField: "User-Agent")
        if config.authMode == .apiKey, !secret.isEmpty {
            req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        switch body {
        case .none:
            req.httpMethod = "GET"
        case .form(let fields):
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            req.httpBody = Data(Self.encode(fields).utf8)
        case .multipart(let form):
            req.httpMethod = "POST"
            req.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
            req.httpBody = form.body
            req.timeoutInterval = 60
        }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw QBError.badResponse }
        return (data, http)
    }

    // 只保留 ASCII 非保留字元，其餘（含中文、+、&、|）一律百分比編碼
    private static let allowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func encode(_ fields: [String: String]) -> String {
        fields.map { k, v in
            let ek = k.addingPercentEncoding(withAllowedCharacters: allowed) ?? k
            let ev = v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v
            return "\(ek)=\(ev)"
        }.joined(separator: "&")
    }

    private func validate(_ resp: HTTPURLResponse, _ data: Data) throws {
        let msg = String(decoding: data.prefix(300), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        switch resp.statusCode {
        case 200..<300: return
        case 300..<400: throw QBError.redirected(Self.redirectBase(resp) ?? "")
        case 400: throw QBError.badRequest(msg)
        case 401: throw config.authMode == .apiKey ? QBError.apiKeyRejected : QBError.hostRejected
        case 403: throw config.authMode == .apiKey ? QBError.apiKeyRejected : QBError.forbidden
        case 404: throw QBError.notFound
        case 409: throw QBError.conflict(msg)
        case 415: throw QBError.invalidTorrent
        default: throw QBError.http(resp.statusCode, msg)
        }
    }

    /// 由轉址目標推算 WebUI 根網址（去掉 /api/v2/... 部分）
    private static func redirectBase(_ resp: HTTPURLResponse) -> String? {
        guard let location = resp.value(forHTTPHeaderField: "Location"),
              let target = URL(string: location, relativeTo: resp.url)?.absoluteURL else { return nil }
        let s = target.absoluteString
        if let r = s.range(of: "/api/v2/") { return String(s[..<r.lowerBound]) }
        var c = URLComponents()
        c.scheme = target.scheme
        c.host = target.host
        c.port = target.port
        return c.string
    }
}
