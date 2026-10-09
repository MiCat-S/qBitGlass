import Foundation

struct MultipartForm: Sendable {
    let boundary = "QBManager-\(UUID().uuidString)"
    private(set) var parts = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func add(_ name: String, _ value: String) {
        parts.append("--\(boundary)\r\n")
        parts.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        parts.append(value)
        parts.append("\r\n")
    }

    mutating func addFile(_ name: String, filename: String, mime: String, data: Data) {
        let safeName = filename.replacingOccurrences(of: "\"", with: "'")
        parts.append("--\(boundary)\r\n")
        parts.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(safeName)\"\r\n")
        parts.append("Content-Type: \(mime)\r\n\r\n")
        parts.append(data)
        parts.append("\r\n")
    }

    var body: Data {
        var d = parts
        d.append("--\(boundary)--\r\n")
        return d
    }
}

private extension Data {
    mutating func append(_ s: String) { append(Data(s.utf8)) }
}
