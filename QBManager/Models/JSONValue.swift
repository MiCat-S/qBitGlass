import Foundation

/// 通用 JSON 值，用於合併 sync/maindata 的部分更新。
enum JSONValue: Codable, Sendable, Hashable {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Int64.self) { self = .int(v); return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    var string: String? {
        switch self {
        case .string(let v): return v
        case .int(let v): return String(v)
        case .double(let v): return String(v)
        case .bool(let v): return v ? "true" : "false"
        default: return nil
        }
    }

    var int: Int64? {
        switch self {
        case .int(let v): return v
        case .double(let v): return v.isFinite ? Int64(v) : nil
        case .bool(let v): return v ? 1 : 0
        case .string(let v): return Int64(v)
        default: return nil
        }
    }

    var double: Double? {
        switch self {
        case .int(let v): return Double(v)
        case .double(let v): return v
        case .string(let v): return Double(v)
        default: return nil
        }
    }

    var bool: Bool? {
        switch self {
        case .bool(let v): return v
        case .int(let v): return v != 0
        case .string(let v): return v == "true"
        default: return nil
        }
    }

    var array: [JSONValue]? {
        if case .array(let v) = self { return v }
        return nil
    }

    var object: [String: JSONValue]? {
        if case .object(let v) = self { return v }
        return nil
    }
}

extension Dictionary where Key == String, Value == JSONValue {
    func str(_ key: String) -> String { self[key]?.string ?? "" }
    func i64(_ key: String) -> Int64 { self[key]?.int ?? 0 }
    func int(_ key: String) -> Int { Int(self[key]?.int ?? 0) }
    func dbl(_ key: String) -> Double { self[key]?.double ?? 0 }
    func bool(_ key: String) -> Bool { self[key]?.bool ?? false }
}
