import Foundation

struct SessionLogParser {
    private let fileManager: FileManager
    private let maxFilesToScan: Int
    private let iso8601 = ISO8601DateFormatter()

    init(fileManager: FileManager = .default, maxFilesToScan: Int = 25) {
        self.fileManager = fileManager
        self.maxFilesToScan = maxFilesToScan
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func loadLatestSnapshot(from rootURL: URL) throws -> QuotaSnapshot? {
        let candidateFiles = try recentLogFiles(in: rootURL)

        for fileURL in candidateFiles {
            if let snapshot = try parseLatestSnapshot(in: fileURL) {
                return snapshot
            }
        }

        return nil
    }

    func recentLogFiles(in rootURL: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return []
        }

        let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var logFiles: [(url: URL, modifiedAt: Date)] = []

        while let fileURL = enumerator?.nextObject() as? URL {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values.isRegularFile == true, fileURL.pathExtension == "jsonl" else {
                continue
            }

            let modifiedAt = values.contentModificationDate ?? .distantPast
            logFiles.append((fileURL, modifiedAt))
        }

        return logFiles
            .sorted { lhs, rhs in
                if lhs.modifiedAt == rhs.modifiedAt {
                    return lhs.url.path > rhs.url.path
                }

                return lhs.modifiedAt > rhs.modifiedAt
            }
            .prefix(maxFilesToScan)
            .map(\.url)
    }

    func parseLatestSnapshot(in fileURL: URL) throws -> QuotaSnapshot? {
        let resourceValues = try fileURL.resourceValues(forKeys: [.contentModificationDateKey])
        let fallbackDate = resourceValues.contentModificationDate ?? .distantPast

        return try reverseScan(fileURL: fileURL) { lineData in
            guard !lineData.isEmpty else {
                return nil
            }

            let event = try? JSONDecoder().decode(SessionEnvelope.self, from: lineData)
            guard
                let event,
                event.type == "event_msg",
                event.payload?.type == "token_count",
                event.payload?.rateLimits?.limitID == "codex"
            else {
                return nil
            }

            let rateLimits = event.payload?.rateLimits
            let capturedAt = timestamp(from: event.timestamp) ?? fallbackDate

            return QuotaSnapshot(
                primary: QuotaWindow(
                    usedPercent: rateLimits?.primary?.usedPercent,
                    windowMinutes: rateLimits?.primary?.windowMinutes,
                    resetsAtEpoch: rateLimits?.primary?.resetsAt
                ),
                secondary: QuotaWindow(
                    usedPercent: rateLimits?.secondary?.usedPercent,
                    windowMinutes: rateLimits?.secondary?.windowMinutes,
                    resetsAtEpoch: rateLimits?.secondary?.resetsAt
                ),
                planType: rateLimits?.planType,
                capturedAt: capturedAt,
                sourceFile: fileURL
            )
        }
    }

    private func timestamp(from rawValue: String?) -> Date? {
        guard let rawValue else {
            return nil
        }

        return iso8601.date(from: rawValue) ?? ISO8601DateFormatter().date(from: rawValue)
    }

    private func reverseScan<T>(fileURL: URL, handler: (Data) throws -> T?) throws -> T? {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        let fileSize = try handle.seekToEnd()
        let chunkSize: UInt64 = 64 * 1024
        var buffer = Data()
        var position = fileSize

        while position > 0 {
            let readSize = min(chunkSize, position)
            position -= readSize

            try handle.seek(toOffset: position)
            guard let chunk = try handle.read(upToCount: Int(readSize)) else {
                continue
            }

            buffer.insert(contentsOf: chunk, at: 0)
            let parts = buffer.split(separator: 0x0A, omittingEmptySubsequences: false)

            if position > 0, let first = parts.first {
                buffer = Data(first)
                for part in parts.dropFirst().reversed() {
                    if let result = try handler(Data(part)) {
                        return result
                    }
                }
            } else {
                buffer.removeAll(keepingCapacity: false)
                for part in parts.reversed() {
                    if let result = try handler(Data(part)) {
                        return result
                    }
                }
            }
        }

        if !buffer.isEmpty {
            return try handler(buffer)
        }

        return nil
    }
}

private struct SessionEnvelope: Decodable {
    let timestamp: String?
    let type: String
    let payload: SessionPayload?
}

private struct SessionPayload: Decodable {
    let type: String?
    let rateLimits: RateLimitsPayload?

    enum CodingKeys: String, CodingKey {
        case type
        case rateLimits = "rate_limits"
    }
}

private struct RateLimitsPayload: Decodable {
    let limitID: String?
    let primary: QuotaWindowPayload?
    let secondary: QuotaWindowPayload?
    let planType: String?

    enum CodingKeys: String, CodingKey {
        case limitID = "limit_id"
        case primary
        case secondary
        case planType = "plan_type"
    }
}

private struct QuotaWindowPayload: Decodable {
    let usedPercent: Double?
    let windowMinutes: Int?
    let resetsAt: Double?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }
}
