import SwiftUI

enum ConnectionState: Equatable {
    case idle, connecting, connected
    case failed(String)
}

/// 單一伺服器的連線、資料同步與批次操作。
@Observable @MainActor
final class SessionStore {
    let server: ServerConfig
    private(set) var client: QBClient?
    private var engine: SyncEngine?

    private(set) var torrents: [String: Torrent] = [:]
    private(set) var categories: [String: TorrentCategory] = [:]
    private(set) var tags: [String] = []
    private(set) var trackerHosts: [String: Set<String>] = [:]
    private(set) var serverState = ServerState()
    private(set) var state: ConnectionState = .idle
    private(set) var appVersion = ""
    private(set) var apiVersion = ""
    private(set) var hasLoaded = false

    /// 輪詢時的暫時性錯誤（顯示在畫面上方）
    var syncError: String?
    /// 使用者操作失敗（以 alert 顯示）
    var actionError: String?

    var filter = TorrentFilter() {
        didSet {
            guard filter.sort != oldValue.sort || filter.ascending != oldValue.ascending else { return }
            UserDefaults.standard.set(filter.sort.rawValue, forKey: "sort.field")
            UserDefaults.standard.set(filter.ascending, forKey: "sort.ascending")
        }
    }

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var refreshAgain = false
    @ObservationIgnored private var holders = 0
    @ObservationIgnored private var sceneActive = true

    init(server: ServerConfig) {
        self.server = server
        if let raw = UserDefaults.standard.string(forKey: "sort.field"), let f = SortField(rawValue: raw) {
            filter.sort = f
            filter.ascending = UserDefaults.standard.bool(forKey: "sort.ascending")
        }
    }

    // MARK: - 衍生資料

    var visibleTorrents: [Torrent] { filter.apply(torrents.values, trackerHosts: trackerHosts) }

    var sortedCategories: [TorrentCategory] {
        categories.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func count(_ status: StatusFilter) -> Int {
        status == .all ? torrents.count : torrents.values.reduce(0) { $0 + (status.matches($1) ? 1 : 0) }
    }

    func hosts(of t: Torrent) -> Set<String> {
        trackerHosts[t.hash] ?? (t.trackerHost.isEmpty ? [] : [t.trackerHost])
    }

    var usesStopStart: Bool { APIVersion(apiVersion) >= APIVersion("2.11") }

    // MARK: - 輪詢

    /// 畫面出現時 acquire、消失時 release；有畫面使用且 App 在前景時才輪詢。
    func acquire() { holders += 1; updatePolling() }
    func release() { holders = max(0, holders - 1); updatePolling() }

    func setSceneActive(_ active: Bool) {
        sceneActive = active
        updatePolling()
    }

    private func updatePolling() {
        if holders > 0 && sceneActive { startPolling() } else { stopPolling() }
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let interval = UserDefaults.standard.double(forKey: "refreshInterval")
                try? await Task.sleep(for: .seconds(interval > 0 ? interval : 2))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func reconnect() async {
        client = nil
        engine = nil
        hasLoaded = false
        state = .idle
        await refresh()
    }

    func refresh() async {
        if isRefreshing { refreshAgain = true; return }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshAgain = false
            await refreshOnce()
        } while refreshAgain
    }

    private func refreshOnce() async {
        do {
            if engine == nil { try await connect() }
            guard let engine else { return }
            let snap = try await engine.poll()
            torrents = snap.torrents
            categories = snap.categories
            tags = snap.tags
            trackerHosts = snap.trackerHosts
            serverState = snap.serverState
            hasLoaded = true
            state = .connected
            syncError = nil
        } catch {
            if Self.isCancellation(error) { return }
            let msg = Self.describe(error)
            if hasLoaded {
                syncError = msg
            } else {
                state = .failed(msg)
                client = nil
                engine = nil
            }
        }
    }

    private func connect() async throws {
        state = .connecting
        let secret = Keychain.get(server.secretAccount) ?? ""
        let c = try QBClient(config: server, secret: secret)
        let info = try await c.connect()
        appVersion = info.app
        apiVersion = info.api
        client = c
        engine = SyncEngine(client: c)
    }

    func logout() async {
        stopPolling()
        await client?.logout()
        client = nil
        engine = nil
    }

    // MARK: - 操作

    /// 執行操作後立即刷新；失敗時寫入 actionError。
    @discardableResult
    func run(_ op: (QBClient) async throws -> Void) async -> Bool {
        guard let client else {
            actionError = "尚未連線到伺服器"
            return false
        }
        do {
            try await op(client)
            await refresh()
            return true
        } catch {
            if !Self.isCancellation(error) { actionError = Self.describe(error) }
            return false
        }
    }

    func start(_ hashes: [String]) async { await run { try await $0.start(hashes) } }
    func stop(_ hashes: [String]) async { await run { try await $0.stop(hashes) } }
    func forceStart(_ hashes: [String], _ value: Bool) async { await run { try await $0.setForceStart(hashes, value) } }
    func delete(_ hashes: [String], deleteFiles: Bool) async { await run { try await $0.delete(hashes, deleteFiles: deleteFiles) } }
    func recheck(_ hashes: [String]) async { await run { try await $0.recheck(hashes) } }
    func reannounce(_ hashes: [String]) async { await run { try await $0.reannounce(hashes) } }
    func queue(_ move: QueueMove, _ hashes: [String]) async { await run { try await $0.queue(move, hashes) } }
    func toggleSequential(_ hashes: [String]) async { await run { try await $0.toggleSequential(hashes) } }
    func toggleFirstLast(_ hashes: [String]) async { await run { try await $0.toggleFirstLastPiece(hashes) } }
    func toggleAltSpeed() async { await run { try await $0.toggleAltSpeed() } }

    func setCategory(_ hashes: [String], _ category: String) async {
        await run { client in
            if !category.isEmpty, self.categories[category] == nil {
                try await client.createCategory(category)
            }
            try await client.setCategory(hashes, category)
        }
    }

    func addTags(_ hashes: [String], _ tags: [String]) async { await run { try await $0.addTags(hashes, tags) } }
    func removeTags(_ hashes: [String], _ tags: [String]) async { await run { try await $0.removeTags(hashes, tags) } }

    // MARK: - 錯誤

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let u = error as? URLError, u.code == .cancelled { return true }
        return false
    }

    static func describe(_ error: Error) -> String {
        if let u = error as? URLError {
            switch u.code {
            case .timedOut: return "連線逾時，請確認伺服器位址與網路"
            case .cannotConnectToHost, .cannotFindHost: return "無法連線到伺服器，請確認位址與連接埠"
            case .notConnectedToInternet: return "目前沒有網路連線"
            case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid,
                 .serverCertificateHasUnknownRoot, .secureConnectionFailed:
                return "HTTPS 憑證不受信任，可在伺服器設定開啟「信任自簽憑證」"
            case .appTransportSecurityRequiresSecureConnection: return "系統阻擋了不安全的 HTTP 連線"
            default: return u.localizedDescription
            }
        }
        return error.localizedDescription
    }
}
