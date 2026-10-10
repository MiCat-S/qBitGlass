import Foundation

/// sync/maindata 的 server_state。
struct ServerState: Equatable, Sendable {
    var raw: [String: JSONValue] = [:]

    var dlSpeed: Int64 { raw.i64("dl_info_speed") }
    var upSpeed: Int64 { raw.i64("up_info_speed") }
    var freeSpace: Int64? { raw["free_space_on_disk"]?.int }
    var altSpeedEnabled: Bool { raw.bool("use_alt_speed_limits") }
}
