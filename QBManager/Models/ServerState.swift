import Foundation

/// sync/maindata 的 server_state。
struct ServerState: Equatable, Sendable {
    var raw: [String: JSONValue] = [:]

    var dlSpeed: Int64 { raw.i64("dl_info_speed") }
    var upSpeed: Int64 { raw.i64("up_info_speed") }
    var dlSession: Int64 { raw.i64("dl_info_data") }
    var upSession: Int64 { raw.i64("up_info_data") }
    var dlLimit: Int64 { raw.i64("dl_rate_limit") }
    var upLimit: Int64 { raw.i64("up_rate_limit") }
    var allTimeDL: Int64 { raw.i64("alltime_dl") }
    var allTimeUL: Int64 { raw.i64("alltime_ul") }
    var freeSpace: Int64? { raw["free_space_on_disk"]?.int }
    var altSpeedEnabled: Bool { raw.bool("use_alt_speed_limits") }
    var connectionStatus: String { raw.str("connection_status") }
    var dhtNodes: Int { raw.int("dht_nodes") }
    var peers: Int { raw.int("total_peer_connections") }
    var globalRatio: String { raw.str("global_ratio") }

    var connectionLabel: String {
        switch connectionStatus {
        case "connected": return "已連線"
        case "firewalled": return "受防火牆限制"
        case "disconnected": return "已斷線"
        default: return connectionStatus
        }
    }
}
