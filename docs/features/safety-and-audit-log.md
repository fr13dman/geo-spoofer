# Safety controls and the audit log

## What this protects

A location command does not erase the phone or write its firmware. The failure this feature prevents is a runaway series of commands: a retry loop, a reconnect storm, or a timer that keeps sending after failure. That loop can hold the developer connection open, drain the battery, leave a simulation in place, and spawn processes without stopping.

The app never reboots a device, never erases content and settings, and never changes Developer Mode.

## Command budget

One operation is the first send plus three retries. The retry waits are 2 seconds, then 4, then 8. Commands to the same device also stay at least 5 seconds apart, so the runner extends a 2 second or 4 second wait when that is what the gap requires. The 8 second wait is already longer than the gap.

Each command is killed if it is still running after 30 seconds. That timeout counts as a failed attempt. One command is in flight per device. A second copy of the app does not start its own reconciler.

After the third retry fails, the device is stopped for the rest of this run. Launch, wake, and reconnect do not start another series while it is stopped. The expiration timer does not send again either. Pressing Apply or Reset, or quitting and opening the app, starts a fresh budget.

Emergency stop cancels the series immediately, then attempts one Clear for each reachable device. Those Clears are logged. The app does not begin another automatic series until the user Applies or Resets, or opens the app again.

## Audit log

The log is a separate append-only file from the lease. The Location Log menu shows it newest first. Nothing is uploaded.

Every attempt is an entry. A retry entry includes the wait before it ran. Each entry has:

- timestamp
- device
- command (apply, clear, or stop)
- attempt number, when the entry is an attempt
- coordinate and expiration, when the operation has them
- time the override was applied, when that time exists
- result
- failure reason, when it failed

When the third retry fails, the next entry says the device is stopped and that reconnect, wake, and the expiration timer will not send again until the user acts or the app is opened again.

## Technologies

The budget is a pure value type plus a process runner. Tests use a fake clock and a fake process so they do not sleep for 30 seconds and do not call Xcode. The log is JSON Lines rather than a database because the entries are an ordered history a person can open from the menu.
