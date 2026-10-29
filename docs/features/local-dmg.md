# Local DMG

## What was built

`scripts/make-dmg.sh` builds the Release app and packs it with `hdiutil` into `dist/GeoSpoofer.dmg`. The script does not sign with a Developer ID and does not notarize. That work is recorded in `docs/future-notarization.md`.

The receiving Mac needs Xcode. The app checks for `simctl` and `devicectl` on launch and, when either is missing, tells the user to install Xcode and select it with `xcode-select`. The DMG does not contain Xcode or a Simulator runtime.

## How to build

```bash
chmod +x scripts/make-dmg.sh
./scripts/make-dmg.sh
```

Open the DMG on this Mac. Gatekeeper may ask you to approve an app that is not notarized. Right-click the app and choose Open for a local build.
