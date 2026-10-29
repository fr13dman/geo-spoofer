import Foundation
import os
import Testing
@testable import GeoSpooferCore

private let sanFrancisco = Coordinate(latitude: 37.7749, longitude: -122.4194)
private let tokyo = Coordinate(latitude: 35.6812, longitude: 139.7671)
private let now = Date(timeIntervalSince1970: 1_700_000_000)

private func phone(_ id: String = "phone-1", name: String = "iPhone", connected: Bool = true) -> Device {
    Device(id: id, name: name, kind: .iPhone, connected: connected)
}

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}

@Test func rejectsCoordinatesAndDurations() {
    #expect(throws: OverrideValidation.nonFiniteCoordinate) {
        try OverrideRules.validate(coordinate: Coordinate(latitude: .nan, longitude: 0))
    }
    #expect(throws: OverrideValidation.latitudeOutOfRange) {
        try OverrideRules.validate(coordinate: Coordinate(latitude: 90.1, longitude: 0))
    }
    #expect(throws: OverrideValidation.longitudeOutOfRange) {
        try OverrideRules.validate(coordinate: Coordinate(latitude: 0, longitude: -180.1))
    }
    #expect(throws: Never.self) {
        try OverrideRules.validate(coordinate: Coordinate(latitude: 90, longitude: 180))
    }
    #expect(throws: OverrideValidation.expirationNotInFuture) {
        try OverrideRules.validate(duration: 0)
    }
    #expect(throws: OverrideValidation.expirationTooFar) {
        try OverrideRules.validate(duration: OverrideRules.maxLease + 1)
    }
}

@Test func missingCandidateAndUnlistedDeviceAreRejected() {
    let missing = ApplyDraft.prepare(candidate: nil, device: phone(), duration: 60, now: now, knownDeviceIDs: ["phone-1"])
    #expect(missing == .rejected(.missingCandidate))
    let unlisted = ApplyDraft.prepare(
        candidate: CandidateFix(coordinate: sanFrancisco),
        device: phone(),
        duration: 60,
        now: now,
        knownDeviceIDs: []
    )
    #expect(unlisted == .rejected(.deviceNotListed))
}

@Test func prepareApplyStoresAbsoluteExpiration() throws {
    let prepared = ApplyDraft.prepare(
        candidate: CandidateFix(coordinate: sanFrancisco, label: "ZIP"),
        device: phone(),
        duration: 15 * 60,
        now: now,
        knownDeviceIDs: ["phone-1"]
    )
    guard case .ready(let lease) = prepared else {
        Issue.record("expected a lease")
        return
    }
    #expect(lease.expiresAt == now.addingTimeInterval(15 * 60))
    #expect(lease.coordinate == sanFrancisco)
    #expect(lease.phase == .active)
}

@Test func searchDoesNotMoveThePinUntilOneMatchIsChosen() {
    let previous = CandidateFix(coordinate: tokyo, label: "Tokyo")
    let empty = PlaceSearch.resolve(matches: [], previous: previous)
    #expect(empty.candidate == previous)
    #expect(empty.message == UserMessage.searchFailed())

    let many = PlaceSearch.resolve(
        matches: [
            PlaceMatch(id: "a", label: "A", coordinate: sanFrancisco),
            PlaceMatch(id: "b", label: "B", coordinate: tokyo)
        ],
        previous: previous
    )
    #expect(many.needsChoice)
    #expect(many.candidate == previous)

    let one = PlaceSearch.resolve(
        matches: [PlaceMatch(id: "a", label: "Market", coordinate: sanFrancisco)],
        previous: previous
    )
    #expect(one.candidate?.coordinate == sanFrancisco)
    #expect(one.needsChoice == false)
    #expect(PlaceSearch.mapCoordinate(selection: empty, matches: []) == nil)
    #expect(PlaceSearch.mapCoordinate(selection: many, matches: [
        PlaceMatch(id: "a", label: "A", coordinate: sanFrancisco),
        PlaceMatch(id: "b", label: "B", coordinate: tokyo)
    ]) == nil)
    #expect(PlaceSearch.mapCoordinate(selection: one, matches: [
        PlaceMatch(id: "a", label: "Market", coordinate: sanFrancisco)
    ]) == sanFrancisco)
}

