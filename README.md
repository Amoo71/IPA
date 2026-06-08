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
- Media (photo/GIF/video frames) is embedded directly into the Live Activity as
  small JPEGs (Apple caps the content at ~4KB, so island images are small) — so
  **no App Group is required**. Just sign the app + extension with **KSign**
  (or a dev account). An unsigned LiveContainer install will **not** show the
  island, because the system won't load the widget extension.

## Build / install

CI (GitHub Actions, `macos-15`) builds an **unsigned** IPA on every push:
`.github/workflows/build-ipa.yml` → artifact **`Islander-ipa`**.

Then sign the app **and** its embedded `IslanderWidget` extension with KSign.
No App Group or other capabilities are needed.

## Layout

```
app/
  project.yml                 XcodeGen project (app + widget extension)
  Shared/                     code compiled into BOTH targets
    IslandAttributes.swift    ActivityAttributes + ContentState (embeds JPEGs)
    IslandShared.swift        Color(hex:)
    IslandVisuals.swift       bars / wave / pulse / ring / dots / heart + slots
  Islander/                   the app (control panel)
    IslanderApp.swift
    RootView.swift            UI + live preview
    IslandController.swift    Live Activity lifecycle + battery-aware loop
    AudioMeter.swift          mic → amplitude bands
    MediaImporter.swift       photo/GIF/video → in-memory frames → tiny JPEGs
    Info.plist
  IslanderWidget/             the Live Activity / Dynamic Island
    IslanderWidgetBundle.swift
    IslandLiveActivity.swift
    Info.plist
```
