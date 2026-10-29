import CoreLocation
import SwiftUI

@main
struct ProbeApp: App {
    var body: some Scene {
        WindowGroup {
            ProbeView()
        }
    }
}

struct ProbeView: View {
    @StateObject private var locator = Locator()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GeoSpoofer probe")
            Text(locator.text)
                .font(.system(.title3, design: .monospaced))
        }
        .padding()
        .onAppear { locator.start() }
    }
}

final class Locator: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var text = "waiting"
    private let manager = CLLocationManager()

    func start() {
        manager.delegate = self
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let line = "\(location.coordinate.latitude),\(location.coordinate.longitude)"
        text = line
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("reported-location.txt")
        try? line.write(to: url, atomically: true, encoding: .utf8)
    }
}
