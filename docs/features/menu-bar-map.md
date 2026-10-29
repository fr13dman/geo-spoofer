# Menu-bar map

## What was built

The Mac app is a SwiftUI window plus a status-item menu. MapKit shows the map. A tap drops the candidate pin and recenters. A ZIP or place search uses `CLGeocoder`, then `PlaceSearch.resolve`. One match moves the map to that coordinate. Several matches wait for a choice, and the map moves when one is chosen. A failed search leaves the map and the pin where they were.

```swift
guard matches.count == 1, selection.needsChoice == false else { return nil }
return selection.candidate?.coordinate
```

Apply stays disabled until there is a candidate, a connected device, and a duration of at most 24 hours. That rule lives on `OverridePanel.canApply` and is unit-tested without launching the window.

Closing the last window does not quit. `GeoSpooferDelegate.applicationShouldTerminateAfterLastWindowClosed` returns false, and the status item keeps Open, Location Log, Stop, and Quit. A second launch finds the pid lock, activates the running app, and exits so only one reconciler runs. The app is not sandboxed: `ENABLE_APP_SANDBOX` is off and `App/Supporting/GeoSpoofer.entitlements` does not request the sandbox, so it can launch `xcrun`.

The Location Log window lists audit entries newest first. Launch, wake, and a device that newly appears in the list each run one reconcile. A one-second timer asks the session for an expiration Clear; the session sends nothing unless a lease is due and the device is not stopped.

## Technologies

SwiftUI and MapKit keep the map in the same process as the menu. `CLGeocoder` was used instead of a private geocoding service because a ZIP only needs to become a coordinate. The status item is AppKit rather than `MenuBarExtra`, so the main window stays a normal window the user can open beside the menu.

## Tests

`searchDoesNotMoveThePinUntilOneMatchIsChosen` checks that one match returns a map coordinate and that an empty or ambiguous search does not. `applyStaysDisabledUntilTheFormIsComplete` in the core package checks the disabled rule. `ApplyButtonUITests` launches the app and checks the Apply button when the test runner can see the window.
