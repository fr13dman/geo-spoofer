# Location command adapter

## What was built

The only values that name `simctl` or `devicectl` are `LocationCommand` and the process runner. Tests assert the argument list and do not launch Xcode.

Calling the developer tools as separate processes was chosen over a private MobileDevice binding. The tools are the same ones Xcode uses, and the runner can kill them when the 30 second timeout expires.

## Arguments

A Simulator set is `xcrun simctl location <udid> set <lat>,<lon>`. A Simulator clear drops the coordinate. An iPhone set is `xcrun devicectl device simulate location coordinate` with `--device`, `--latitude`, and `--longitude`. An iPhone clear is `devicectl device simulate location clear`.

```swift
case .setPhone(let id, let coordinate):
    [
        "xcrun", "devicectl", "device", "simulate", "location", "coordinate",
        "--device", id,
        "--latitude", coordinate.latitude.commandToken,
        "--longitude", coordinate.longitude.commandToken
    ]
```

`CommandGuard` rejects any argument list that contains both `settings` and `reset`. That is the command that erases a device. `LocationCommand` has no value that builds it.

## Runner

`ProcessCommandRunner` is the only type that starts a process. It allows one in-flight command per device. If the previous command for that device finished less than 5 seconds ago, it waits out the gap, which extends the 2 second and 4 second retry backoff. A 30 second timeout terminates the process and counts as a failed attempt. `SystemProcessSpawner` uses `/usr/bin/xcrun`.

Device lists are parsed from saved JSON fixtures. Shut-down Simulators are dropped. A phone whose connection is disconnected is dropped. A Mac listed by the same tool is dropped.

## Tests

`locationCommandsMatchTheXcodeTools`, `deviceListsKeepBootedSimulatorsAndAvailablePhones`, and `runnerEnforcesTheGapTheTimeoutAndASingleInFlightCommand` cover the argv, the fixtures, the 5 second gap, the timeout, and the overlap refusal.
