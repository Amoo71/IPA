# Islander — Dynamic Island controller

A SwiftUI app + Widget Extension that drives the iPhone's **Dynamic Island**
via a **Live Activity** (ActivityKit). You can place content on the **left**,
**right**, or **both** sides and show:

- a **photo or GIF** (GIFs animate frame-by-frame)
- a **Spotify-style equalizer**, a **wave**, a **call-style double wave**, or a **pulse**
- an animation **driven by the live microphone** (reacts to sound)

The in-app preview animates smoothly via `TimelineView`; the real island
animates by pushing Live Activity content updates several times per second
(self-running animations are ignored by the system, so data updates are the
only way to move things in the island).

## Reality check / limits

- The Dynamic Island appears only on **iPhone 14 Pro and newer** (iOS 16.2+).
- A third-party app **cannot** render a true real-time audio waveform like the
  system's Now Playing / call UI. Updates are rate-limited, so mic/GIF motion is
  as smooth as the update cadence allows (a few fps).
- Live Activities need a **signed** install with the **App Group** and
  **Live Activities** entitlements. Sign with **KSign** (or a dev account).
  An unsigned LiveContainer install will **not** show the island.

## Build / install

CI (GitHub Actions, `macos-15`) builds an **unsigned** IPA on every push:
`.github/workflows/build-ipa.yml` → artifact **`Islander-ipa`**.

Then sign with KSign and make sure the **App Group** `group.com.islander.app`
is enabled for both the app and the `IslanderWidget` extension.

## Layout

```
app/
  project.yml                 XcodeGen project (app + widget extension)
  Shared/                     code compiled into BOTH targets
    IslandAttributes.swift    ActivityAttributes + ContentState
    IslandShared.swift        App Group id + Color(hex:)
    IslandVisuals.swift       bars / wave / pulse / frame views
  Islander/                   the app (control panel)
    IslanderApp.swift
    RootView.swift            UI + live preview
    IslandController.swift    Live Activity lifecycle + update loop
    AudioMeter.swift          mic → amplitude bands
    MediaImporter.swift       photo/GIF → frames in the App Group
    Info.plist / *.entitlements
  IslanderWidget/             the Live Activity / Dynamic Island
    IslanderWidgetBundle.swift
    IslandLiveActivity.swift
    Info.plist / *.entitlements
```
