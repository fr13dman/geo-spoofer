import Foundation

public enum AutomaticTrigger: Equatable, Sendable {
    case launch
    case wake
    case reconnect
    case expiration
}

public enum PlannedCommand: Equatable, Sendable {
    case apply(Lease)
    case clear(deviceID: String, deviceName: String)
}

public struct Reconciler: Sendable {
    public init() {}

    public func plan(
        leases: [Lease],
        connectedDeviceIDs: Set<String>,
        stoppedDeviceIDs: Set<String>,
        now: Date,
        trigger: AutomaticTrigger
    ) -> [PlannedCommand] {
        leases.compactMap { lease in
            guard connectedDeviceIDs.contains(lease.deviceID) else { return nil }
            guard !stoppedDeviceIDs.contains(lease.deviceID) else { return nil }
            let due = lease.phase == .pendingClear || lease.expiresAt <= now
            if due {
                return .clear(deviceID: lease.deviceID, deviceName: lease.deviceName)
            }
            switch trigger {
            case .launch, .wake, .reconnect:
                return .apply(lease)
            case .expiration:
                return nil
            }
        }
    }
}