@Test func durationDialSnapsAroundTheClock() {
    #expect(DurationDial.minutes(atClockDegrees: DurationDial.startDegrees) == 0)
    #expect(DurationDial.minutes(atClockDegrees: 0) == 12 * 60)
    #expect(DurationDial.minutes(atClockDegrees: DurationDial.startDegrees + DurationDial.sweepDegrees) == 24 * 60)
    #expect(DurationDial.minutes(atClockDegrees: 180) == 0)
    #expect(DurationDial.clockDegrees(dx: 0, dy: -1) == 0)
    #expect(DurationDial.clockDegrees(dx: 1, dy: 0) == 90)
    #expect(DurationDial.label(forMinutes: 0) == "Choose a duration")
    #expect(DurationDial.label(forMinutes: 15) == "15 minutes")
    #expect(DurationDial.label(forMinutes: 60) == "1 hour")
    #expect(DurationDial.label(forMinutes: 4 * 60 + 15) == "4h 15m")
}

@Test func applyStaysDisabledUntilTheFormIsComplete() {
    var panel = OverridePanel()
    #expect(!panel.canApply)
    panel.candidate = CandidateFix(coordinate: sanFrancisco)
    panel.duration = 60
    #expect(!panel.canApply)
    panel.devices = [phone()]
    panel.selectedDeviceID = "phone-1"
    #expect(panel.canApply)
    panel.duration = OverrideRules.maxLease + 1
    #expect(!panel.canApply)
    panel.duration = 60
    panel.devices = [phone(connected: false)]
    #expect(!panel.canApply)
}

@Test func reconcilerClearsWhenDueAndReappliesWhileTheLeaseIsActive() {
    let reconciler = Reconciler()
    let active = Lease(
        deviceID: "phone-1",
        deviceName: "iPhone",
        coordinate: tokyo,
        appliedAt: now,
        expiresAt: now.addingTimeInterval(600),
        phase: .active
    )
    let expired = Lease(
        deviceID: "phone-1",
        deviceName: "iPhone",
        coordinate: tokyo,
        appliedAt: now,
        expiresAt: now,
        phase: .active
    )
    #expect(
        reconciler.plan(
            leases: [active],
            connectedDeviceIDs: ["phone-1"],
            stoppedDeviceIDs: [],
            now: now,
            trigger: .reconnect
        ) == [.apply(active)]
    )
    #expect(
        reconciler.plan(
            leases: [expired],
            connectedDeviceIDs: ["phone-1"],
            stoppedDeviceIDs: [],
            now: now,
            trigger: .expiration
        ) == [.clear(deviceID: "phone-1", deviceName: "iPhone")]
    )
    #expect(
        reconciler.plan(
            leases: [active],
            connectedDeviceIDs: [],
            stoppedDeviceIDs: [],
            now: now,
            trigger: .launch
        ).isEmpty
    )
    #expect(
        reconciler.plan(
            leases: [expired],
            connectedDeviceIDs: ["phone-1"],
            stoppedDeviceIDs: ["phone-1"],
            now: now,
            trigger: .launch
        ).isEmpty
    )
    #expect(
        reconciler.plan(
            leases: [active],
            connectedDeviceIDs: ["phone-1"],
            stoppedDeviceIDs: [],
            now: now,
            trigger: .expiration
        ).isEmpty
    )
}

@Test func threeFailuresStopTheDeviceAndAUserActionStartsANewSeries() {
    var gate = DeviceCommandGate()
    let started = gate.begin(deviceID: "phone-1", userInitiated: false)
    #expect(started)
    for index in 0..<RetrySchedule.maximumRetries {
        gate.record(deviceID: "phone-1", attemptIndex: index, succeeded: false)
        #expect(!gate.isStopped("phone-1"))
    }
    gate.record(deviceID: "phone-1", attemptIndex: RetrySchedule.maximumRetries, succeeded: false)
    #expect(gate.isStopped("phone-1"))
    let blocked = gate.begin(deviceID: "phone-1", userInitiated: false)
    #expect(!blocked)
    let restarted = gate.begin(deviceID: "phone-1", userInitiated: true)
    #expect(restarted)
    #expect(!gate.isStopped("phone-1"))
    #expect(RetrySchedule.backoff(beforeAttempt: 1) == 2)
    #expect(RetrySchedule.backoff(beforeAttempt: 2) == 4)
    #expect(RetrySchedule.backoff(beforeAttempt: 3) == 8)
}

@Test func leaseStoreReloadsAfterARelaunch() throws {
    let directory = temporaryDirectory()
    let store = LeaseStore(fileURL: AppPaths.leaseFile(in: directory))
    let lease = Lease(
        deviceID: "sim-1",
        deviceName: "iPhone 16",
        coordinate: sanFrancisco,
        appliedAt: now,
        expiresAt: now.addingTimeInterval(3600),
        phase: .pendingClear
    )
    try store.save([lease])
    let reloaded = try LeaseStore(fileURL: AppPaths.leaseFile(in: directory)).load()
    #expect(reloaded == [lease])
}

