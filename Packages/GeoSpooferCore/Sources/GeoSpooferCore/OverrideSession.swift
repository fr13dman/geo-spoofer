import Foundation

public struct SessionNotice: Equatable, Sendable {
    public var message: String
    public var stopped: Bool

    public init(message: String, stopped: Bool) {
        self.message = message
        self.stopped = stopped
    }
}

public actor OverrideSession {
    private var leases: [String: Lease]
    private var gate = DeviceCommandGate()
    private var busy = false
    private var cancelRequested = false
    private let store: LeaseStore
    private let audit: AuditLog
    private let commander: any LocationCommanding
    private let clock: any Clocking
    private let sleeper: any Sleeping
    private let reconciler = Reconciler()

    public init(
        directory: URL,
        commander: any LocationCommanding,
        clock: any Clocking = SystemClock(),
        sleeper: any Sleeping = ImmediateSleeper()
    ) throws {
        self.store = LeaseStore(fileURL: AppPaths.leaseFile(in: directory))
        self.audit = AuditLog(fileURL: AppPaths.auditFile(in: directory))
        self.commander = commander
        self.clock = clock
        self.sleeper = sleeper
        let loaded = try store.load()
        self.leases = Dictionary(uniqueKeysWithValues: loaded.map { ($0.deviceID, $0) })
    }

    public func currentLeases() -> [Lease] {
        Array(leases.values)
    }

    public func auditEntries() throws -> [AuditEntry] {
        try audit.load()
    }

    public func isStopped(_ deviceID: String) -> Bool {
        gate.isStopped(deviceID)
    }

    public func apply(
        candidate: CandidateFix?,
        device: Device?,
        duration: TimeInterval?,
        knownDeviceIDs: Set<String>
    ) async -> SessionNotice {
        let now = clock.now()
        switch ApplyDraft.prepare(
            candidate: candidate,
            device: device,
            duration: duration,
            now: now,
            knownDeviceIDs: knownDeviceIDs
        ) {
        case .rejected(let error):
            let name = device?.name ?? "No device"
            let id = device?.id ?? ""
            try? audit.append(
                AuditEntry(
                    timestamp: now,
                    deviceID: id,
                    deviceName: name,
                    command: .apply,
                    coordinate: candidate?.coordinate,
                    result: .failure,
                    failureReason: String(describing: error)
                )
            )
            return SessionNotice(message: UserMessage.applyFailed(String(describing: error)), stopped: false)
        case .ready(let prepared):
            guard let device else {
                return SessionNotice(message: UserMessage.applyFailed(String(describing: OverrideValidation.missingDevice)), stopped: false)
            }
            let command = LocationCommand.set(device: device, coordinate: prepared.coordinate)
            let outcome = await runSeries(
                deviceID: device.id,
                deviceName: device.name,
                commandKind: .apply,
                command: command,
                coordinate: prepared.coordinate,
                appliedAt: prepared.appliedAt,
                expiresAt: prepared.expiresAt,
                userInitiated: true
            )
            if outcome.succeeded {
                leases[device.id] = prepared
                try? store.save(Array(leases.values))
                return SessionNotice(
                    message: UserMessage.applied(deviceName: device.name, expiresAt: prepared.expiresAt),
                    stopped: false
                )
            }
            return SessionNotice(
                message: outcome.stopped
                    ? UserMessage.stopped(deviceName: device.name)
                    : UserMessage.applyFailed(outcome.failureReason ?? "Apply failed."),
                stopped: outcome.stopped
            )
        }
    }

    public func reset(device: Device) async -> SessionNotice {
        if leases[device.id] != nil {
            leases[device.id]?.phase = .pendingClear
            try? store.save(Array(leases.values))
        }
        guard device.connected else {
            return SessionNotice(
                message: "\(device.name) is disconnected. Clear will be sent when it is connected again.",
                stopped: false
            )
        }
        let lease = leases[device.id]
        let outcome = await runSeries(
            deviceID: device.id,
            deviceName: device.name,
            commandKind: .clear,
            command: LocationCommand.clear(device: device),
            coordinate: lease?.coordinate,
            appliedAt: lease?.appliedAt,
            expiresAt: lease?.expiresAt,
            userInitiated: true
        )
        if outcome.succeeded {
            leases[device.id] = nil
            try? store.save(Array(leases.values))
            return SessionNotice(message: UserMessage.cleared(deviceName: device.name), stopped: false)
        }
        return SessionNotice(
            message: outcome.stopped
                ? UserMessage.stopped(deviceName: device.name)
                : UserMessage.clearFailed(outcome.failureReason ?? "Clear failed."),
            stopped: outcome.stopped
        )
    }

    public func stop(devices: [Device]) async -> SessionNotice {
        cancelRequested = true
        while busy {
            await Task.yield()
        }
        cancelRequested = false
        var notes: [String] = []
        for device in devices where device.connected {
            let now = clock.now()
            try? audit.append(
                AuditEntry(
                    timestamp: now,
                    deviceID: device.id,
                    deviceName: device.name,
                    command: .stop,
                    coordinate: leases[device.id]?.coordinate,
                    appliedAt: leases[device.id]?.appliedAt,
                    expiresAt: leases[device.id]?.expiresAt,
                    result: .stopped,
                    failureReason: "Emergency stop."
                )
            )
            let outcome = await runSeries(
                deviceID: device.id,
                deviceName: device.name,
                commandKind: .clear,
                command: LocationCommand.clear(device: device),
                coordinate: leases[device.id]?.coordinate,
                appliedAt: leases[device.id]?.appliedAt,
                expiresAt: leases[device.id]?.expiresAt,
                userInitiated: true,
                singleAttempt: true
            )
            if outcome.succeeded {
                leases[device.id] = nil
                notes.append(UserMessage.cleared(deviceName: device.name))
            } else {
                gate.forceStop(device.id)
                notes.append(UserMessage.clearFailed(outcome.failureReason ?? "Clear failed."))
            }
        }
        try? store.save(Array(leases.values))
        let message = notes.isEmpty ? "Stop canceled automatic commands." : notes.joined(separator: " ")
        return SessionNotice(message: message, stopped: false)
    }

    public func performAutomatic(trigger: AutomaticTrigger, devices: [Device]) async {
        let connected = Set(devices.filter(\.connected).map(\.id))
        let planned = reconciler.plan(
            leases: Array(leases.values),
            connectedDeviceIDs: connected,
            stoppedDeviceIDs: gate.stopped,
            now: clock.now(),
            trigger: trigger
        )
        for command in planned {
            switch command {
            case .apply(let lease):
                guard let device = devices.first(where: { $0.id == lease.deviceID }) else { continue }
                let outcome = await runSeries(
                    deviceID: lease.deviceID,
                    deviceName: lease.deviceName,
                    commandKind: .apply,
                    command: LocationCommand.set(device: device, coordinate: lease.coordinate),
                    coordinate: lease.coordinate,
                    appliedAt: lease.appliedAt,
                    expiresAt: lease.expiresAt,
                    userInitiated: false
                )
                if outcome.succeeded {
                    leases[lease.deviceID] = lease
                    try? store.save(Array(leases.values))
                }
            case .clear(let deviceID, let deviceName):
                guard let device = devices.first(where: { $0.id == deviceID }) else { continue }
                let lease = leases[deviceID]
                let outcome = await runSeries(
                    deviceID: deviceID,
                    deviceName: deviceName,
                    commandKind: .clear,
                    command: LocationCommand.clear(device: device),
                    coordinate: lease?.coordinate,
                    appliedAt: lease?.appliedAt,
                    expiresAt: lease?.expiresAt,
                    userInitiated: false
                )
                if outcome.succeeded {
                    leases[deviceID] = nil
                    try? store.save(Array(leases.values))
                }
            }
        }
    }

    private struct SeriesOutcome {
        var succeeded: Bool
        var stopped: Bool
        var failureReason: String?
    }

    private func runSeries(
        deviceID: String,
        deviceName: String,
        commandKind: AuditCommand,
        command: LocationCommand,
        coordinate: Coordinate?,
        appliedAt: Date?,
        expiresAt: Date?,
        userInitiated: Bool,
        singleAttempt: Bool = false
    ) async -> SeriesOutcome {
        guard gate.begin(deviceID: deviceID, userInitiated: userInitiated) else {
            return SeriesOutcome(succeeded: false, stopped: true, failureReason: "Stopped.")
        }
        if busy {
            return SeriesOutcome(succeeded: false, stopped: false, failureReason: UserMessage.commandInFlight())
        }
        busy = true
        defer { busy = false }

        let attempts = singleAttempt ? 1 : RetrySchedule.attemptCount
        var failureReason: String?
        for index in 0..<attempts {
            if cancelRequested, !singleAttempt {
                return SeriesOutcome(succeeded: false, stopped: false, failureReason: "Canceled by Stop.")
            }
            let wait = RetrySchedule.backoff(beforeAttempt: index)
            if wait > 0 {
                await sleeper.sleep(seconds: wait)
            }
            let now = clock.now()
            do {
                _ = try await commander.run(command)
                gate.record(deviceID: deviceID, attemptIndex: index, succeeded: true)
                try? audit.append(
                    AuditEntry(
                        timestamp: now,
                        deviceID: deviceID,
                        deviceName: deviceName,
                        command: commandKind,
                        attemptNumber: index + 1,
                        coordinate: coordinate,
                        appliedAt: appliedAt,
                        expiresAt: expiresAt,
                        waitSeconds: wait,
                        result: .success
                    )
                )
                return SeriesOutcome(succeeded: true, stopped: false, failureReason: nil)
            } catch {
                failureReason = error.localizedDescription
                if let runner = error as? RunnerError {
                    failureReason = describe(runner)
                }
                gate.record(deviceID: deviceID, attemptIndex: index, succeeded: false)
                try? audit.append(
                    AuditEntry(
                        timestamp: now,
                        deviceID: deviceID,
                        deviceName: deviceName,
                        command: commandKind,
                        attemptNumber: index + 1,
                        coordinate: coordinate,
                        appliedAt: appliedAt,
                        expiresAt: expiresAt,
                        waitSeconds: wait,
                        result: .failure,
                        failureReason: failureReason
                    )
                )
                if gate.isStopped(deviceID) {
                    try? audit.append(AuditLog.stoppedEntry(deviceID: deviceID, deviceName: deviceName, now: clock.now()))
                    return SeriesOutcome(succeeded: false, stopped: true, failureReason: failureReason)
                }
            }
        }
        return SeriesOutcome(succeeded: false, stopped: gate.isStopped(deviceID), failureReason: failureReason)
    }

    private func describe(_ error: RunnerError) -> String {
        switch error {
        case .overlap:
            "A command is already in flight for this device."
        case .timedOut:
            "The command timed out after 30 seconds."
        case .settingsResetForbidden:
            "Refused to erase device content and settings."
        case .failed(let reason):
            reason
        }
    }
}
