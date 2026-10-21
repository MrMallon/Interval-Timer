# Interval Timer

A free interval timer for iPhone and iPad (Apple Watch next) for HIIT, Tabata, boxing, EMOM, circuits and physio. Built to match Timer Plus feature for feature and fix what its reviewers complain about.

**Free forever: no ads, no subscriptions, no in-app purchases, no tracking.** Everything stays on your device.

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
| `Packages/TimerKit/Tests` (31 tests) | Timer maths, cue timing, stopwatch, presets | Every push (quick check) |
| `AppTests` (21 tests, in the iOS Simulator) | Plays alongside music and only lowers it while speaking (when turned on), all-sounds-off leaves audio alone, phone calls pause and resume, cues on time in a real workout, history, saved-timer edits, voice lines | Simulator suite |
| `UITests` (8 tests, in the iOS Simulator) | Library, create and edit a timer, presets, full workout, pause and skip, **keeps running and beeping in the background**, stopwatch, settings | Simulator suite |

The quick check (~2 min) runs on every push. The simulator suite (~14 min) runs when you add the **simulator-tests** label to a pull request (it then re-runs on every push until you remove the label), or when you start the CI workflow by hand from the Actions tab. macOS minutes count 10× against GitHub's free allowance on a private repo, so one simulator run uses about 140 of the 2,000 free minutes a month.

Each simulator run publishes its screenshots to the [`ci-screenshots`](../../tree/ci-screenshots) branch.

Not covered by the simulator: real phone calls, the lock button and other music apps. Check those once on a real iPhone.

## Layout

| Path | What it is |
| --- | --- |
| `Packages/TimerKit` | Pure Swift package: workout model, timer engine, cue planner, stopwatch, presets. Shared with the future Watch app. Fully unit-tested. |
| `App/Run` | Run screen, the session that drives a workout, summary, notification fallback |
| `App/Audio` | Tone synthesiser (no audio files), speech, audio session handling |
| `App/Views` | Library, editor, presets, history, stopwatch, settings |
| `App/Models` | SwiftData models and settings |
| `AppTests`, `UITests` | Simulator unit and UI tests |
| `project.yml` | XcodeGen spec (the `.xcodeproj` is generated, not committed) |

## How timing works

The engine never counts ticks. It stores when the run started and how much time was banked before pauses, so the current state is a pure function of the clock. Every cue (beeps, countdown, voice, ticks) is planned up front from the workout and fired as the clock passes it. If the app wakes up late, stale cues are dropped and only "where you are now" is announced.

While sounds are on, a continuously rendering audio engine keeps the app running on a locked screen. With every sound off the app never touches your audio session, and local notifications mark phase changes instead.

## Roadmap

1. MVP (this) — iPhone and iPad
2. Apple Watch app (standalone + synced timers), VoiceOver pass, more languages
3. Live Activity and Dynamic Island, widgets, Siri shortcuts, Apple Health logging, iCloud sync
