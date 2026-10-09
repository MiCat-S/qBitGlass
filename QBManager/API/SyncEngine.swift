import Foundation

struct SyncSnapshot: Sendable {
    var torrents: [String: Torrent]
    var categories: [String: TorrentCategory]
    var tags: [String]
    /// hash → 該種子所有 tracker 主機（qB ≥ 4.5 的 maindata 才有 trackers 欄位）
    var trackerHosts: [String: Set<String>]
    var serverState: ServerState
}

/// 透過 sync/maindata 的 rid 增量同步，合併部分更新後產生完整快照（在背景 actor 中執行）。
actor SyncEngine {
    private let client: QBClient
    private var rid = 0
    private var raw: [String: [String: JSONValue]] = [:]
    private var torrents: [String: Torrent] = [:]
    private var categories: [String: TorrentCategory] = [:]
    private var tags: Set<String> = []
    private var trackers: [String: [String]] = [:]
    private var trackerHosts: [String: Set<String>] = [:]
    private var serverState: [String: JSONValue] = [:]

    init(client: QBClient) { self.client = client }

    func reset() { rid = 0 }

    func poll() async throws -> SyncSnapshot {
        let data = try await client.mainData(rid: rid)
        guard let obj = try? JSONDecoder().decode([String: JSONValue].self, from: data) else {
            throw QBError.badResponse
        }
        merge(obj)
        return SyncSnapshot(torrents: torrents,
                            categories: categories,
                            tags: tags.sorted { $0.localizedStandardCompare($1) == .orderedAscending },
                            trackerHosts: trackerHosts,
                            serverState: ServerState(raw: serverState))
    }

    private func merge(_ obj: [String: JSONValue]) {
        if obj["full_update"]?.bool == true {
            raw = [:]; torrents = [:]; categories = [:]; tags = []; trackers = [:]; serverState = [:]
        }
        rid = Int(obj["rid"]?.int ?? 0)

        if let changed = obj["torrents"]?.object {
            for (hash, value) in changed {
                guard let patch = value.object else { continue }
                var cur = raw[hash] ?? [:]
                cur.merge(patch) { _, new in new }
                raw[hash] = cur
                torrents[hash] = Torrent(hash: hash, dict: cur)
            }
        }
        for h in obj["torrents_removed"]?.array ?? [] {
            guard let hash = h.string else { continue }
            raw[hash] = nil
            torrents[hash] = nil
        }

        if let changed = obj["categories"]?.object {
            for (name, value) in changed {
                let d = value.object ?? [:]
                var cat = categories[name] ?? TorrentCategory(name: name, savePath: "")
                if let p = d["savePath"]?.string { cat.savePath = p }
                categories[name] = cat
            }
        }
        for c in obj["categories_removed"]?.array ?? [] {
            if let name = c.string { categories[name] = nil }
        }

        for t in obj["tags"]?.array ?? [] { if let s = t.string { tags.insert(s) } }
        for t in obj["tags_removed"]?.array ?? [] { if let s = t.string { tags.remove(s) } }

        var trackersChanged = obj["full_update"]?.bool == true
        if let changed = obj["trackers"]?.object {
            for (url, value) in changed {
                trackers[url] = (value.array ?? []).compactMap(\.string)
            }
            trackersChanged = true
        }
        for u in obj["trackers_removed"]?.array ?? [] {
            if let url = u.string { trackers[url] = nil; trackersChanged = true }
        }
        if trackersChanged { rebuildTrackerHosts() }

        if let state = obj["server_state"]?.object {
            serverState.merge(state) { _, new in new }
        }
    }

    private func rebuildTrackerHosts() {
        var map: [String: Set<String>] = [:]
        for (url, hashes) in trackers {
            let host = URL(string: url)?.host ?? url
            for h in hashes { map[h, default: []].insert(host) }
        }
        trackerHosts = map
    }
}
