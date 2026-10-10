import SwiftUI

/// qBittorrent 種子狀態（相容 4.x 的 paused* 與 5.x 的 stopped*）。
enum TorrentState: String, Sendable {
    case error, missingFiles, uploading, pausedUP, stoppedUP, queuedUP, stalledUP
    case checkingUP, forcedUP, allocating, downloading, metaDL, forcedMetaDL
    case pausedDL, stoppedDL, queuedDL, stalledDL, checkingDL, forcedDL
    case checkingResumeData, moving, unknown

    init(raw: String) { self = TorrentState(rawValue: raw) ?? .unknown }

    var isStopped: Bool { [.pausedUP, .stoppedUP, .pausedDL, .stoppedDL].contains(self) }
    var isErrored: Bool { self == .error || self == .missingFiles }
    var isChecking: Bool { [.checkingUP, .checkingDL, .checkingResumeData].contains(self) }
    var isStalled: Bool { self == .stalledUP || self == .stalledDL }

    /// 對應 qBittorrent 的 isDownloading()
    var isDownloading: Bool {
        [.downloading, .metaDL, .forcedMetaDL, .stalledDL, .checkingDL,
         .pausedDL, .stoppedDL, .queuedDL, .forcedDL].contains(self)
    }

    /// 對應 qBittorrent 的 isUploading()
    var isUploading: Bool {
        [.uploading, .stalledUP, .checkingUP, .queuedUP, .forcedUP].contains(self)
    }

    /// 對應 qBittorrent 的 isCompleted()
    var isCompleted: Bool {
        [.uploading, .stalledUP, .checkingUP, .pausedUP, .stoppedUP, .queuedUP, .forcedUP].contains(self)
    }

    var label: String {
        switch self {
        case .error: return "錯誤"
        case .missingFiles: return "檔案遺失"
        case .uploading: return "做種中"
        case .pausedUP, .stoppedUP: return "已完成"
        case .queuedUP: return "排隊做種"
        case .stalledUP: return "做種（閒置）"
        case .checkingUP, .checkingDL: return "檢查中"
        case .forcedUP: return "[強制] 做種"
        case .allocating: return "分配空間"
        case .downloading: return "下載中"
        case .metaDL: return "取得中繼資料"
        case .forcedMetaDL: return "[強制] 取得中繼資料"
        case .pausedDL, .stoppedDL: return "已停止"
        case .queuedDL: return "排隊下載"
        case .stalledDL: return "下載（停滯）"
        case .forcedDL: return "[強制] 下載"
        case .checkingResumeData: return "檢查恢復資料"
        case .moving: return "移動中"
        case .unknown: return "未知"
        }
    }

    var symbol: String {
        switch self {
        case .error, .missingFiles: return "exclamationmark.triangle.fill"
        case .uploading, .forcedUP: return "arrow.up.circle.fill"
        case .stalledUP: return "arrow.up.circle"
        case .pausedUP, .stoppedUP: return "checkmark.circle.fill"
        case .pausedDL, .stoppedDL: return "pause.circle.fill"
        case .queuedUP, .queuedDL: return "clock.fill"
        case .checkingUP, .checkingDL, .checkingResumeData: return "arrow.triangle.2.circlepath"
        case .downloading, .forcedDL: return "arrow.down.circle.fill"
        case .stalledDL: return "arrow.down.circle"
        case .metaDL, .forcedMetaDL: return "doc.text.magnifyingglass"
        case .allocating: return "internaldrive"
        case .moving: return "folder.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .error, .missingFiles: return .red
        case .uploading, .forcedUP, .stalledUP, .queuedUP: return .green
        case .pausedUP, .stoppedUP: return .teal
        case .pausedDL, .stoppedDL: return .gray
        case .checkingUP, .checkingDL, .checkingResumeData, .moving, .allocating: return .orange
        case .downloading, .forcedDL, .metaDL, .forcedMetaDL: return .blue
        case .stalledDL, .queuedDL: return .indigo
        case .unknown: return .secondary
        }
    }
}

struct Torrent: Identifiable, Hashable, Sendable {
    let hash: String
    var id: String { hash }

    var name: String
    var state: TorrentState
    var progress: Double
    var size: Int64
    var totalSize: Int64
    var amountLeft: Int64
    var downloaded: Int64
    var uploaded: Int64
    var dlspeed: Int64
    var upspeed: Int64
    var dlLimit: Int64
    var upLimit: Int64
    var eta: Int64
    var ratio: Double
    var availability: Double
    var category: String
    var tags: [String]
    var tracker: String
    var addedOn: Int64
    var completionOn: Int64
    var lastActivity: Int64
    var timeActive: Int64
    var seedingTime: Int64
    var forceStart: Bool
    var seqDl: Bool
    var firstLastPiecePrio: Bool
    var autoTmm: Bool
    var numSeeds: Int
    var numComplete: Int
    var numLeechs: Int
    var numIncomplete: Int
    var savePath: String
    var contentPath: String
    var magnetURI: String
    var isPrivate: Bool

    init(hash: String, dict d: [String: JSONValue]) {
        self.hash = hash
        name = d.str("name")
        state = TorrentState(raw: d.str("state"))
        progress = d.dbl("progress")
        size = d.i64("size")
        totalSize = d.i64("total_size")
        amountLeft = d.i64("amount_left")
        downloaded = d.i64("downloaded")
        uploaded = d.i64("uploaded")
        dlspeed = d.i64("dlspeed")
        upspeed = d.i64("upspeed")
        dlLimit = d.i64("dl_limit")
        upLimit = d.i64("up_limit")
        eta = d.i64("eta")
        ratio = d.dbl("ratio")
        availability = d.dbl("availability")
        category = d.str("category")
        tags = d.str("tags")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        tracker = d.str("tracker")
        addedOn = d.i64("added_on")
        completionOn = d.i64("completion_on")
        lastActivity = d.i64("last_activity")
        timeActive = d.i64("time_active")
        seedingTime = d.i64("seeding_time")
        forceStart = d.bool("force_start")
        seqDl = d.bool("seq_dl")
        firstLastPiecePrio = d.bool("f_l_piece_prio")
        autoTmm = d.bool("auto_tmm")
        numSeeds = d.int("num_seeds")
        numComplete = d.int("num_complete")
        numLeechs = d.int("num_leechs")
        numIncomplete = d.int("num_incomplete")
        savePath = d.str("save_path")
        contentPath = d.str("content_path")
        magnetURI = d.str("magnet_uri")
        isPrivate = d.bool("isPrivate") || d.bool("private")
    }

    /// 對應 qBittorrent 的 isActive()
    var isActive: Bool {
        switch state {
        case .stalledDL: return upspeed > 0
        case .metaDL, .forcedMetaDL, .downloading, .forcedDL, .uploading, .forcedUP, .moving: return true
        default: return dlspeed > 0 || upspeed > 0
        }
    }

    var trackerHost: String {
        guard !tracker.isEmpty else { return "" }
        return URL(string: tracker)?.host ?? tracker
    }
}

struct TorrentCategory: Hashable, Sendable {
    var name: String
    var savePath: String
}
