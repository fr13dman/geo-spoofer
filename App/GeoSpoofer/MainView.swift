import GeoSpooferCore
import MapKit
import SwiftUI

struct MainView: View {
    @Bindable var model: AppModel
    @State private var query = ""
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 80, longitudeDelta: 80)
        )
    )

    var body: some View {
        HSplitView {
            map
                .frame(minWidth: 480, minHeight: 420)
            controls
                .frame(minWidth: 340, idealWidth: 380)
                .padding(28)
                .background(.background)
        }
        .task { await model.start() }
        .onChange(of: model.cameraRequest) { _, request in
            guard let request else { return }
            moveCamera(to: CLLocationCoordinate2D(
                latitude: request.coordinate.latitude,
                longitude: request.coordinate.longitude
            ))
        }
        .onReceive(NotificationCenter.default.publisher(for: .geoSpooferStop)) { _ in
            Task { await model.stop() }
        }
    }

    private var map: some View {
        MapReader { proxy in
            Map(position: $camera) {
                if let candidate = model.panel.candidate {
                    Marker(
                        candidate.label ?? "Override",
                        coordinate: CLLocationCoordinate2D(
                            latitude: candidate.coordinate.latitude,
                            longitude: candidate.coordinate.longitude
                        )
                    )
                }
            }
            .onTapGesture { location in
                guard let coordinate = proxy.convert(location, from: .local) else { return }
                model.panel.candidate = CandidateFix(
                    coordinate: Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
                )
                model.matches = []
                moveCamera(to: coordinate)
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("GeoSpoofer")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
            VStack(alignment: .leading, spacing: 12) {
                Text("Place")
                    .font(sectionFont)
                HStack(spacing: 12) {
                    TextField("ZIP code or place", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .rounded))
                    Button("Find") { Task { await model.search(query) } }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
                if !model.matches.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.matches) { match in
                            Button(match.label) { select(match) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                if let candidate = model.panel.candidate {
                    Text(candidate.label ?? "\(candidate.coordinate.latitude), \(candidate.coordinate.longitude)")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Device")
                    .font(sectionFont)
                Picker("Device", selection: $model.panel.selectedDeviceID) {
                    Text("Choose a device").tag(Optional<String>.none)
                    ForEach(model.panel.devices) { device in
                        Text("\(device.name) · \(device.kind == .iPhone ? "iPhone" : "Simulator")").tag(Optional(device.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .font(.system(.body, design: .rounded))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Duration")
                    .font(sectionFont)
                Text("Drag the dial. A full turn is 24 hours.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
                DurationDialView(minutes: model.minutes) { model.setMinutes($0) }
            }
            HStack(spacing: 12) {
                Button("Apply") { Task { await model.apply() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!model.toolsAvailable || !model.panel.canApply)
                    .accessibilityIdentifier("applyButton")
                Button("Reset") { Task { await model.reset() } }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(model.panel.selectedDevice == nil)
                Button("Stop") { Task { await model.stop() } }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
            Text(model.panel.message)
                .font(.system(.callout, design: .rounded))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var sectionFont: Font {
        .system(.subheadline, design: .rounded).weight(.semibold)
    }

    private func select(_ match: PlaceMatch) {
        model.choose(match)
        moveCamera(to: CLLocationCoordinate2D(latitude: match.coordinate.latitude, longitude: match.coordinate.longitude))
    }

    private func moveCamera(to coordinate: CLLocationCoordinate2D) {
        camera = .region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)))
    }
}

struct LogView: View {
    var model: AppModel

    var body: some View {
        List(model.logEntries.reversed()) { entry in
            Text(entry.summary)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
        .navigationTitle("Location Log")
        .task { await model.start() }
    }
}
