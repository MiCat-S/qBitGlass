import SwiftUI

enum ConnectionState: Equatable {
    case idle, connecting, connected
    case failed(String)
}

/// 單一伺服器的連線、資料同步與批次操作。
@Observable @MainActor
final class SessionStore {
    private(set) var server: ServerConfig
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
    /// 篩選、排序後要顯示的種子；只在資料或篩選條件變動時重算，不在每次畫面更新時重算
    private(set) var visibleTorrents: [Torrent] = []
    /// 各狀態的種子數（狀態膠囊與篩選面板用），每次同步只算一遍
    private(set) var statusCounts: [StatusFilter: Int] = [:]
    /// 連線失敗後是否還會自動重試；帳密錯誤這類問題不會
    private(set) var willRetry = false

    /// 輪詢時的暫時性錯誤（顯示在畫面上方）
    var syncError: String?
    /// 使用者操作失敗（以 alert 顯示）
    var actionError: String?

    var filter = TorrentFilter() {
        didSet {
            guard filter != oldValue else { return }
            updateVisible()
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
    /// 每次重新連線或改設定就加一，讓進行中的舊請求結果被丟棄
    @ObservationIgnored private var generation = 0
    /// 自動輪詢暫停到這個時間；.distantFuture 表示等使用者手動重試
    @ObservationIgnored private var pausedUntil: Date?
    @ObservationIgnored private var retryDelay: TimeInterval = 0

    init(server: ServerConfig) {
        self.server = server
        if let raw = UserDefaults.standard.string(forKey: "sort.field"), let f = SortField(rawValue: raw) {
            filter.sort = f
            filter.ascending = UserDefaults.standard.bool(forKey: "sort.ascending")
        }
    }

    // MARK: - 衍生資料

    var sortedCategories: [TorrentCategory] {
        categories.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func count(_ status: StatusFilter) -> Int { statusCounts[status] ?? 0 }

    func hosts(of t: Torrent) -> Set<String> {
        trackerHosts[t.hash] ?? (t.trackerHost.isEmpty ? [] : [t.trackerHost])
    }

    var usesStopStart: Bool { APIVersion(apiVersion) >= APIVersion("2.11") }

    private func updateVisible() {
        visibleTorrents = filter.apply(torrents.values, trackerHosts: trackerHosts)
    }

    /// 走訪一次算出所有狀態的數量，取代每個狀態膠囊各掃一遍
    private func recount() {
        var counts: [StatusFilter: Int] = [:]
        for t in torrents.values {
            for status in StatusFilter.allCases where status.matches(t) { counts[status, default: 0] += 1 }
        }
        statusCounts = counts
    }

    // MARK: - 輪詢

    /// 畫面出現時 acquire、消失時 release；有畫面使用且 App 在前景時才輪詢。
    func acquire() { holders += 1; updatePolling() }
    func release() { holders = max(0, holders - 1); updatePolling() }

    func setSceneActive(_ active: Bool) {
        sceneActive = active
        // 回到前景時，暫時性錯誤不必等退避時間，立刻再試一次
        if active, pausedUntil != .distantFuture {
            pausedUntil = nil
            retryDelay = 0
        }
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
                await self.autoRefresh()
                let interval = UserDefaults.standard.double(forKey: "refreshInterval")
                try? await Task.sleep(for: .seconds(interval > 0 ? interval : 2))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// 輪詢觸發的刷新：失敗後依退避時間再試，不可恢復的錯誤則等使用者手動重試
    private func autoRefresh() async {
        if let pausedUntil, Date() < pausedUntil { return }
        await refresh()
    }

    /// 下拉重新整理：自動更新已因錯誤停止時，重新建立連線再試一次
    func manualRefresh() async {
        if pausedUntil == .distantFuture { await reconnect() } else { await refresh() }
    }

    func reconnect() async {
        resetConnection()
        hasLoaded = false
        state = .idle
        await refresh()
    }

    /// 伺服器設定變更：清掉舊資料並以新設定重新登入；正在顯示時立即重新連線
    func update(_ server: ServerConfig) {
        self.server = server
        resetConnection()
        hasLoaded = false
        state = .idle
        torrents = [:]
        categories = [:]
        tags = []
        trackerHosts = [:]
        serverState = ServerState()
        visibleTorrents = []
        statusCounts = [:]
        syncError = nil
        if holders > 0 && sceneActive { Task { await refresh() } }
    }

    /// 丟棄目前的連線，並清除重試狀態
    private func resetConnection() {
        generation += 1
        client = nil
        engine = nil
        pausedUntil = nil
        retryDelay = 0
        willRetry = false
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
        let gen = generation
        do {
            if engine == nil { try await connect(gen) }
            guard let engine else { return }
            let snap = try await engine.poll()
            guard gen == generation else { return }
            apply(snap)
            hasLoaded = true
            state = .connected
            syncError = nil
            pausedUntil = nil
            retryDelay = 0
            willRetry = false
        } catch {
            if Self.isCancellation(error) || gen != generation { return }
            handleFailure(error)
        }
    }

    /// 只更新有變動的部分，沒有變化時不觸發畫面重繪，也不重新排序
    private func apply(_ snap: SyncSnapshot) {
        var listChanged = false
        if snap.torrentsChanged || !hasLoaded {
            torrents = snap.torrents
            recount()
            listChanged = true
        }
        if trackerHosts != snap.trackerHosts {
            trackerHosts = snap.trackerHosts
            listChanged = true
        }
        if listChanged { updateVisible() }
        if categories != snap.categories { categories = snap.categories }
        if tags != snap.tags { tags = snap.tags }
        if serverState != snap.serverState { serverState = snap.serverState }
    }

    /// 暫時性錯誤（網路不通、逾時）逐步拉長間隔重試，最長 60 秒。
    /// 帳密錯誤、被封鎖、網址或憑證設定錯誤，重試只會再失敗（帳密錯誤還會讓 qBittorrent 封鎖 IP），
    /// 所以停止自動重試，等使用者按重試或修改設定
    private func handleFailure(_ error: Error) {
        let msg = Self.describe(error)
        let transient = Self.isTransient(error)
        if transient {
            retryDelay = retryDelay == 0 ? 2 : min(retryDelay * 2, 60)
            pausedUntil = Date().addingTimeInterval(retryDelay)
        } else {
            pausedUntil = .distantFuture
        }
        willRetry = transient
        if hasLoaded {
            syncError = transient ? msg : "\(msg)（已暫停自動更新，下拉可重新連線）"
        } else {
            state = .failed(msg)
            client = nil
            engine = nil
        }
    }

    private static func isTransient(_ error: Error) -> Bool {
        if let u = error as? URLError {
            switch u.code {
            case .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .networkConnectionLost,
                 .notConnectedToInternet, .cannotLoadFromNetwork, .dataNotAllowed, .internationalRoamingOff,
                 .callIsActive:
                return true
            default:
                return false
            }
        }
        switch error as? QBError {
        case .http(let code, _): return code >= 500
        case .badResponse: return true
        default: return false
        }
    }

    private func connect(_ gen: Int) async throws {
        // 背景重試時維持錯誤畫面，不要每次重試都閃回「連線中」
        if case .failed = state {} else { state = .connecting }
        let secret = Keychain.get(server.secretAccount) ?? ""
        let c = try QBClient(config: server, secret: secret)
        let info = try await c.connect()
        guard gen == generation else { throw CancellationError() }
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

    // 回傳是否成功，讓畫面決定後續動作（例如刪除成功才關閉詳情頁）
    @discardableResult func start(_ hashes: [String]) async -> Bool { await run { try await $0.start(hashes) } }
    @discardableResult func stop(_ hashes: [String]) async -> Bool { await run { try await $0.stop(hashes) } }
    @discardableResult func forceStart(_ hashes: [String], _ value: Bool) async -> Bool { await run { try await $0.setForceStart(hashes, value) } }
    @discardableResult func delete(_ hashes: [String], deleteFiles: Bool) async -> Bool { await run { try await $0.delete(hashes, deleteFiles: deleteFiles) } }
    @discardableResult func recheck(_ hashes: [String]) async -> Bool { await run { try await $0.recheck(hashes) } }
    @discardableResult func reannounce(_ hashes: [String]) async -> Bool { await run { try await $0.reannounce(hashes) } }
    @discardableResult func queue(_ move: QueueMove, _ hashes: [String]) async -> Bool { await run { try await $0.queue(move, hashes) } }
    @discardableResult func toggleSequential(_ hashes: [String]) async -> Bool { await run { try await $0.toggleSequential(hashes) } }
    @discardableResult func toggleFirstLast(_ hashes: [String]) async -> Bool { await run { try await $0.toggleFirstLastPiece(hashes) } }
    @discardableResult func toggleAltSpeed() async -> Bool { await run { try await $0.toggleAltSpeed() } }

    @discardableResult
    func setCategory(_ hashes: [String], _ category: String) async -> Bool {
        await run { client in
            if !category.isEmpty, self.categories[category] == nil {
                try await client.createCategory(category)
            }
            try await client.setCategory(hashes, category)
        }
    }

    @discardableResult func addTags(_ hashes: [String], _ tags: [String]) async -> Bool { await run { try await $0.addTags(hashes, tags) } }
    @discardableResult func removeTags(_ hashes: [String], _ tags: [String]) async -> Bool { await run { try await $0.removeTags(hashes, tags) } }

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
