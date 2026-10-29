import Foundation
import Testing
@testable import GeoSpooferCore

@Test func simulatorProbeReadsTheAppliedCoordinate() async throws {
    guard ProcessInfo.processInfo.environment["RUN_SIMULATOR_TESTS"] == "1" else { return }
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let project = root.appendingPathComponent("GeoSpoofer.xcodeproj")
    let derived = root.appendingPathComponent(".build/probe-dd")
    try run("/usr/bin/xcodebuild", [
        "-project", project.path,
        "-scheme", "GeoSpooferProbe",
        "-destination", "generic/platform=iOS Simulator",
        "-derivedDataPath", derived.path,
        "-configuration", "Debug",
        "build"
    ])
    let udid = try bootedOrFirstSimulator()
    _ = try? run("/usr/bin/xcrun", ["simctl", "boot", udid])
    try run("/usr/bin/xcrun", ["simctl", "bootstatus", udid, "-b"])
    let app = try findApp(named: "GeoSpooferProbe.app", under: derived)
    try run("/usr/bin/xcrun", ["simctl", "install", udid, app.path])
    try run("/usr/bin/xcrun", ["simctl", "privacy", udid, "grant", "location-when-in-use", "com.geospoofer.probe"])
    try run("/usr/bin/xcrun", ["simctl", "launch", udid, "com.geospoofer.probe"])
    let coordinate = Coordinate(latitude: 37.7749, longitude: -122.4194)
    let runner = ProcessCommandRunner(spawner: SystemProcessSpawner())
    _ = try await runner.run(.setSimulator(udid: udid, coordinate: coordinate))
    let container = try run("/usr/bin/xcrun", ["simctl", "get_app_container", udid, "com.geospoofer.probe", "data"])
    let report = URL(fileURLWithPath: container.trimmingCharacters(in: .whitespacesAndNewlines))
        .appendingPathComponent("Documents/reported-location.txt")
    let line = try await waitForReport(at: report)
    let parts = line.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
    #expect(parts.count == 2)
    #expect(abs((parts[0] ?? 0) - coordinate.latitude) < 0.02)
    #expect(abs((parts[1] ?? 0) - coordinate.longitude) < 0.02)
    _ = try await runner.run(.clearSimulator(udid: udid))
}

private func bootedOrFirstSimulator() throws -> String {
    let booted = try run("/usr/bin/xcrun", ["simctl", "list", "devices", "booted", "-j"])
    if let id = firstUDID(in: Data(booted.utf8), state: "Booted") { return id }
    let available = try run("/usr/bin/xcrun", ["simctl", "list", "devices", "available", "-j"])
    guard let id = firstUDID(in: Data(available.utf8), state: nil) else {
        throw ProbeError("No iOS Simulator is available.")
    }
    return id
}

private func firstUDID(in data: Data, state: String?) -> String? {
    guard
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let devices = root["devices"] as? [String: Any]
    else { return nil }
    for value in devices.values {
        guard let entries = value as? [[String: Any]] else { continue }
        for entry in entries {
            let entryState = entry["state"] as? String
            if let state, entryState != state { continue }
            if let udid = entry["udid"] as? String, (entry["isAvailable"] as? Bool) != false {
                let name = (entry["name"] as? String) ?? ""
                if name.contains("iPhone") { return udid }
            }
        }
    }
    return nil
}

private func findApp(named name: String, under root: URL) throws -> URL {
    let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
    while let url = enumerator?.nextObject() as? URL {
        if url.lastPathComponent == name { return url }
    }
    throw ProbeError("Could not find \(name).")
}

private func waitForReport(at url: URL) async throws -> String {
    let deadline = Date().addingTimeInterval(20)
    while Date() < deadline {
        if let text = try? String(contentsOf: url, encoding: .utf8), text.contains(",") {
            return text
        }
        try await Task.sleep(nanoseconds: 500_000_000)
    }
    throw ProbeError("The probe did not write a location.")
}

@discardableResult
private func run(_ launch: String, _ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launch)
    process.arguments = arguments
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    guard process.terminationStatus == 0 else {
        throw ProbeError(error.isEmpty ? output : error)
    }
    return output
}

private struct ProbeError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}
