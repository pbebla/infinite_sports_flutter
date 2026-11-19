# Fresh-read probe — run sheet (Task 0 of `2026-11-13-fresh-reads.md`)

The probe is `tool/fresh_read_probe.dart`: a separate app entry point that starts Firebase and the
Realtime Database exactly like `lib/main.dart` (env config → `Firebase.initializeApp` → emulator
switch → `.info/serverTimeOffset` listener → on-disk cache ON) and nothing else (no sign-in, no
notifications, no app UI). Each launch runs ONE phase picked by a launch counter
(`shared_preferences` key `freshProbeLaunch`). It only READS `SyncProbe/value` and children of
`SyncProbe/barrier/`; it never writes and never calls `.get()`. Every bounded wait is 8 s
(`kRevealReadTimeout`). Note: in this plugin version `once()` is `onValue.first` (a listener that
cancels itself after its first event).

## Before you start (read this)

1. **Database rules.** The probe is signed out. The LIVE rules are `database.rules.stage1.json` (root `.read: true`), so the
   signed-out reads work today with no deploy (checked 2026-11-13: status 200). Under the stricter target rules
   (`database.rules.json`) `SyncProbe` would need a public-read entry. Write the test values with an admin tool, never through the probe.
2. **Same package id as the fan app.** The probe APK is `com.infinitesports.Infinite_Sports_App`.
   Installing it REPLACES the fan app on that phone, and it shares the fan app's data folder (the
   database's saved copy and `shared_preferences`). If a release/store build is installed, the
   debug install fails until you uninstall it (which wipes that app's data and sign-in). Use a test
   phone; reinstall the real app afterwards.
3. **Cold start every launch.** Always force-stop before changing the value and before starting the
   next launch, so no listener from the previous run is alive when the value changes.

## Commands (Git Bash)

```bash
cd /c/Users/zayaa/StudioProjects/infinite_sports_flutter
FLUTTER=/c/src/flutter/bin/flutter
ADB=/c/Users/zayaa/AppData/Local/Android/Sdk/platform-tools/adb.exe
PKG=com.infinitesports.Infinite_Sports_App

# Build (a few minutes)
$FLUTTER build apk --debug -t tool/fresh_read_probe.dart

# Clean slate (recommended before launch 1: no saved copy, counter 0)
$ADB uninstall $PKG

# Install (later installs with -r keep the data)
$ADB install -r build/app/outputs/flutter-apk/app-debug.apk

# One launch = one phase (cold start, logcat cleared first)
$ADB shell am force-stop $PKG
$ADB logcat -c
$ADB shell am start -n $PKG/.MainActivity
#   ...wait until the screen shows the PROBE|...|DONE line (phase 8 can take up to about 2 minutes: every timed-out step waits its full 8 s)...
$ADB logcat -d | grep "PROBE|"
$ADB shell am force-stop $PKG
```

Optional builds:

- Reset the counter but keep the saved copy:
  `$FLUTTER build apk --debug -t tool/fresh_read_probe.dart --dart-define=PROBE_RESET=1`, install,
  launch once (it only resets and says so), then install the normal build again. The next launch is
  phase 1.
- Re-run one phase: add `--dart-define=PROBE_PHASE=<1..8>`. That build runs the phase on every
  launch and does NOT advance the counter.
- Launches after 8 repeat phase 8 (the START line says so).

## Line format

`PROBE|<launch>|<phase>|<step>|<value or ERR:<type> or TIMEOUT>|<ms since step start>|<ms since app start>`

- `START` / `DONE` open and close each run; `connected` lines log `.info/connected` at start and on
  every change.
- `... event#n` = an `onValue` event (with its arrival time); `... cancel` = that listener cancelled
  (`events=` and the latest value).
- `... late` = a `once()` that passed the 8 s bound but answered afterwards.
- A value `null` means the path does not exist (expected for barrier children).

## Controller steps per launch

Before each launch: force-stop, set `SyncProbe/value` in the console, then launch.

| Launch | Set `SyncProbe/value` to | Phone | Phase (what runs) |
|---|---|---|---|
| 1 | `A` | online | `once()` — primes the saved copy |
| 2 | `B` | online | `once()` → 3 s → `once()` → 3 s → `once()` |
| 3 | `C` | online | wait for `.info/connected` → `once()` → 3 s → `once()` |
| 4 | `D` | online | `onValue` 6 s (every event logged) → cancel → `once()` |
| 5 | `E` | online | linger: `onValue`, cancel 300 ms after first event → `once()` |
| 6 | `F` | online | `once()` (baseline) → barrier: `onValue`; at first event `once()` on `SyncProbe/barrier/<new push id>`; log the latest value event when the barrier answers; cancel |
| 7 | `G` | online | `once()` (baseline) → barrier on `SyncProbe/barrier/fixed` twice in a row |
| 8 | `H`, then turn **airplane mode ON** before launching | offline | every variant above, each bounded at 8 s |

## Results (fill in from the PROBE lines)

### Phase 1 (value set: A)

| Step | Value | Step ms | What this tells us |
|---|---|---|---|
| connected (first) | | | |
| once | | | Clean install: fresh A expected; primes the saved copy |

### Phase 2 (value set: B, saved copy should be A)

| Step | Value | Step ms | What this tells us |
|---|---|---|---|
| once#1 | | | Does a cold-start `once()` answer from the saved copy (A) or the server (B)? |
| once#2 (+3s) | | | Does it become fresh once the connection is up? |
| once#3 (+3s) | | | |
| connected changes (app ms) | | | When the connection came up relative to the reads |

### Phase 3 (value set: C)

| Step | Value | Step ms | What this tells us |
|---|---|---|---|
| wait-connected | | | |
| once#1 (connected) | | | Is a `once()` after `.info/connected` = true fresh? |
| once#2 (+3s) | | | |

### Phase 4 (value set: D)

| Step | Value | Step ms | What this tells us |
|---|---|---|---|
| onValue6s event#1 | | | First event: saved copy (C?) or server (D)? |
| onValue6s event#2.. | | | Does a second, fresh event follow, and how long after? (sets the linger time) |
| onValue6s cancel | | | |
| once after onValue | | | Did the live listener renew the saved copy? |

### Phase 5 (value set: E)

| Step | Value | Step ms | What this tells us |
|---|---|---|---|
| linger event#1 | | | |
| linger event#2 (if any within 300 ms) | | | |
| linger cancel | | | |
| once after linger | | | Is 300 ms of listening enough to get the server value? |

### Phase 6 (value set: F)

| Step | Value | Step ms | What this tells us |
|---|---|---|---|
| once (baseline) | | | Did phase 5's short linger renew the saved copy across a restart (E vs older)? |
| fresh onValue event#1 | | | |
| fresh barrier#1 <id> | | | How long a server round trip on a never-loaded path takes |
| fresh value-at-barrier#1 | | | When the barrier answers, has the value already reached F? (barrier works = yes) |
| fresh onValue cancel | | | |

### Phase 7 (value set: G)

| Step | Value | Step ms | What this tells us |
|---|---|---|---|
| once (baseline) | | | |
| fixed onValue event#1 | | | |
| fixed barrier#1 fixed | | | |
| fixed value-at-barrier#1 | | | |
| fixed barrier#2 fixed | | | Is the second read of a fixed child answered locally (fast, no round trip)? Then a fixed child is NOT a barrier |
| fixed value-at-barrier#2 | | | |

### Phase 8 (value set: H, airplane mode ON)

| Step | Value | Step ms | What this tells us |
|---|---|---|---|
| connected (first) | | | |
| 8a once | | | Offline cold start: saved copy, or hangs until TIMEOUT? |
| 8b wait-connected | | | (TIMEOUT expected) |
| 8c once | | | |
| 8d onValue6s event#1 / cancel | | | Does a listener answer from the saved copy offline? |
| 8d once after onValue | | | |
| 8e linger event#1 / cancel | | | |
| 8e once after linger | | | |
| 8f fresh barrier#1 / value-at-barrier#1 | | | Offline: a barrier on a never-loaded path must TIMEOUT (bounded), not hang |
| 8g fixed barrier#1, #2 / value-at-barrier | | | Offline: is the fixed child answered from the saved copy? |
| any `... late` lines | | | |

## Afterwards

- Turn airplane mode off, uninstall the probe, reinstall the real fan app.
- Remove the temporary `SyncProbe` read rule if it is not kept for Task 6.

## Results (emulator Pixel 7, Android 16 image, 2026-11-13 evening, run by the controller)

Values A to H were written to `SyncProbe/value` before launches 1 to 8; the node was deleted afterwards.

| Launch | Server value | What the probe saw | What this tells us |
|---|---|---|---|
| 1 | A | `once` = A after 2.1 s (waited for the connection) | With no saved copy a one-shot read waits for the server. |
| 2 | B | `once` at start (not connected) = **A**; `once` 3 s later (connected) = **A**; `once` 3 s after that = **B** | A one-shot read answers from the saved copy. Before the connection is up it refreshes nothing. While connected it still returns the old value, and (for this tiny value) the saved copy is renewed so the NEXT read is fresh: one behind. |
| 3 | C | waited for connected; `once` = **B**; `once` 3 s later = **C** | The saved copy survives a cold start (B came from launch 2's renewal). Connected one-shot reads are one behind. |
| 4 | D | `onValue` event 1 = C at 80 ms (saved copy); connected at 0.9 s; event 2 = **D** about 320 ms after the connection; `once` afterwards = D | A listener that stays attached gets the server's value a few hundred ms after the connection is up. |
| 5 | E | `onValue` event 1 = D; cancelled 300 ms later, before the connection was up; `once` = D | A short linger that ends before the connection is up renews nothing (launch 6's first read was still D). |
| 6 | F | `once` = **D** (stale); `onValue` event 1 = D; connected; event 2 = **F**; a `once` on a never-loaded UNIQUE child returned ~60 ms after event 2; latest value at that moment = F | The barrier works: when a read of a never-loaded unique child returns, the earlier listener already holds the server's value. Cost: one round trip. |
| 7 | G | same as 6 with a FIXED child: first barrier returned after the fresh event; the second returned in 34 ms | A fixed barrier child is answered from the saved copy the second time. The barrier child must be unique every time. |
| 8 | H, airplane mode | every read = **G** within 16 to 121 ms; wait-for-connection and the unique barrier timed out at 8.0 s; nothing hung | Offline, everything answers from the saved copy at once; the server-first path must fall back when its bound passes. |

**Also observed on the real app the same day:** `Logo Urls` and `Futsal/15/Line Ups` (several KB) stayed stale across five cold starts, i.e. the one-behind renewal seen above for a tiny value did NOT happen for them. Do not rely on one-behind.

**Decisions for Task 1:**
- A refreshing read returns the first event at once and keeps ONE shared listener per path attached until the server has answered (barrier returned) or 15 s have passed, whichever is first. A fixed short linger is useless: it can end before the connection is up.
- A server-first read attaches the listener, waits for the connection, then for the barrier; the value at that moment is the server's. Past the bound (8 s) it returns the saved copy marked not-from-server.
- The barrier is a `once()` on a new unique child of one public, never-written node (`SyncBarrier/<push id>`); Task 6 gives that node a public-read, no-write rule in both rules files.
