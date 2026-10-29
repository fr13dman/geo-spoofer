# Glossary

## Location override

A temporary simulated location for an entire device.

_Avoid_: spoof, fake GPS

## Live location

The device's real location after a location override has been cleared.

_Avoid_: original settings, saved coordinate

## Clear

Ending a location override so the device uses its live location.

_Avoid_: settings reset, erase

## Candidate fix

A map coordinate chosen by a place search or a pin that has not been sent to a device.

_Avoid_: ZIP code as the value that is applied

## Device

An iPhone this Mac can see, or a booted Simulator, that can hold a location override.

_Avoid_: phone as a stand-in for a shut-down Simulator

## Lease

The one recorded location override for a device, including the coordinate, when it was applied, when it expires, and whether it is still active or waiting to be cleared.

_Avoid_: preset, route

## Pending clear

A lease that should be cleared and has not yet been cleared on the device.

## Apply

Sending the candidate fix to the selected device and starting or replacing that device's lease. The user chooses a duration of at most 24 hours, and the lease stores the absolute expiration that duration produces.

## Command budget

The automatic attempts allowed for one operation: the first send, then three retries. When the third retry fails, the device is stopped.

_Avoid_: unlimited retry, polling loop

## Stopped

A device that will not receive another automatic command during this run of the app. A later Apply, Reset, or a new launch of the app can start a fresh command budget.

## Audit entry

A timestamped record of an apply, clear, retry, timeout, failure, or stop, including the coordinate and expiration when the operation has them.

_Avoid_: lease, as the record of the current override

## Emergency stop

The user action that cancels retries immediately and then attempts one Clear for each reachable device.
