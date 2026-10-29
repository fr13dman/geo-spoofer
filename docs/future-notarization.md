# Future work: notarized direct download

The current package is a local, unsigned DMG for this Mac. Gatekeeper will not treat it as a normal download for other people.

Later work, not part of this version:

- Join the Apple Developer Program and sign the app with a Developer ID.
- Notarize the app and staple the ticket to the DMG.
- Keep the app unsandboxed so it can still launch Xcode's `simctl` and `devicectl`.
- Keep the requirement that the receiving Mac has Xcode installed. The DMG does not include Xcode.

Until that work lands, build and open the DMG on this Mac.
