import Foundation

struct UsageWindow {
    var percent: Double
    var resetsAt: Date?
}

enum RunStatus {
    case running, idle
}

struct ProviderUsage: Identifiable {
    let id: String
    let name: String
    var status: RunStatus = .idle
    var session: UsageWindow?
    var weekly: UsageWindow?
    var error: String?
}

enum FileScan {
    /// Ngưỡng coi provider là "đang chạy": log được ghi trong khoảng này.
    static let activeThreshold: TimeInterval = 120

    static func modDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    /// Các file .jsonl trong thư mục (không đệ quy), mới nhất trước.
    static func jsonlFiles(in dir: URL) -> [(URL, Date)] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return items.filter { $0.pathExtension == "jsonl" }
            .compactMap { url in modDate(url).map { (url, $0) } }
            .sorted { $0.1 > $1.1 }
    }

    static func status(lastWrite: Date?) -> RunStatus {
        guard let d = lastWrite else { return .idle }
        return Date().timeIntervalSince(d) < activeThreshold ? .running : .idle
    }

    /// Đọc tối đa `maxBytes` cuối file.
    static func tail(_ url: URL, maxBytes: UInt64 = 512 * 1024) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > maxBytes ? size - maxBytes : 0)
        guard let data = try? h.readToEnd() else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
