# BudControl Finder 6

An iPhone companion app and guided clean-room Bluetooth protocol finder for Moto Buds-style earbuds.

## What is new

The Finder tab replaces the log-first workflow with a three-step capture:

1. **Prepare Baseline** — records current characteristic values.
2. **Start Action Capture** — marks the exact moment you perform one gesture or state change.
3. **Analyze Changes** — filters scan/RSSI/subscription noise and ranks characteristics by notifications, byte changes, repeated values, vendor-service likelihood, and write capability.

Each result shows before/after hex, changed byte positions, GATT properties, a confidence score, and useful tags. Repeatable results can be saved as observations and exported.

## Included Moto Buds+ research hints

The Finder highlights vendor services already observed in the user's own Moto Buds+ captures:

- FE2C
- FC9D
- 66666666-6666-6666-6666-666666666666
- FC9D9FE0-4899-11EE-BE56-0242AC120002

These are **hints, not claimed protocol definitions**. FC9D0004 receives a battery-like tag only when its value shape looks percentage-like; it is still treated as an observation until repeated tests confirm the meaning.

## Guided gesture presets

The app includes quick tests for noise-control cycling, play/pause, next/previous track, voice assistant, in-ear state changes, case state, and a custom action.

## Advanced lab

The original raw GATT lab is still available under **Finder > Advanced GATT Lab** for:

- Full service/characteristic browsing
- Reads and notification controls
- Raw event logs
- One-shot verified writes
- Verified command mapping and JSON import/export

The Finder itself does not guess write payloads or automate firmware/reset commands.

## GitHub IPA build

Upload the repository contents to GitHub, open **Actions**, run **Build BudControl IPA**, and download the `BudControl-unsigned-IPA` artifact. Extract it to get `BudControl-unsigned.ipa` for Sideloadly.

The bundle identifier is `com.budcontrol.protocolfinder`, so this edition can be installed separately from the earlier companion build.
