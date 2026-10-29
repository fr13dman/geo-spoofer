# Duration dial

## What was built

The duration control is a circular dial in the side panel. Dragging around the arc sets a lease from 0 through 24 hours in 15-minute steps. The center reads the chosen length in SF Rounded. Zero stays labeled “Choose a duration,” so Apply remains disabled until the dial leaves the start.

The arc begins at the lower left and runs clockwise over the top to the lower right. The open gap along the bottom keeps 0 and 24 hours from sharing one point. A drag that lands in that gap snaps to the nearer end. The same mapping turns a pointer offset into clock degrees, with 0 at the top.

```swift
public static func minutes(atClockDegrees degrees: Double) -> Int {
    let swept = sweptDegrees(from: degrees)
    let raw = swept / sweepDegrees * Double(maximumMinutes)
    let stepped = (raw / Double(stepMinutes)).rounded() * Double(stepMinutes)
    return min(maximumMinutes, max(0, Int(stepped)))
}
```

`DurationDialView` draws that arc and calls `AppModel.setMinutes`, which still stores the duration as an absolute expiration of at most 24 hours. The stepper and the 15-minute, 1-hour, and 4-hour buttons are gone. VoiceOver can still nudge the value by 15 minutes.

The side panel uses 28 points of padding and 28 points between Place, Device, Duration, and the action buttons. Section labels and the title use the rounded system font. Apply, Reset, and Stop use large bordered buttons with 12 points between them.

## Technologies

The angle math lives in `DurationDial` inside GeoSpooferCore so the tests do not need SwiftUI. The drawing is a SwiftUI `Canvas` plus a drag gesture. A stock `Slider` was considered and set aside because a dial matches the requested control and keeps 24 hours visible as one turn.

## Tests

`durationDialSnapsAroundTheClock` checks the lower-left start, the top (12 hours), the lower-right end (24 hours), the bottom gap, the up and right pointer directions, and the center labels.
