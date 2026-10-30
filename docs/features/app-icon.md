# App icon

## What was built

The Dock and Finder icon is the map-pin mark. A sharp blue pin sits on the illustrated map, with two fading copies trailing up and to the left. That trail is the motion: the pin has just moved, and the solid pin is where it stopped. The map itself stays still so the icon still reads as a place at small size.

The artwork is `App/GeoSpoofer/AppIcon.icns`, with every Dock size from 16 pixels through 1024. Each image is clipped to the same rounded macOS icon shape as other apps, with a clear margin around it, so the Dock does not show a square. `CFBundleIconFile` is `AppIcon`, and launch assigns that file to the running app's icon.

## Technologies

The picture was drawn from the chosen map-pin proposal and packed with `iconutil` into one `.icns`. A vector pin drawn in SwiftUI was considered and set aside, because the paper-map texture and the soft trail are a picture, not a control.
