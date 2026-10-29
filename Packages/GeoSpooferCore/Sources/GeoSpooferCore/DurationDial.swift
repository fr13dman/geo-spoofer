import Foundation

/// Maps a finger on a circular dial to a lease duration.
/// The scale runs clockwise from the lower left (0) over the top to the lower right (24 hours), in 15-minute steps.
public enum DurationDial {
    public static let maximumMinutes = 24 * 60
    public static let stepMinutes = 15
    /// Clock degrees: 0 is up, and values increase clockwise.
    public static let startDegrees = 220.0
    public static let sweepDegrees = 280.0

    public static func minutes(atClockDegrees degrees: Double) -> Int {
        let swept = sweptDegrees(from: degrees)
        let raw = swept / sweepDegrees * Double(maximumMinutes)
        let stepped = (raw / Double(stepMinutes)).rounded() * Double(stepMinutes)
        return min(maximumMinutes, max(0, Int(stepped)))
    }

    public static func clockDegrees(forMinutes minutes: Int) -> Double {
        let clamped = min(maximumMinutes, max(0, minutes))
        let swept = Double(clamped) / Double(maximumMinutes) * sweepDegrees
        return normalize(startDegrees + swept)
    }

    /// `dx` and `dy` are measured from the dial center. Positive `dy` points down the screen.
    public static func clockDegrees(dx: Double, dy: Double) -> Double {
        let radians = atan2(dx, -dy)
        return normalize(radians * 180 / .pi)
    }

    public static func label(forMinutes minutes: Int) -> String {
        if minutes <= 0 { return "Choose a duration" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 {
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }
        if hours == 0 { return "\(remainder) minutes" }
        return "\(hours)h \(remainder)m"
    }

    private static func sweptDegrees(from degrees: Double) -> Double {
        var swept = normalize(degrees) - startDegrees
        if swept < 0 { swept += 360 }
        if swept > sweepDegrees {
            let intoGap = swept - sweepDegrees
            let gap = 360 - sweepDegrees
            return intoGap < gap / 2 ? sweepDegrees : 0
        }
        return swept
    }

    private static func normalize(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value < 0 { value += 360 }
        return value
    }
}
