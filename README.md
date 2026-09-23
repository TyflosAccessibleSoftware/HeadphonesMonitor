# Headphone monitor

A macOS menu bar app built with SwiftUI and Swift 6.2. It reads headset information from [HeadsetControl](https://github.com/Sapd/HeadsetControl).

## Build and run

1. Install HeadsetControl with Homebrew and confirm that `headsetcontrol -b -o json` runs.
2. Open `HeadphoneMonitor.xcodeproj` in Xcode 27 or later.
3. Select the **Headphone monitor** scheme and run it on **My Mac**.

The app appears in the menu bar and has no Dock icon. It checks for HeadsetControl at launch, queries the headset after three seconds, and refreshes every ten minutes by default. The Settings menu lets you change the interval and turn sound on or off. You can also refresh immediately, open all available device information, or quit. The interval and sound preferences persist between launches; sound is enabled by default.

When a headset is connected but its battery level is unavailable, the app retries every 60 seconds. After a refresh returns a battery percentage, it resumes the interval selected in Settings.

The menu bar icon changes with the battery level: cyan below 20%, yellow from 20% through 49%, orange from 50% through 80%, and red above 80%. The original blue icon represents a connected headset whose battery level is unknown.

The app plays `detection.wav` when a refresh finds a headset after the previous state had none. It plays `info.wav` only when a battery percentage becomes available or changes. It plays `low.wav` on every successful refresh with a detected battery level of 20% or less. All sounds are in `Resources/Sounds/` and follow the Sound setting.

The original SVG artwork is in `Resources/svg/`. The asset catalog contains PNG renditions for the menu bar and application icon.

## Author and license

Created by Jonathan Chacón of Tyflos Accessible Software. This project uses the MID license.