@Test func auditLogKeepsOneLinePerAttempt() throws {
    let url = temporaryDirectory().appendingPathComponent("location-log.jsonl")
    let log = AuditLog(fileURL: url)
    let entry = AuditEntry(
        timestamp: now,
        deviceID: "phone-1",
        deviceName: "iPhone",
        command: .apply,
        attemptNumber: 2,
        coordinate: sanFrancisco,
        appliedAt: now,
        expiresAt: now.addingTimeInterval(60),
        waitSeconds: 2,
        result: .failure,
        failureReason: "locked"
    )
    try log.append(entry)
    try log.append(AuditLog.stoppedEntry(deviceID: "phone-1", deviceName: "iPhone", now: now))
    let loaded = try log.load()
    #expect(loaded.count == 2)
    #expect(loaded[0].attemptNumber == 2)
    #expect(loaded[0].waitSeconds == 2)
    #expect(loaded[0].expiresAt == now.addingTimeInterval(60))
    #expect(loaded[1].result == .stopped)
}

@Test func failedApplyKeepsThePreviousLeaseAndLogsEveryAttempt() async throws {
    let commander = ScriptedCommander(results: Array(repeating: .failure("Developer Mode is off."), count: 4))
    let clock = ManualClock(now)
    let directory = temporaryDirectory()
    let existing = Lease(
        deviceID: "phone-1",
        deviceName: "iPhone",
        coordinate: tokyo,
        appliedAt: now,
        expiresAt: now.addingTimeInterval(2400),
        phase: .active
    )
    try LeaseStore(fileURL: AppPaths.leaseFile(in: directory)).save([existing])
    let reloaded = try OverrideSession(directory: directory, commander: commander, clock: clock, sleeper: ImmediateSleeper())
    let notice = await reloaded.apply(
        candidate: CandidateFix(coordinate: sanFrancisco),
        device: phone(),
        duration: 600,
        knownDeviceIDs: ["phone-1"]
    )
    #expect(notice.stopped)
    #expect(await reloaded.currentLeases() == [existing])
    let entries = try await reloaded.auditEntries()
    #expect(entries.filter { $0.command == .apply }.count == 4)
    #expect(entries.contains { $0.result == .stopped })
    #expect(commander.commands.count == 4)
    #expect(commander.commands.allSatisfy { $0.arguments.contains("--latitude") })
}

@Test func successfulApplyReplacesTheLease() async throws {
    let commander = ScriptedCommander(results: [.success])
    let session = try OverrideSession(directory: temporaryDirectory(), commander: commander, clock: ManualClock(now))
    let notice = await session.apply(
        candidate: CandidateFix(coordinate: sanFrancisco, label: "Pin"),
        device: phone(),
        duration: 60,
        knownDeviceIDs: ["phone-1"]
    )
    #expect(notice.message.contains("iPhone"))
    #expect(notice.message.contains("software-simulated"))
    let leases = await session.currentLeases()
    #expect(leases.count == 1)
    #expect(leases[0].coordinate == sanFrancisco)
}

@Test func resetWithoutALeaseStillClearsAndAFailedResetKeepsPendingClear() async throws {
    let succeeding = ScriptedCommander(results: [.success])
    let open = try OverrideSession(directory: temporaryDirectory(), commander: succeeding, clock: ManualClock(now))
    let cleared = await open.reset(device: phone())
    #expect(cleared.message.contains("live location"))
    #expect(succeeding.commands == [.clearPhone(id: "phone-1")])

    let failing = ScriptedCommander(results: Array(repeating: .failure("locked"), count: 4))
    let directory = temporaryDirectory()
    let seeded = Lease(
        deviceID: "phone-1",
        deviceName: "iPhone",
        coordinate: tokyo,
        appliedAt: now,
        expiresAt: now.addingTimeInterval(600),
        phase: .active
    )
    try LeaseStore(fileURL: AppPaths.leaseFile(in: directory)).save([seeded])
    let session = try OverrideSession(directory: directory, commander: failing, clock: ManualClock(now))
    _ = await session.reset(device: phone())
    let leases = await session.currentLeases()
    #expect(leases.count == 1)
    #expect(leases[0].phase == .pendingClear)
    #expect(leases[0].coordinate == tokyo)
}

