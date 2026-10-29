import GeoSpooferCore
import SwiftUI

struct DurationDialView: View {
    var minutes: Int
    var onChange: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = side * 0.36
            ZStack {
                dial(center: center, radius: radius)
                Text(DurationDial.label(forMinutes: minutes))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .frame(width: radius * 1.5)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let dx = Double(value.location.x - center.x)
                        let dy = Double(value.location.y - center.y)
                        onChange(DurationDial.minutes(atClockDegrees: DurationDial.clockDegrees(dx: dx, dy: dy)))
                    }
            )
        }
        .frame(height: 230)
        .accessibilityElement()
        .accessibilityIdentifier("durationDial")
        .accessibilityLabel("Duration")
        .accessibilityValue(DurationDial.label(forMinutes: minutes))
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? DurationDial.stepMinutes : -DurationDial.stepMinutes
            onChange(min(DurationDial.maximumMinutes, max(0, minutes + step)))
        }
    }

    private func dial(center: CGPoint, radius: CGFloat) -> some View {
        Canvas { context, _ in
            var track = Path()
            appendArc(to: &track, from: DurationDial.startDegrees, sweep: DurationDial.sweepDegrees, center: center, radius: radius)
            context.stroke(track, with: .color(.secondary.opacity(0.25)), style: StrokeStyle(lineWidth: 14, lineCap: .round))

            let valueDegrees = DurationDial.clockDegrees(forMinutes: minutes)
            let swept = minutes == 0 ? 0 : DurationDial.sweepDegrees * Double(minutes) / Double(DurationDial.maximumMinutes)
            if swept > 0 {
                var value = Path()
                appendArc(to: &value, from: DurationDial.startDegrees, sweep: swept, center: center, radius: radius)
                context.stroke(value, with: .color(.accentColor), style: StrokeStyle(lineWidth: 14, lineCap: .round))
            }

            let knob = point(clockDegrees: valueDegrees, center: center, radius: radius)
            let knobRect = CGRect(x: knob.x - 11, y: knob.y - 11, width: 22, height: 22)
            context.fill(Path(ellipseIn: knobRect), with: .color(.white))
            context.stroke(Path(ellipseIn: knobRect), with: .color(.accentColor), lineWidth: 3)

            for mark in [0, 6, 12, 18, 24] {
                let degrees = DurationDial.clockDegrees(forMinutes: mark * 60)
                let tick = point(clockDegrees: degrees, center: center, radius: radius + 22)
                let text = context.resolve(
                    Text(mark == 0 ? "0" : "\(mark)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                )
                context.draw(text, at: tick, anchor: .center)
            }
        }
    }

    private func appendArc(to path: inout Path, from start: Double, sweep: Double, center: CGPoint, radius: CGFloat) {
        let steps = max(1, Int(sweep / 4))
        for step in 0...steps {
            let degrees = start + sweep * Double(step) / Double(steps)
            let location = point(clockDegrees: degrees, center: center, radius: radius)
            if step == 0 {
                path.move(to: location)
            } else {
                path.addLine(to: location)
            }
        }
    }

    private func point(clockDegrees: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        let radians = clockDegrees * .pi / 180
        return CGPoint(
            x: center.x + CGFloat(sin(radians)) * radius,
            y: center.y - CGFloat(cos(radians)) * radius
        )
    }
}
