import Foundation

struct TorrentFile: Identifiable, Hashable, Sendable {
    var index: Int
    var name: String
    var size: Int64
    var progress: Double
    var priority: Int
    var availability: Double

    var id: Int { index }

    init(offset: Int, dict d: [String: JSONValue]) {
        index = d["index"]?.int.map(Int.init) ?? offset
        name = d.str("name")
        size = d.i64("size")
        progress = d.dbl("progress")
        priority = d.int("priority")
        availability = d.dbl("availability")
    }

    static let priorities: [(value: Int, label: String)] = [
        (0, "不下載"), (1, "普通"), (6, "高"), (7, "最高"),
    ]

    var priorityLabel: String {
        switch priority {
        case 0: return "不下載"
        case 1: return "普通"
        case 2...6: return "高"
        case 7: return "最高"
        default: return "\(priority)"
        }
    }
}

struct TorrentTracker: Identifiable, Hashable, Sendable {
    var url: String
    var status: Int
    var tier: String
    var peers: Int
    var seeds: Int
    var leeches: Int
    var downloaded: Int
    var message: String

    var id: String { url }

    init(dict d: [String: JSONValue]) {
        url = d.str("url")
        status = d.int("status")
        tier = d.str("tier")
        peers = d.int("num_peers")
        seeds = d.int("num_seeds")
        leeches = d.int("num_leeches")
        downloaded = d.int("num_downloaded")
        message = d.str("msg")
    }

    var isRealTracker: Bool { !url.hasPrefix("** [") }

    var statusLabel: String {
        switch status {
        case 0: return "已停用"
        case 1: return "未連線"
        case 2: return "運作中"
        case 3: return "更新中"
        case 4: return "無法運作"
        default: return "\(status)"
        }
    }
}