@Test func relaunchClearsAnExpiredLeaseAndReappliesAnActiveOne() async throws {
    let commander = ScriptedCommander(results: [.success])
    let directory = temporaryDirectory()
    let active = Lease(
        deviceID: "sim-1",
        deviceName: "iPhone 16",
        coordinate: sanFrancisco,
        appliedAt: now,
        expiresAt: now.addingTimeInterval(600),
        phase: .active
    )
    try LeaseStore(fileURL: AppPaths.leaseFile(in: directory)).save([active])
    let session = try OverrideSession(directory: directory, commander: commander, clock: ManualClock(now.addingTimeInterval(10)))
    let simulator = Device(id: "sim-1", name: "iPhone 16", kind: .simulator, connected: true)
    await session.performAutomatic(trigger: .launch, devices: [simulator])
    #expect(commander.commands == [.setSimulator(udid: "sim-1", coordinate: sanFrancisco)])
    let kept = await session.currentLeases()
    #expect(kept.first?.expiresAt == active.expiresAt)

    let expiring = ScriptedCommander(results: [.success])
    let expiredDirectory = temporaryDirectory()
    try LeaseStore(fileURL: AppPaths.leaseFile(in: expiredDirectory)).save([
        Lease(
            deviceID: "sim-1",
            deviceName: "iPhone 16",
            coordinate: sanFrancisco,
            appliedAt: now,
            expiresAt: now,
            phase: .active
        )
    ])
    let expired = try OverrideSession(directory: expiredDirectory, commander: expiring, clock: ManualClock(now))
    await expired.performAutomatic(trigger: .launch, devices: [simulator])
    #expect(expiring.commands == [.clearSimulator(udid: "sim-1")])
    #expect(await expired.currentLeases().isEmpty)
}

@Test func stoppedDeviceIsNotSentAgainUntilReset() async throws {
    let commander = ScriptedCommander(results: Array(repeating: .failure("nope"), count: 8))
    let directory = temporaryDirectory()
    let lease = Lease(
        deviceID: "phone-1",
        deviceName: "iPhone",
        coordinate: tokyo,
        appliedAt: now,
        expiresAt: now.addingTimeInterval(30),
        phase: .active
    )
    try LeaseStore(fileURL: AppPaths.leaseFile(in: directory)).save([lease])
    let session = try OverrideSession(directory: directory, commander: commander, clock: ManualClock(now.addingTimeInterval(60)))
    await session.performAutomatic(trigger: .expiration, devices: [phone()])
    let afterStop = commander.commands.count
    #expect(afterStop == 4)
    await session.performAutomatic(trigger: .reconnect, devices: [phone()])
    #expect(commander.commands.count == afterStop)
    _ = await session.reset(device: phone())
    #expect(commander.commands.count == afterStop + 4)
}

@Test func locationCommandsMatchTheXcodeTools() {
    let setSimulator = LocationCommand.setSimulator(udid: "SIM", coordinate: sanFrancisco)
    #expect(setSimulator.arguments == ["xcrun", "simctl", "location", "SIM", "set", "37.7749,-122.4194"])
    #expect(LocationCommand.clearSimulator(udid: "SIM").arguments == ["xcrun", "simctl", "location", "SIM", "clear"])
    let setPhone = LocationCommand.setPhone(id: "UDID", coordinate: sanFrancisco)
    #expect(
        setPhone.arguments == [
            "xcrun", "devicectl", "device", "simulate", "location", "coordinate",
            "--device", "UDID", "--latitude", "37.7749", "--longitude", "-122.4194"
        ]
    )
    #expect(
        LocationCommand.clearPhone(id: "UDID").arguments == [
            "xcrun", "devicectl", "device", "simulate", "location", "clear", "--device", "UDID"
        ]
    )
    #expect(throws: RunnerError.settingsResetForbidden) {
        try CommandGuard.check(["xcrun", "devicectl", "device", "settings", "reset", "--device", "UDID"])
    }
}

@Test func deviceListsKeepBootedSimulatorsAndAvailablePhones() throws {
    let simulators = try DeviceListParser.simulators(from: Data(simulatorFixture.utf8))
    #expect(simulators.map(\.id) == ["BOOTED"])
    let phones = try DeviceListParser.phones(from: Data(phoneFixture.utf8))
    #expect(phones.map(\.name) == ["Pocket"])
    #expect(phones.map(\.kind) == [.iPhone])
}

