import Foundation

public enum RetrySchedule {
    public static let retryWaits: [TimeInterval] = [2, 4, 8]
    public static let minimumGap: TimeInterval = 5
    public static let timeout: TimeInterval = 30
    public static let maximumRetries = 3
    public static var attemptCount: Int { maximumRetries + 1 }

    public static func backoff(beforeAttempt index: Int) -> TimeInterval {
        guard index > 0, index - 1 < retryWaits.count else { return 0 }
        return retryWaits[index - 1]
    }
}

public struct DeviceCommandGate: Equatable, Sendable {
    public private(set) var stopped: Set<String> = []

    public init() {}

    public func isStopped(_ deviceID: String) -> Bool {
        stopped.contains(deviceID)
    }

    public mutating func begin(deviceID: String, userInitiated: Bool) -> Bool {
        if userInitiated {
            stopped.remove(deviceID)
            return true
        }
        return !stopped.contains(deviceID)
    }

    public mutating func record(deviceID: String, attemptIndex: Int, succeeded: Bool) {
        guard !succeeded else { return }
        if attemptIndex >= RetrySchedule.maximumRetries {
            stopped.insert(deviceID)
        }
    }

    public mutating func forceStop(_ deviceID: String) {
        stopped.insert(deviceID)
    }
}
