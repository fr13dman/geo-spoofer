import Foundation

public struct ProcessOutput: Equatable, Sendable {
    public var status: Int32
    public var stdout: String
    public var stderr: String

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

public enum RunnerError: Error, Equatable, Sendable {
    case overlap
    case timedOut
    case settingsResetForbidden
    case failed(String)
}

public protocol ProcessSpawning: Sendable {
    func spawn(arguments: [String], timeout: TimeInterval) async throws -> ProcessOutput
}

public protocol Clocking: Sendable {
    func now() -> Date
}

public struct SystemClock: Clocking {
    public init() {}
    public func now() -> Date { Date() }
}

public final class ManualClock: Clocking, @unchecked Sendable {
    public var date: Date
    public init(_ date: Date) { self.date = date }
    public func now() -> Date { date }
    public func advance(_ interval: TimeInterval) { date.addTimeInterval(interval) }
}

public protocol Sleeping: Sendable {
    func sleep(seconds: TimeInterval) async
}

public struct ImmediateSleeper: Sleeping {
    public init() {}
    public func sleep(seconds: TimeInterval) async {}
}

public final class RecordingSleeper: Sleeping, @unchecked Sendable {
    public private(set) var delays: [TimeInterval] = []
    public init() {}
    public func sleep(seconds: TimeInterval) async {
        delays.append(seconds)
    }
}

public protocol LocationCommanding: Sendable {
    func run(_ command: LocationCommand) async throws -> ProcessOutput
}

public actor ProcessCommandRunner: LocationCommanding {
    private let spawner: any ProcessSpawning
    private let sleeper: any Sleeping
    private let clock: any Clocking
    private var inFlight: Set<String> = []
    private var lastFinished: [String: Date] = [:]

    public init(spawner: any ProcessSpawning, sleeper: any Sleeping = ImmediateSleeper(), clock: any Clocking = SystemClock()) {
        self.spawner = spawner
        self.sleeper = sleeper
        self.clock = clock
    }

    public func run(_ command: LocationCommand) async throws -> ProcessOutput {
        try CommandGuard.check(command.arguments)
        let deviceID = command.deviceID
        if inFlight.contains(deviceID) {
            throw RunnerError.overlap
        }
        inFlight.insert(deviceID)
        defer { inFlight.remove(deviceID) }
        if let last = lastFinished[deviceID] {
            let elapsed = clock.now().timeIntervalSince(last)
            if elapsed < RetrySchedule.minimumGap {
                await sleeper.sleep(seconds: RetrySchedule.minimumGap - elapsed)
            }
        }
        do {
            let output = try await spawner.spawn(arguments: command.arguments, timeout: RetrySchedule.timeout)
            lastFinished[deviceID] = clock.now()
            if output.status != 0 {
                let reason = output.stderr.isEmpty ? "Command exited with status \(output.status)." : output.stderr
                throw RunnerError.failed(reason)
            }
            return output
        } catch let error as RunnerError {
            lastFinished[deviceID] = clock.now()
            throw error
        } catch {
            lastFinished[deviceID] = clock.now()
            throw RunnerError.failed(error.localizedDescription)
        }
    }
}

public struct SystemProcessSpawner: ProcessSpawning {
    public init() {}

    public func spawn(arguments: [String], timeout: TimeInterval) async throws -> ProcessOutput {
        let executable = "/usr/bin/xcrun"
        let processArguments = arguments.first == "xcrun" ? Array(arguments.dropFirst()) : arguments
        return try await runProcess(executable: executable, arguments: processArguments, timeout: timeout)
    }

    private func runProcess(executable: String, arguments: [String], timeout: TimeInterval) async throws -> ProcessOutput {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProcessOutput, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            let gate = ResumeOnce()
            process.terminationHandler = { process in
                let output = ProcessOutput(
                    status: process.terminationStatus,
                    stdout: Self.read(stdout),
                    stderr: Self.read(stderr)
                )
                gate.resume {
                    if process.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: RunnerError.timedOut)
                    } else {
                        continuation.resume(returning: output)
                    }
                }
            }
            do {
                try process.run()
            } catch {
                gate.resume { continuation.resume(throwing: RunnerError.failed(error.localizedDescription)) }
                return
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    process.terminate()
                }
            }
        }
    }

    private static func read(_ pipe: Pipe) -> String {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func resume(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        body()
    }
}