@Test func runnerEnforcesTheGapTheTimeoutAndASingleInFlightCommand() async throws {
    let sleeper = RecordingSleeper()
    let clock = ManualClock(now)
    let runner = ProcessCommandRunner(spawner: ScriptedSpawner(result: .success(ProcessOutput(status: 0, stdout: "", stderr: ""))), sleeper: sleeper, clock: clock)
    _ = try await runner.run(.clearPhone(id: "phone-1"))
    _ = try await runner.run(.clearPhone(id: "phone-1"))
    #expect(sleeper.delays == [5])

    let timingOut = ProcessCommandRunner(
        spawner: ScriptedSpawner(result: .failure(RunnerError.timedOut)),
        sleeper: ImmediateSleeper(),
        clock: ManualClock(now)
    )
    await #expect(throws: RunnerError.timedOut) {
        try await timingOut.run(.clearSimulator(udid: "SIM"))
    }

    let hold = HoldSpawner()
    let overlapping = ProcessCommandRunner(spawner: hold, sleeper: ImmediateSleeper(), clock: ManualClock(now))
    let first = Task { try await overlapping.run(.clearPhone(id: "phone-1")) }
    while hold.entered == 0 {
        await Task.yield()
    }
    await #expect(throws: RunnerError.overlap) {
        try await overlapping.run(.setPhone(id: "phone-1", coordinate: sanFrancisco))
    }
    hold.release()
    _ = try await first.value
}

@Test func aSecondProcessHandsOffWhenTheLockIsLive() {
    #expect(InstanceHandoff.shouldExit(existingPID: 10, currentPID: 11, isAlive: { $0 == 10 }))
    #expect(!InstanceHandoff.shouldExit(existingPID: 11, currentPID: 11, isAlive: { _ in true }))
    #expect(!InstanceHandoff.shouldExit(existingPID: 10, currentPID: 11, isAlive: { _ in false }))
    #expect(InstanceHandoff.pid(in: "42\n") == 42)
}

private let simulatorFixture = """
{
  "devices": {
    "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [
      {"udid": "BOOTED", "name": "iPhone 16", "state": "Booted", "isAvailable": true},
      {"udid": "SHUT", "name": "iPhone 16 Down", "state": "Shutdown", "isAvailable": true}
    ]
  }
}
"""

private let phoneFixture = """
{
  "result": {
    "devices": [
      {
        "identifier": "PHONE",
        "deviceProperties": {"name": "Pocket", "platform": "iOS"},
        "connectionProperties": {"tunnelState": "connected"}
      },
      {
        "identifier": "GONE",
        "deviceProperties": {"name": "Gone", "platform": "iOS"},
        "connectionProperties": {"tunnelState": "disconnected"}
      },
      {
        "identifier": "MAC",
        "deviceProperties": {"name": "Mac", "platform": "macOS"}
      }
    ]
  }
}
"""

private final class ScriptedCommander: LocationCommanding, @unchecked Sendable {
    enum Step {
        case success
        case failure(String)
    }

    private struct State {
        var results: [Step]
        var commands: [LocationCommand] = []
    }

    private let state: OSAllocatedUnfairLock<State>

    init(results: [Step]) {
        state = OSAllocatedUnfairLock(initialState: State(results: results))
    }

    var commands: [LocationCommand] {
        state.withLock { $0.commands }
    }

    func run(_ command: LocationCommand) async throws -> ProcessOutput {
        let step = state.withLock { (state: inout State) -> Step in
            state.commands.append(command)
            return state.results.isEmpty ? .success : state.results.removeFirst()
        }
        switch step {
        case .success:
            return ProcessOutput(status: 0, stdout: "", stderr: "")
        case .failure(let reason):
            throw RunnerError.failed(reason)
        }
    }
}

private final class ScriptedSpawner: ProcessSpawning, @unchecked Sendable {
    var result: Result<ProcessOutput, RunnerError>
    init(result: Result<ProcessOutput, RunnerError>) { self.result = result }
    func spawn(arguments: [String], timeout: TimeInterval) async throws -> ProcessOutput {
        #expect(timeout == 30)
        return try result.get()
    }
}

private final class HoldSpawner: ProcessSpawning, @unchecked Sendable {
    private struct State {
        var enteredCount = 0
        var releaseContinuation: CheckedContinuation<Void, Never>?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var entered: Int {
        state.withLock { $0.enteredCount }
    }

    func spawn(arguments: [String], timeout: TimeInterval) async throws -> ProcessOutput {
        state.withLock { $0.enteredCount += 1 }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            state.withLock { $0.releaseContinuation = continuation }
        }
        return ProcessOutput(status: 0, stdout: "", stderr: "")
    }

    func release() {
        let continuation = state.withLock { state -> CheckedContinuation<Void, Never>? in
            let continuation = state.releaseContinuation
            state.releaseContinuation = nil
            return continuation
        }
        continuation?.resume()
    }
}
