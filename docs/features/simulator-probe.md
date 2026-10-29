# Simulator probe

## What was built

`GeoSpooferProbe` is an iOS app whose only job is to show the coordinate Core Location reports and write it to `Documents/reported-location.txt`. It is not installed on a physical phone as a companion. The Mac app does not need it to Apply or Clear.

The gated test `simulatorProbeReadsTheAppliedCoordinate` runs only when `RUN_SIMULATOR_TESTS=1`. It builds the probe, installs it on an iPhone Simulator, grants location, launches it, Applies `37.7749,-122.4194` through `ProcessCommandRunner`, reads the file the probe wrote, and Clears. `swift test` without that variable returns immediately.

A physical iPhone is a manual check: connect and trust the phone, Apply a pin, confirm the phone reports that place, then press Reset and confirm it reports its live location again.

## Technologies

Core Location on the Simulator is the read-back, because `devicectl` and `simctl` can set and clear a location and cannot report the active simulation. The test drives the same runner the app uses, so the argument list is not reimplemented in the shell.
