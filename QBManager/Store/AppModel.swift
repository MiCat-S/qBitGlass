import SwiftUI

/// 從外部開啟的 magnet 連結或 .torrent 檔
struct IncomingTorrent: Identifiable, Equatable {
    let id = UUID()
    var urls: [String] = []
    var files: [TorrentUpload] = []
}

/// 伺服器清單與各伺服器連線（Session）的管理。
@Observable @MainActor
final class AppModel {
    private(set) var servers: [ServerConfig] = []
    var path = NavigationPath()
    /// 目前畫面上開啟的伺服器（由 TorrentListView 設定）
    var activeServerID: UUID?
    var incoming: IncomingTorrent?
    @ObservationIgnored private var sessions: [UUID: SessionStore] = [:]
    @ObservationIgnored private var sceneActive = true

    private let serversKey = "servers.v1"
    private let lastKey = "servers.last"

    init() {
        if let data = UserDefaults.standard.data(forKey: serversKey),
           let list = try? JSONDecoder().decode([ServerConfig].self, from: data) {
            servers = list
        }
    }

    var lastServerID: UUID? {
        get { UserDefaults.standard.string(forKey: lastKey).flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: lastKey) }
    }

    func server(_ id: UUID) -> ServerConfig? { servers.first { $0.id == id } }

    func session(for id: UUID) -> SessionStore? {
        if let s = sessions[id] { return s }
        guard let server = server(id) else { return nil }
        let s = SessionStore(server: server)
        s.setSceneActive(sceneActive)
        sessions[id] = s
        return s
    }

    func open(_ id: UUID) {
        lastServerID = id
        var p = NavigationPath()
        p.append(id)
        path = p
    }

    func setSceneActive(_ active: Bool) {
        sceneActive = active
        sessions.values.forEach { $0.setSceneActive(active) }
    }

    func save(_ server: ServerConfig, secret: String) {
        if let i = servers.firstIndex(where: { $0.id == server.id }) {
            let old = servers[i]
            if old.authMode != server.authMode { Keychain.delete(old.secretAccount) }
            servers[i] = server
        } else {
            servers.append(server)
        }
        Keychain.set(secret, for: server.secretAccount)
        // 設定變更後丟棄舊連線，下次進入時重新登入
        sessions[server.id]?.stopPolling()
        sessions[server.id] = nil
        persist()
    }

    func delete(_ server: ServerConfig) {
        servers.removeAll { $0.id == server.id }
        sessions[server.id]?.stopPolling()
        sessions[server.id] = nil
        Keychain.delete("\(server.id.uuidString).password")
        Keychain.delete("\(server.id.uuidString).apikey")
        if activeServerID == server.id { path = NavigationPath() }
        persist()
    }

    func move(from: IndexSet, to: Int) {
        servers.move(fromOffsets: from, toOffset: to)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(data, forKey: serversKey)
        }
    }

    /// 處理外部開啟的 magnet: 連結或 .torrent 檔
    func handleOpen(_ url: URL) {
        var item = IncomingTorrent()
        if url.scheme?.lowercased() == "magnet" {
            item.urls = [url.absoluteString]
        } else if url.isFileURL {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return }
            item.files = [TorrentUpload(filename: url.lastPathComponent, data: data)]
        } else {
            return
        }
        // 目前停在伺服器清單時，自動開啟上次使用的伺服器再顯示新增畫面
        if path.isEmpty, let id = lastServerID ?? servers.first?.id, server(id) != nil {
            open(id)
        }
        incoming = item
    }
}
