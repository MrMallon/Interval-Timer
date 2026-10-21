# Interval Timer

A free interval timer for iPhone, iPad and Apple Watch for HIIT, Tabata, boxing, EMOM, circuits and physio. Built to match Timer Plus feature for feature and fix what its reviewers complain about.

**Free forever: no ads, no subscriptions, no in-app purchases, no tracking.** Everything stays on your devices: no accounts, no servers, no cloud. iPhone and Apple Watch talk to each other directly.

Available in 15 languages: English, Dutch, French, German, Italian, Japanese, Korean, Portuguese (Brazil), Russian, Simplified Chinese, Spanish, Swedish, Thai, Traditional Chinese and Turkish.

## What's in this version (MVP)

- Simple timers: get ready, work, rest, rounds, cycles, rest between cycles, cool down
- Custom timers: set every interval yourself (pyramids, ladders, named exercises)
- Presets: Tabata, HIIT 40/20, EMOM, boxing, MMA, circuit, physio holds, pyramid
- Big colour-coded run screen with round and cycle counters, screen flash, skip and pause
- Beeps, voice guidance, optional ticking, final countdown, "time left" markers, "next up" announcements
- Runs on a locked screen and over your music; never ducks music unless you turn that on
- Pauses for phone calls and resumes after
- Saved timers you can edit, duplicate, reorder and delete
- Interval stopwatch with laps
- History with weekly totals and "start again"
- Pale colours mode, keep-screen-on, haptics
- Live Activity: the countdown, phase and round on the Lock Screen and in the Dynamic Island
- Quick start widget for the Home Screen: tap a timer to start it
- Siri and Shortcuts: "Start Tabata in Interval Timer"

## Try it on your iPhone (no Mac needed)

Every change to `main` builds a fresh installable app on the [Latest build](../../releases/tag/latest) release. Install it from a Windows PC with a free Apple ID using Sideloadly: see **[SIDELOADING.md](SIDELOADING.md)**.

## Build and run

You need a Mac with Xcode 16 or later.

```sh
brew install xcodegen      # once
xcodegen                   # creates IntervalTimer.xcodeproj from project.yml
open IntervalTimer.xcodeproj
```

Pick your team under Signing & Capabilities, then run on a simulator or device. Re-run `xcodegen` whenever you add or remove files.

To run the engine tests without Xcode open:

```sh
cd Packages/TimerKit && swift test
```

## Testing

| Suite | What it covers | When it runs |
| --- | --- | --- |
| `Packages/TimerKit/Tests` (39 tests) | Timer maths, cue timing, stopwatch, presets, iPhone–Watch sync merging | Every push (quick check) |
| `AppTests` (30 tests, in the iOS Simulator) | Plays alongside music and only lowers it while speaking (when turned on), all-sounds-off leaves audio alone, phone calls pause and resume, cues on time in a real workout, history, saved-timer edits, voice lines, widget links, Live Activity contents, Siri "Start Timer" | Simulator suite |
| `UITests` (11 tests, in the iOS Simulator) | Library, create and edit a timer, presets, full workout, pause and skip, **keeps running and beeping in the background**, stopwatch, settings, the app in German and Japanese, Apple's accessibility audit on every screen, a widget link starting a timer with its Live Activity in the Dynamic Island | Simulator suite |
| Translation check | Every string in the code is in `Shared/Localizable.xcstrings` and translated into all 14 languages | Every push (quick check) |

The quick check (~2 min: engine tests plus iPhone and Watch builds) runs on every push to `main` and every pull request. The simulator suite (~14 min) runs on every pull request, and you can start it by hand from the Actions tab. The repo is public, so GitHub Actions minutes are free.

Each simulator run publishes its screenshots to the [`ci-screenshots`](../../tree/ci-screenshots) branch.

Not covered by the simulator: real phone calls, the lock button and other music apps. Check those once on a real iPhone.

## Layout

| Path | What it is |
| --- | --- |
| `Packages/TimerKit` | Pure Swift package: workout model, timer engine, cue planner, stopwatch, presets. Shared by the iPhone and Watch apps, plus iPhone–Watch sync merging. Fully unit-tested. |
| `App/Run` | Run screen, the session that drives a workout, summary, notification fallback |
| `App/Audio` | Tone synthesiser (no audio files), speech, audio session handling |
| `App/Views` | Library, editor, presets, history, stopwatch, settings |
| `Shared` | Code used by both apps: SwiftData models, settings, colours, voice lines, iPhone–Watch sync |
| `Watch` | Apple Watch app: library, editor, run screen with wrist taps and voice, history, settings |
| `Widgets` | Widget extension: Quick start Home Screen widget and the workout Live Activity / Dynamic Island |
| `SharedIOS` | Code shared by the iPhone app and its widget: Live Activity data, widget timer list, `intervaltimer://` links |
| `App/Intents` | Siri and Shortcuts: "Start Timer" with your saved timers |
| `AppTests`, `UITests` | Simulator unit and UI tests |
| `project.yml` | XcodeGen spec (the `.xcodeproj` is generated, not committed) |

## How timing works

The engine never counts ticks. It stores when the run started and how much time was banked before pauses, so the current state is a pure function of the clock. Every cue (beeps, countdown, voice, ticks) is planned up front from the workout and fired as the clock passes it. If the app wakes up late, stale cues are dropped and only "where you are now" is announced.

While sounds are on, a continuously rendering audio engine keeps the app running on a locked screen. With every sound off the app never touches your audio session, and local notifications mark phase changes instead.

## Languages and accessibility

- All text lives in `Shared/Localizable.xcstrings` (Xcode string catalog), shared by both apps. Counts use proper plural forms per language (Russian has four).
- CI fails if a string in the code is missing from the catalog or untranslated in any language.
- Voice guidance speaks in the phone's language.
- Phase colours pass WCAG AA contrast with white text; Pale colours mode uses dark text instead.
- Every control has a VoiceOver label; the stopwatch and countdowns are read as "1 minute, 23 seconds", not digits.
- Text follows the system text size; the summary stacks and scrolls at accessibility sizes.
- The accessibility audit test fails if the workout, summary or stopwatch screens have contrast, clipping or labelling problems.

## Apple Watch

The Watch app runs on its own (no iPhone needed) and also syncs with the iPhone:

- Timers made or edited on either device appear on the other; deletions sync too (newest change wins).
- Workouts finished on the watch show up in the iPhone's History, and the other way round.
- Cues are wrist taps with their system sounds, plus the same spoken guidance as the iPhone.
- A HealthKit workout session keeps the timer running with your wrist down. Nothing is written to Health.

To run it, pick the **IntervalTimerWatch** scheme in Xcode with a paired watch or a watch simulator. Signing needs the HealthKit capability, which `project.yml` already declares.

## Roadmap

1. MVP — iPhone and iPad (done)
2. Apple Watch app, accessibility pass, 15 languages (done)
3. Live Activity and Dynamic Island, Quick start widget, Siri shortcuts (done)
4. Optional Apple Health logging

No cloud sync is planned: everything stays on your devices.
