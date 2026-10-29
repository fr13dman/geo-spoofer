import Foundation

public struct Coordinate: Equatable, Codable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct CandidateFix: Equatable, Codable, Sendable {
    public var coordinate: Coordinate
    public var label: String?

    public init(coordinate: Coordinate, label: String? = nil) {
        self.coordinate = coordinate
        self.label = label
    }
}

public enum DeviceKind: String, Codable, Sendable {
    case iPhone
    case simulator
}

public struct Device: Equatable, Codable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var kind: DeviceKind
    public var connected: Bool

    public init(id: String, name: String, kind: DeviceKind, connected: Bool) {
        self.id = id
        self.name = name
        self.kind = kind
        self.connected = connected
    }
}

public enum LeasePhase: String, Codable, Sendable {
    case active
    case pendingClear
}

public struct Lease: Equatable, Codable, Sendable, Identifiable {
    public var id: String { deviceID }
    public var deviceID: String
    public var deviceName: String
    public var coordinate: Coordinate
    public var appliedAt: Date
    public var expiresAt: Date
    public var phase: LeasePhase

    public init(
        deviceID: String,
        deviceName: String,
        coordinate: Coordinate,
        appliedAt: Date,
        expiresAt: Date,
        phase: LeasePhase
    ) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.coordinate = coordinate
        self.appliedAt = appliedAt
        self.expiresAt = expiresAt
        self.phase = phase
    }
}

public enum OverrideRules {
    public static let maxLease: TimeInterval = 24 * 60 * 60

    public static func validate(coordinate: Coordinate) throws(OverrideValidation) {
        guard coordinate.latitude.isFinite, coordinate.longitude.isFinite else {
            throw .nonFiniteCoordinate
        }
        guard (-90...90).contains(coordinate.latitude) else {
            throw .latitudeOutOfRange
        }
        guard (-180...180).contains(coordinate.longitude) else {
            throw .longitudeOutOfRange
        }
    }

    public static func validate(duration: TimeInterval) throws(OverrideValidation) {
        guard duration.isFinite, duration > 0 else {
            throw .expirationNotInFuture
        }
        guard duration <= maxLease else {
            throw .expirationTooFar
        }
    }

    public static func expirationDate(duration: TimeInterval, now: Date) throws(OverrideValidation) -> Date {
        try validate(duration: duration)
        return now.addingTimeInterval(duration)
    }
}

public enum OverrideValidation: Error, Equatable, Sendable {
    case nonFiniteCoordinate
    case latitudeOutOfRange
    case longitudeOutOfRange
    case missingCandidate
    case missingDuration
    case expirationNotInFuture
    case expirationTooFar
    case missingDevice
    case deviceNotListed
}

public enum UserMessage {
    public static func applied(deviceName: String, expiresAt: Date) -> String {
        "Location override is active on \(deviceName) until \(timestamp(expiresAt)). Apps can still detect a software-simulated location."
    }

    public static func applyFailed(_ reason: String) -> String {
        "Apply failed. \(reason)"
    }

    public static func cleared(deviceName: String) -> String {
        "\(deviceName) is using its live location."
    }

    public static func clearFailed(_ reason: String) -> String {
        "Clear failed. \(reason)"
    }

    public static func stopped(deviceName: String) -> String {
        "\(deviceName) is stopped. Reconnect, wake, and the expiration timer will not send again until you Apply, Reset, or open the app again."
    }

    public static func missingTools() -> String {
        "Xcode’s simctl or devicectl is missing. Install Xcode and select it with xcode-select."
    }

    public static func commandInFlight() -> String {
        "A command is already running for a device."
    }

    public static func searchFailed() -> String {
        "No place matched that search. The pin was left where it was."
    }

    public static func chooseMatch() -> String {
        "That search matched more than one place. Choose one before the pin moves."
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

public struct PlaceMatch: Equatable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var coordinate: Coordinate

    public init(id: String, label: String, coordinate: Coordinate) {
        self.id = id
        self.label = label
        self.coordinate = coordinate
    }
}

public struct PlaceSelection: Equatable, Sendable {
    public var candidate: CandidateFix?
    public var needsChoice: Bool
    public var message: String?

    public init(candidate: CandidateFix?, needsChoice: Bool, message: String?) {
        self.candidate = candidate
        self.needsChoice = needsChoice
        self.message = message
    }
}

public enum PlaceSearch {
    public static func resolve(matches: [PlaceMatch], previous: CandidateFix?) -> PlaceSelection {
        if matches.isEmpty {
            return PlaceSelection(candidate: previous, needsChoice: false, message: UserMessage.searchFailed())
        }
        if matches.count > 1 {
            return PlaceSelection(candidate: previous, needsChoice: true, message: UserMessage.chooseMatch())
        }
        let match = matches[0]
        return PlaceSelection(
            candidate: CandidateFix(coordinate: match.coordinate, label: match.label),
            needsChoice: false,
            message: nil
        )
    }

    /// The coordinate the map should show after a search. A failed search and a search that still needs a choice leave the map where it is.
    public static func mapCoordinate(selection: PlaceSelection, matches: [PlaceMatch]) -> Coordinate? {
        guard matches.count == 1, selection.needsChoice == false else { return nil }
        return selection.candidate?.coordinate
    }
}

public struct OverridePanel: Equatable, Sendable {
    public static let presets: [TimeInterval] = [15 * 60, 60 * 60, 4 * 60 * 60]

    public var candidate: CandidateFix?
    public var devices: [Device]
    public var selectedDeviceID: String?
    public var duration: TimeInterval?
    public var message: String

    public init(
        candidate: CandidateFix? = nil,
        devices: [Device] = [],
        selectedDeviceID: String? = nil,
        duration: TimeInterval? = nil,
        message: String = ""
    ) {
        self.candidate = candidate
        self.devices = devices
        self.selectedDeviceID = selectedDeviceID
        self.duration = duration
        self.message = message
    }

    public var selectedDevice: Device? {
        devices.first { $0.id == selectedDeviceID }
    }

    public var canApply: Bool {
        guard let candidate, let duration, let device = selectedDevice, device.connected else {
            return false
        }
        do {
            try OverrideRules.validate(coordinate: candidate.coordinate)
            try OverrideRules.validate(duration: duration)
            return true
        } catch {
            return false
        }
    }
}

public enum ApplyPreparation: Equatable, Sendable {
    case rejected(OverrideValidation)
    case ready(Lease)
}

public enum ApplyDraft {
    public static func prepare(
        candidate: CandidateFix?,
        device: Device?,
        duration: TimeInterval?,
        now: Date,
        knownDeviceIDs: Set<String>
    ) -> ApplyPreparation {
        guard let candidate else { return .rejected(.missingCandidate) }
        do {
            try OverrideRules.validate(coordinate: candidate.coordinate)
        } catch {
            return .rejected(error)
        }
        guard let duration else { return .rejected(.missingDuration) }
        let expiresAt: Date
        do {
            expiresAt = try OverrideRules.expirationDate(duration: duration, now: now)
        } catch {
            return .rejected(error)
        }
        guard let device else { return .rejected(.missingDevice) }
        guard device.connected, knownDeviceIDs.contains(device.id) else {
            return .rejected(.deviceNotListed)
        }
        return .ready(
            Lease(
                deviceID: device.id,
                deviceName: device.name,
                coordinate: candidate.coordinate,
                appliedAt: now,
                expiresAt: expiresAt,
                phase: .active
            )
        )
    }
}
