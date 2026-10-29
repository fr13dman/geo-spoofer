# Lease, retry budget, and audit log

## What was built

`GeoSpooferCore` is a Swift package with no UI and no Xcode process. It owns the candidate fix, the lease file, the decision to Apply or Clear, the three-retry budget, and the Location Log.

SwiftPM was chosen so `swift test` covers this behavior without launching the menu-bar app. A database was not used. One JSON file holds the leases, and a JSON Lines file holds the history, because a person can open that history from the menu.

## Validation and Apply

A candidate fix is a coordinate, not the ZIP text. `ApplyDraft.prepare` rejects a missing pin, a coordinate outside the legal range, a duration that is not positive, a duration past 24 hours, and a device that is not on the current list. The duration is turned into an absolute expiration before anything is stored.

```swift
public static func expirationDate(duration: TimeInterval, now: Date) throws(OverrideValidation) -> Date {
    try validate(duration: duration)
    return now.addingTimeInterval(duration)
}
```

A failed Apply does not replace the lease. `OverrideSession.apply` writes the new lease only after the command series succeeds. Tests seed a Tokyo lease, fail every Paris command, and assert the stored lease is still Tokyo.

## Reconcile

`Reconciler` returns a command value and does not talk to a device.

- A disconnected device produces no command.
- A stopped device produces no command.
- A lease that is pending clear, or whose expiration is in the past, produces Clear.
- Launch, wake, and reconnect Apply the saved coordinate again and keep the original expiration.
- The expiration trigger only Clears. It does not Apply.

## Command budget

`DeviceCommandGate` allows the first send and three retries. `RetrySchedule.retryWaits` is 2, 4, then 8 seconds. The fourth failure marks the device stopped. An automatic trigger cannot begin while it is stopped. Apply and Reset pass `userInitiated: true`, which clears that stop and starts a new series. A new process starts with an empty gate, so opening the app again is also a new series.

## Audit log

`AuditLog.append` writes one JSON object per line. Each attempt includes the attempt number, coordinate, expiration, wait, and failure reason. The entry after the third retry uses `AuditLog.stoppedEntry`, which states that reconnect, wake, and the expiration timer will not send again.

## Tests

`Packages/GeoSpooferCore/Tests/GeoSpooferCoreTests/CoreTests.swift` covers the bounds, the disabled Apply form, search matches, reload after relaunch, expired Clear, reconnect re-Apply, a failed Apply keeping the old lease, four logged attempts, and the stop that blocks a later reconnect.
