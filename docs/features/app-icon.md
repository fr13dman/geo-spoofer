# App icon

## What was built

The Dock and Finder icon is the map-pin mark. A sharp blue pin sits on the illustrated map, with two fading copies trailing up and to the left. That trail is the motion: the pin has just moved, and the solid pin is where it stopped. The map itself stays still so the icon still reads as a place at small size.

The artwork is the set of PNG files in `App/GeoSpoofer/Assets.xcassets/AppIcon.appiconset`, from 16 pixels through 1024. `ASSETCATALOG_COMPILER_APPICON_NAME` is `AppIcon` on the Mac app.

## Technologies

The picture was drawn from the chosen map-pin proposal, then stored as a normal asset catalog image. A vector pin drawn in SwiftUI was considered and set aside, because the paper-map texture and the soft trail are a picture, not a control.
