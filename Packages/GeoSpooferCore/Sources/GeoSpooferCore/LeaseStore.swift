import Foundation

public struct LeaseStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> [Lease] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONCoding.decoder.decode(LeaseFile.self, from: data).leases
    }

    public func save(_ leases: [Lease]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONCoding.encoder.encode(LeaseFile(leases: leases))
        try data.write(to: fileURL, options: .atomic)
    }
}

struct LeaseFile: Codable, Sendable {
    var leases: [Lease]
}

public enum AppPaths {
    public static func supportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GeoSpoofer", isDirectory: true)
    }

    public static func leaseFile(in directory: URL = supportDirectory()) -> URL {
        directory.appendingPathComponent("leases.json")
    }

    public static func auditFile(in directory: URL = supportDirectory()) -> URL {
        directory.appendingPathComponent("location-log.jsonl")
    }

    public static func lockFile(in directory: URL = supportDirectory()) -> URL {
        directory.appendingPathComponent("instance.pid")
    }
}

public enum InstanceHandoff {
    public static func shouldExit(existingPID: Int32?, currentPID: Int32, isAlive: (Int32) -> Bool) -> Bool {
        guard let existingPID, existingPID != currentPID else { return false }
        return isAlive(existingPID)
    }

    public static func pid(in contents: String) -> Int32? {
        Int32(contents.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
