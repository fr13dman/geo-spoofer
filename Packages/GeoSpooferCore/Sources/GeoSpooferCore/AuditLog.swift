import Foundation

public enum AuditCommand: String, Codable, Sendable {
    case apply
    case clear
    case stop
}

public enum AuditResult: String, Codable, Sendable {
    case success
    case failure
    case stopped
}

public struct AuditEntry: Equatable, Codable, Identifiable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var deviceID: String
    public var deviceName: String
    public var command: AuditCommand
    public var attemptNumber: Int?
    public var coordinate: Coordinate?
    public var appliedAt: Date?
    public var expiresAt: Date?
    public var waitSeconds: TimeInterval?
    public var result: AuditResult
    public var failureReason: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        deviceID: String,
        deviceName: String,
        command: AuditCommand,
        attemptNumber: Int? = nil,
        coordinate: Coordinate? = nil,
        appliedAt: Date? = nil,
        expiresAt: Date? = nil,
        waitSeconds: TimeInterval? = nil,
        result: AuditResult,
        failureReason: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.command = command
        self.attemptNumber = attemptNumber
        self.coordinate = coordinate
        self.appliedAt = appliedAt
        self.expiresAt = expiresAt
        self.waitSeconds = waitSeconds
        self.result = result
        self.failureReason = failureReason
    }

    public var summary: String {
        var parts = [timestampLabel, deviceName, command.rawValue, result.rawValue]
        if let attemptNumber {
            parts.append("attempt \(attemptNumber)")
        }
        if let coordinate {
            parts.append("\(coordinate.latitude),\(coordinate.longitude)")
        }
        if let expiresAt {
            parts.append("expires \(AuditLog.timestamp(expiresAt))")
        }
        if let waitSeconds, waitSeconds > 0 {
            parts.append("wait \(waitSeconds)s")
        }
        if let failureReason, !failureReason.isEmpty {
            parts.append(failureReason)
        }
        return parts.joined(separator: " · ")
    }

    private var timestampLabel: String {
        AuditLog.timestamp(timestamp)
    }
}

public struct AuditLog: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func append(_ entry: AuditEntry) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONCoding.encoder.encode(entry)
        guard var line = String(data: data, encoding: .utf8) else {
            throw CocoaError(.coderReadCorrupt)
        }
        if !line.hasSuffix("\n") {
            line.append("\n")
        }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            if let encoded = line.data(using: .utf8) {
                try handle.write(contentsOf: encoded)
            }
            try handle.close()
        } else {
            try Data(line.utf8).write(to: fileURL)
        }
    }

    public func load() throws -> [AuditEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        return try text.split(whereSeparator: \.isNewline).map { line in
            try JSONCoding.decoder.decode(AuditEntry.self, from: Data(line.utf8))
        }
    }

    public static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    public static func stoppedEntry(deviceID: String, deviceName: String, now: Date) -> AuditEntry {
        AuditEntry(
            timestamp: now,
            deviceID: deviceID,
            deviceName: deviceName,
            command: .stop,
            result: .stopped,
            failureReason: "Stopped after 3 retries. Reconnect, wake, and the expiration timer will not send again until you Apply, Reset, or open the app again."
        )
    }
}

enum JSONCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
