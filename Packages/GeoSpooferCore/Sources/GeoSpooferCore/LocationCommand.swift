import Foundation

public enum LocationCommand: Equatable, Sendable {
    case setSimulator(udid: String, coordinate: Coordinate)
    case clearSimulator(udid: String)
    case setPhone(id: String, coordinate: Coordinate)
    case clearPhone(id: String)

    public var deviceID: String {
        switch self {
        case .setSimulator(let udid, _), .clearSimulator(let udid):
            udid
        case .setPhone(let id, _), .clearPhone(let id):
            id
        }
    }

    public var isClear: Bool {
        switch self {
        case .clearSimulator, .clearPhone: true
        case .setSimulator, .setPhone: false
        }
    }

    public var arguments: [String] {
        switch self {
        case .setSimulator(let udid, let coordinate):
            ["xcrun", "simctl", "location", udid, "set", coordinate.commandPair]
        case .clearSimulator(let udid):
            ["xcrun", "simctl", "location", udid, "clear"]
        case .setPhone(let id, let coordinate):
            [
                "xcrun", "devicectl", "device", "simulate", "location", "coordinate",
                "--device", id,
                "--latitude=\(coordinate.latitude.commandToken)",
                "--longitude=\(coordinate.longitude.commandToken)"
            ]
        case .clearPhone(let id):
            ["xcrun", "devicectl", "device", "simulate", "location", "clear", "--device", id]
        }
    }

    public static func set(device: Device, coordinate: Coordinate) -> LocationCommand {
        switch device.kind {
        case .simulator:
            .setSimulator(udid: device.id, coordinate: coordinate)
        case .iPhone:
            .setPhone(id: device.id, coordinate: coordinate)
        }
    }

    public static func clear(device: Device) -> LocationCommand {
        switch device.kind {
        case .simulator:
            .clearSimulator(udid: device.id)
        case .iPhone:
            .clearPhone(id: device.id)
        }
    }

    /// `simctl location clear` stops the simulation and leaves the last fix in running apps.
    /// Restarting the Simulator's location service makes those apps drop it.
    public static func flushSimulatorLocationService(udid: String) -> [String] {
        ["xcrun", "simctl", "spawn", udid, "launchctl", "kickstart", "-k", "system/com.apple.locationd"]
    }
}

extension Coordinate {
    var commandPair: String {
        "\(latitude.commandToken),\(longitude.commandToken)"
    }
}

extension Double {
    var commandToken: String {
        var value = String(self)
        if value == "-0.0" { value = "0.0" }
        return value
    }
}

public enum CommandGuard {
    public static func check(_ arguments: [String]) throws(RunnerError) {
        let words = arguments.map { $0.lowercased() }
        if words.contains("settings"), words.contains("reset") {
            throw .settingsResetForbidden
        }
    }
}
