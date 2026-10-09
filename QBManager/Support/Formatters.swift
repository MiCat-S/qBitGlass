import Foundation

enum Fmt {
    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .binary
        f.allowsNonnumericFormatting = false
        return f
    }()

    static func bytes(_ v: Int64) -> String {
        v <= 0 ? "0 B" : byteFormatter.string(fromByteCount: v)
    }

    static func speed(_ v: Int64) -> String { bytes(v) + "/s" }

    static func limit(_ v: Int64) -> String { v <= 0 ? "無限制" : speed(v) }

    static func percent(_ p: Double) -> String {
        let v = p * 100
        return v >= 100 ? "100%" : String(format: "%.1f%%", v)
    }

    static func ratio(_ r: Double) -> String {
        r < 0 || r >= 9999 ? "∞" : String(format: "%.2f", r)
    }

    /// qB 以 8640000（100 天）表示無限
    static func eta(_ s: Int64) -> String {
        s < 0 || s >= 8_640_000 ? "∞" : duration(s)
    }

    static func duration(_ s: Int64) -> String {
        guard s > 0 else { return "0 秒" }
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60, sec = s % 60
        if d > 0 { return "\(d) 天 \(h) 時" }
        if h > 0 { return "\(h) 時 \(m) 分" }
        if m > 0 { return "\(m) 分 \(sec) 秒" }
        return "\(sec) 秒"
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    static func date(_ ts: Int64) -> String {
        ts <= 0 ? "—" : dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }
}
