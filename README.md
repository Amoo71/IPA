# TermiChat

A self-built, **CLI-themed WhatsApp client for iOS**. It links to your account
through the official WhatsApp **multi-device (WhatsApp Web)** protocol — no
subscription, no server, everything runs inside the app. Built to be sideloaded
with **LiveContainer**.

```
┌────────────────────────┐
│      T E R M I C H A T  │
└────────────────────────┘
$ connected to whatsapp
```

## What it does

- Links to WhatsApp by scanning a QR code (Settings → Linked Devices), exactly
  like WhatsApp Web — the session is stored **locally and encrypted** on device.
- Shows your chats in a modern terminal aesthetic (monospaced font, dark
  terminal palette, prompt-style UI):
  - top bar: `connected as: <name>` + a `[ settings ]` button on the right
  - a centered, rounded `> search` bar
  - an `archived` row
  - the chat list, with **pinned chats** floated to the top
- Live incoming/outgoing messages, unread badges, pinned / archived / muted
  state, group vs. direct chats.

## How it is built

| Layer | Tech |
|-------|------|
| WhatsApp connection | [`whatsmeow`](https://github.com/tulir/whatsmeow) (Go) compiled to a native iOS `Wabridge.xcframework` via `gomobile bind` |
| UI | SwiftUI, monospaced, terminal theme |
| Bridge | Go ↔ Swift events as JSON strings (`bridge/wabridge.go` ↔ `ios/.../WhatsAppBridge.swift`) |
| Packaging | XcodeGen + `xcodebuild` → **unsigned `.ipa`** in GitHub Actions |

```
bridge/                 Go whatsmeow wrapper (gomobile-friendly)
ios/                    SwiftUI app + XcodeGen project.yml
.github/workflows/      build-ipa.yml  →  produces TermiChat.ipa
```

## Getting the IPA

The IPA is built by the **Build IPA** GitHub Actions workflow (runs on every
push to `main`, or trigger it manually via *Actions → Build IPA → Run workflow*).

1. Open the workflow run → **Artifacts** → download `TermiChat-ipa`.
2. Unzip to get `TermiChat.ipa`.
3. Install it in **LiveContainer** (the IPA is intentionally unsigned;
   LiveContainer provides the runtime/signing).
4. Launch, open WhatsApp on your phone → **Settings → Linked Devices → Link a
   Device**, and scan the QR shown in TermiChat.

> The first sync pulls your recent chats via WhatsApp's history sync; pinned and
> archived flags come straight from your account.

## Notes & limits

- This is an unofficial client. Use at your own risk; linking too many devices
  or unusual activity can have account consequences.
- History sync only provides *recent* conversations — older chats appear as new
  messages arrive.
