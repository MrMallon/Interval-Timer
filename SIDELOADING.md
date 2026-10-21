# Install Interval Timer on your iPhone from Windows

This puts the app on your iPhone for free, using your normal Apple ID. No Mac and no paid developer account needed.

**The catch:** with a free Apple ID, Apple lets a sideloaded app run for **7 days**. After that it won't open until you re-install it (your timers and history are kept if you don't delete the app first). Free accounts can also only have **3 sideloaded apps** on a device at once.

## What you need

- A Windows PC and a USB cable for your iPhone.
- **iTunes and iCloud downloaded from Apple's website**, not the Microsoft Store versions. Sideloading tools can't talk to the Microsoft Store versions. If you have those, uninstall them first.
  - iTunes: apple.com/itunes → "Windows" → download the 64-bit installer.
  - iCloud for Windows: from Apple's support site (the non-Store installer).
- **Sideloadly** (free) from sideloadly.io. AltStore (altstore.io) works too; the steps are similar.
- Your Apple ID. A spare Apple ID also works if you'd rather not use your main one.

## 1. Download the app

Open the **[Latest build](../../releases/tag/latest)** release page and download **`IntervalTimer.ipa`**.

There's also `IntervalTimer-with-Watch.ipa`, which includes the Apple Watch app. Free Apple IDs usually can't install Watch apps, so start with `IntervalTimer.ipa`.

A new build appears here automatically every time the app changes on `main`.

## 2. Install it

1. Plug the iPhone into the PC and tap **Trust** on the phone if asked.
2. Open Sideloadly. Your iPhone should appear in the **iDevice** box.
3. Drag `IntervalTimer.ipa` onto the Sideloadly window.
4. Type your Apple ID email and click **Start**. Enter your Apple ID password (and the two-factor code) when asked. Sideloadly sends these to Apple only, to sign the app.
5. Wait for **Done.**

## 3. Allow it on the iPhone (first time only)

1. **Turn on Developer Mode:** Settings → Privacy & Security → Developer Mode → on. The phone restarts; after it does, tap **Turn On** and enter your passcode.
2. **Trust your Apple ID as a developer:** Settings → General → VPN & Device Management → tap your Apple ID under "Developer App" → **Trust**.
3. Open Interval Timer.

## 4. Every week

Re-install before the 7 days are up: plug in, open Sideloadly, drag in the `.ipa` again (the newest one is fine) and click **Start**. Don't delete the app first, so you keep your timers and history.

Sideloadly can also refresh automatically over Wi-Fi while your PC is on: turn on its auto-refresh option after installing.

## What works with a free Apple ID

| Feature | Works? |
| --- | --- |
| Timers, voice, beeps, background running, history, stopwatch, settings | Yes |
| Lock Screen countdown and Dynamic Island (Live Activity) | Yes |
| Siri: "Start Tabata in Interval Timer" | Yes |
| Home Screen "Quick start" widget | Shows up, but may only say "Open Interval Timer to add timers": it needs an App Group, which free signing may not grant |
| Apple Watch app | Usually not installable with a free Apple ID |

## Troubleshooting

- **Sideloadly doesn't see the iPhone:** unlock the phone, re-plug it, and make sure the Apple-website iTunes is installed (not the Store one).
- **"Maximum number of apps" error:** free accounts allow 3 sideloaded apps per device. Delete another sideloaded app.
- **"Untrusted Developer" when opening:** do step 3.2 again.
- **The app stopped opening after a week:** that's the 7-day limit. Re-install (step 4).

When you're ready for the App Store (or want builds that last a year and include the Watch app), a paid Apple Developer membership ($99/year) lets GitHub upload builds to TestFlight instead.
