import AppKit
import CoreLocation
import Foundation
import GeoSpooferCore

struct MapCameraRequest: Equatable {
    var coordinate: Coordinate
    var generation: Int
}

@MainActor
@Observable
final class AppModel {
    var panel = OverridePanel()
    var matches: [PlaceMatch] = []
    var logEntries: [AuditEntry] = []
    var toolsAvailable = true
    var minutes = 0
    var cameraRequest: MapCameraRequest?

    private let session: OverrideSession?
    private let spawner: any ProcessSpawning
    private var started = false

    init(session: OverrideSession?, spawner: any ProcessSpawning, message: String = "") {
        self.session = session
        self.spawner = spawner
        panel.message = message
    }

    static func live() throws -> AppModel {
        let spawner = SystemProcessSpawner()
        let runner = ProcessCommandRunner(spawner: spawner)
        let session = try OverrideSession(directory: AppPaths.supportDirectory(), commander: runner)
        return AppModel(session: session, spawner: spawner)
    }

    static func failed(_ message: String) -> AppModel {
        AppModel(session: nil, spawner: SystemProcessSpawner(), message: message)
    }

    func start() async {
        guard !started else { return }
        started = true
        await refresh(trigger: .launch)
        watchExpirations()
        watchReconnects()
        watchWake()
    }

    func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let geocoder = CLGeocoder()
        let found: [PlaceMatch]
        do {
            let marks = try await geocoder.geocodeAddressString(trimmed)
            found = marks.compactMap { mark in
                guard let location = mark.location else { return nil }
                let coordinate = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                let label = [mark.name, mark.locality, mark.postalCode].compactMap { $0 }.joined(separator: ", ")
                return PlaceMatch(id: "\(coordinate.latitude),\(coordinate.longitude),\(label)", label: label.isEmpty ? trimmed : label, coordinate: coordinate)
            }
        } catch {
            found = []
        }
        let selection = PlaceSearch.resolve(matches: found, previous: panel.candidate)
        panel.candidate = selection.candidate
        panel.message = selection.message ?? ""
        matches = selection.needsChoice ? found : []
        if let coordinate = PlaceSearch.mapCoordinate(selection: selection, matches: found) {
            show(coordinate)
        }
    }

    func choose(_ match: PlaceMatch) {
        panel.candidate = CandidateFix(coordinate: match.coordinate, label: match.label)
        matches = []
        panel.message = ""
        show(match.coordinate)
    }

    private func show(_ coordinate: Coordinate) {
        let next = (cameraRequest?.generation ?? 0) + 1
        cameraRequest = MapCameraRequest(coordinate: coordinate, generation: next)
    }

    func setMinutes(_ value: Int) {
        let bounded = min(max(value, 0), 24 * 60)
        minutes = bounded
        panel.duration = bounded == 0 ? nil : TimeInterval(bounded * 60)
    }

    func apply() async {
        guard toolsAvailable, let session else {
            panel.message = UserMessage.missingTools()
            return
        }
        let notice = await session.apply(
            candidate: panel.candidate,
            device: panel.selectedDevice,
            duration: panel.duration,
            knownDeviceIDs: Set(panel.devices.map(\.id))
        )
        panel.message = notice.message
        await reloadLog()
    }

    func reset() async {
        guard let session, let device = panel.selectedDevice else {
            panel.message = UserMessage.applyFailed(String(describing: OverrideValidation.missingDevice))
            return
        }
        let notice = await session.reset(device: device)
        panel.message = notice.message
        await reloadLog()
    }

    func stop() async {
        guard let session else { return }
        let notice = await session.stop(devices: panel.devices)
        panel.message = notice.message
        await reloadLog()
    }

    private func refresh(trigger: AutomaticTrigger?) async {
        let inventory = await DeviceInventory.load(spawner: spawner)
        panel.devices = inventory.devices
        toolsAvailable = inventory.toolsAvailable
        if !inventory.toolsAvailable {
            panel.message = UserMessage.missingTools()
        }
        if let session, let trigger, inventory.toolsAvailable {
            await session.performAutomatic(trigger: trigger, devices: inventory.devices)
        }
        await reloadLog()
    }

    private func reloadLog() async {
        guard let session else { return }
        logEntries = (try? await session.auditEntries()) ?? []
    }

    private func watchExpirations() {
        Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, let session = self.session, self.toolsAvailable else { continue }
                await session.performAutomatic(trigger: .expiration, devices: self.panel.devices)
            }
        }
    }

    private func watchReconnects() {
        Task { @MainActor [weak self] in
            var seen = Set(self?.panel.devices.map(\.id) ?? [])
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self else { return }
                let before = seen
                await self.refresh(trigger: nil)
                let current = Set(self.panel.devices.map(\.id))
                seen = current
                if !before.isEmpty, !current.subtracting(before).isEmpty, let session = self.session, self.toolsAvailable {
                    await session.performAutomatic(trigger: .reconnect, devices: self.panel.devices)
                    await self.reloadLog()
                }
            }
        }
    }

    private func watchWake() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh(trigger: .wake)
            }
        }
    }
}

struct DeviceInventory: Sendable {
    var devices: [Device]
    var toolsAvailable: Bool

    static func load(spawner: any ProcessSpawning) async -> DeviceInventory {
        async let simctl = toolExists(spawner, name: "simctl")
        async let devicectl = toolExists(spawner, name: "devicectl")
        let hasSimctl = await simctl
        let hasDevicectl = await devicectl
        let toolsAvailable = hasSimctl && hasDevicectl
        guard toolsAvailable else { return DeviceInventory(devices: [], toolsAvailable: false) }
        let simulators = await list(spawner, arguments: ["xcrun", "simctl", "list", "devices", "available", "-j"]) { data in
            try DeviceListParser.simulators(from: data)
        }
        let phones = await list(spawner, arguments: ["xcrun", "devicectl", "list", "devices", "--json-output", "-"]) { data in
            try DeviceListParser.phones(from: data)
        }
        return DeviceInventory(devices: simulators + phones, toolsAvailable: true)
    }

    private static func toolExists(_ spawner: any ProcessSpawning, name: String) async -> Bool {
        guard let output = try? await spawner.spawn(arguments: ["xcrun", "--find", name], timeout: 20) else { return false }
        return output.status == 0
    }

    private static func list(
        _ spawner: any ProcessSpawning,
        arguments: [String],
        parse: (Data) throws -> [Device]
    ) async -> [Device] {
        guard let output = try? await spawner.spawn(arguments: arguments, timeout: 30), output.status == 0 else { return [] }
        return (try? parse(Data(output.stdout.utf8))) ?? []
    }
}
