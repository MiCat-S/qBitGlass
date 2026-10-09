import Foundation

enum StatusFilter: String, CaseIterable, Identifiable, Sendable {
    case all, downloading, seeding, completed, running, stopped
    case active, inactive, stalled, checking, moving, errored

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "全部"
        case .downloading: return "下載中"
        case .seeding: return "做種中"
        case .completed: return "已完成"
        case .running: return "執行中"
        case .stopped: return "已停止"
        case .active: return "活動中"
        case .inactive: return "非活動"
        case .stalled: return "停滯"
        case .checking: return "檢查中"
        case .moving: return "移動中"
        case .errored: return "錯誤"
        }
    }

    var symbol: String {
        switch self {
        case .all: return "tray.full"
        case .downloading: return "arrow.down"
        case .seeding: return "arrow.up"
        case .completed: return "checkmark"
        case .running: return "play"
        case .stopped: return "pause"
        case .active: return "bolt"
        case .inactive: return "moon.zzz"
        case .stalled: return "tortoise"
        case .checking: return "arrow.triangle.2.circlepath"
        case .moving: return "folder"
        case .errored: return "exclamationmark.triangle"
        }
    }

    func matches(_ t: Torrent) -> Bool {
        switch self {
        case .all: return true
        case .downloading: return t.state.isDownloading
        case .seeding: return t.state.isUploading
        case .completed: return t.state.isCompleted
        case .running: return !t.state.isStopped
        case .stopped: return t.state.isStopped
        case .active: return t.isActive
        case .inactive: return !t.isActive
        case .stalled: return t.state.isStalled
        case .checking: return t.state.isChecking
        case .moving: return t.state == .moving
        case .errored: return t.state.isErrored
        }
    }
}

enum SortField: String, CaseIterable, Identifiable, Sendable {
    case addedOn, name, size, progress, dlspeed, upspeed, eta, ratio
    case state, seeds, leechs, category, completionOn, lastActivity, uploaded, downloaded

    var id: String { rawValue }

    var label: String {
        switch self {
        case .addedOn: return "加入時間"
        case .name: return "名稱"
        case .size: return "大小"
        case .progress: return "進度"
        case .dlspeed: return "下載速度"
        case .upspeed: return "上傳速度"
        case .eta: return "剩餘時間"
        case .ratio: return "分享率"
        case .state: return "狀態"
        case .seeds: return "種子數"
        case .leechs: return "下載者數"
        case .category: return "分類"
        case .completionOn: return "完成時間"
        case .lastActivity: return "最後活動"
        case .uploaded: return "已上傳"
        case .downloaded: return "已下載"
        }
    }

    func less(_ a: Torrent, _ b: Torrent) -> Bool {
        switch self {
        case .addedOn: return a.addedOn < b.addedOn
        case .name: return a.name.localizedStandardCompare(b.name) == .orderedAscending
        case .size: return a.size < b.size
        case .progress: return a.progress < b.progress
        case .dlspeed: return a.dlspeed < b.dlspeed
        case .upspeed: return a.upspeed < b.upspeed
        case .eta: return a.eta < b.eta
        case .ratio: return a.ratio < b.ratio
        case .state: return a.state.label < b.state.label
        case .seeds: return a.numSeeds < b.numSeeds
        case .leechs: return a.numLeechs < b.numLeechs
        case .category: return a.category.localizedStandardCompare(b.category) == .orderedAscending
        case .completionOn: return a.completionOn < b.completionOn
        case .lastActivity: return a.lastActivity < b.lastActivity
        case .uploaded: return a.uploaded < b.uploaded
        case .downloaded: return a.downloaded < b.downloaded
        }
    }
}

/// 篩選條件。category / tag / tracker 為 nil 表示「全部」，空字串表示「無」。
struct TorrentFilter: Equatable, Sendable {
    var status: StatusFilter = .all
    var category: String?
    var tag: String?
    var trackerHost: String?
    var search: String = ""
    var sort: SortField = .addedOn
    var ascending: Bool = false

    var isFiltering: Bool {
        status != .all || category != nil || tag != nil || trackerHost != nil
    }

    var activeCount: Int {
        [status != .all, category != nil, tag != nil, trackerHost != nil].filter { $0 }.count
    }

    /// trackerHosts: hash → 該種子所有 tracker 主機
    func matches(_ t: Torrent, trackerHosts: [String: Set<String>]) -> Bool {
        guard status.matches(t) else { return false }
        if let category, t.category != category { return false }
        if let tag {
            if tag.isEmpty { if !t.tags.isEmpty { return false } }
            else if !t.tags.contains(tag) { return false }
        }
        if let trackerHost {
            let hosts = trackerHosts[t.hash] ?? (t.trackerHost.isEmpty ? [] : [t.trackerHost])
            if trackerHost.isEmpty { if !hosts.isEmpty { return false } }
            else if !hosts.contains(trackerHost) { return false }
        }
        let words = search.split(whereSeparator: \.isWhitespace)
        if !words.isEmpty {
            for w in words where !t.name.localizedCaseInsensitiveContains(w) && !t.hash.hasPrefix(w.lowercased()) {
                return false
            }
        }
        return true
    }

    func apply(_ torrents: some Sequence<Torrent>, trackerHosts: [String: Set<String>]) -> [Torrent] {
        let filtered = torrents.filter { matches($0, trackerHosts: trackerHosts) }
        return filtered.sorted { a, b in
            if sort.less(a, b) { return ascending }
            if sort.less(b, a) { return !ascending }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}
