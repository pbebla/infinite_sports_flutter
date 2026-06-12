# Emulator Dress Rehearsal

This runbook verifies the full notification-Watcher alert sequence (kickoff, goal with assist,
undo silence, re-recorded goal, full-time, post-final silence) using the Firebase Local Emulator
Suite before any deploy. It is completely safe: the `demo-rehearsal` project ID uses Firebase's
special `demo-` prefix which keeps everything fully offline with zero reads/writes to production.
`sendAlert` in the emulator logs a `DRY-RUN sendAlert` line instead of calling FCM, so no real
push notifications are sent.

---

## Step 1 — Build

```bash
cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter/functions"
npm run build
```

Expect exit 0 with no TypeScript errors.

---

## Step 2 — Start emulators (background)

```bash
export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr"
export PATH="$JAVA_HOME/bin:$PATH"
cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter"
npx firebase-tools emulators:start --only functions,database --project demo-rehearsal
```

Wait until the console prints:

```
All emulators ready! It is now safe to connect your app.
```

Functions port: `127.0.0.1:5001` — Database port: `127.0.0.1:9000`

> Note: Node 24 vs engine 22 warning is harmless.

---

## Step 3 — Seed a fake match

```bash
curl -s -X PUT "http://127.0.0.1:9000/Tournaments/T1.json?ns=demo-rehearsal-default-rtdb" \
  -d "{\"Name\":\"Test Tournament 2026\",\"Teams\":{\"e1\":{\"Name\":\"Eagles\"},\"l1\":{\"Name\":\"Lions\"}},\"Matches\":{\"M1\":{\"Team1Id\":\"e1\",\"Team2Id\":\"l1\",\"Team1Score\":0,\"Team2Score\":0,\"Status\":0,\"MatchLocation\":\"Field A\"}}}"
```

---

## Step 4 — Simulate the match

```bash
NS="ns=demo-rehearsal-default-rtdb"
BASE="http://127.0.0.1:9000/Tournaments/T1/Matches/M1"

# Kickoff (Status 0 -> 1) — immediate alert
curl -s -X PUT "$BASE/Status.json?$NS" -d "1"; sleep 3

# Goal: activity entry then score 0 -> 1 — alert fires ~10s later (grace window)
curl -s -X PUT "$BASE/Team1Activity.json?$NS" -d "{\"12\":[{\"Goal\":\"Sam Smith\"},{\"Assist\":\"Skylar Jackson\"}]}"
curl -s -X PUT "$BASE/Team1Score.json?$NS" -d "1"; sleep 14

# Undo (1 -> 0): SILENT; then re-record (0 -> 1): alerts again ~10s later
curl -s -X PUT "$BASE/Team1Score.json?$NS" -d "0"; sleep 3
curl -s -X PUT "$BASE/Team1Score.json?$NS" -d "1"; sleep 14

# Full time (Status 1 -> 2) — immediate alert
curl -s -X PUT "$BASE/Status.json?$NS" -d "2"; sleep 3

# Post-final score edit: must be SILENT (match is finished)
curl -s -X PUT "$BASE/Team1Score.json?$NS" -d "2"; sleep 12
```

---

## Step 5 — Expected log sequence

Check the emulator console for exactly these four `DRY-RUN sendAlert` lines, in order. No
additional DRY-RUN lines should appear (undo write and post-final edit must be silent).

- [ ] `DRY-RUN sendAlert` kind `kickoff`, title `Kickoff: Eagles vs Lions`, body `Now playing — Field A`
- [ ] `DRY-RUN sendAlert` kind `goal`, title `GOAL! Eagles 1 – 0 Lions`, body `Sam Smith (Eagles) 12' · Assist: Skylar Jackson`
- [ ] `DRY-RUN sendAlert` kind `goal` — second time, same title/body (the re-recorded goal after undo)
- [ ] `DRY-RUN sendAlert` kind `fulltime`, title `Full time: Eagles 1 – 0 Lions`

---

## Step 6 — Stop emulators

Ctrl-C in the emulator terminal, or kill the java process:

```bash
# macOS/Linux
pkill -f "firebase-database-emulator"

# Windows PowerShell
Stop-Process -Name java -Force
```
