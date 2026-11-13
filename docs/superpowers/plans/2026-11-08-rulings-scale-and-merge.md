# Decisions made during the build — scale fixes + duplicate-account merge (2026-11-06 → 11-08)

Opus 5.5 ran both plans (`2026-11-06-fantasy-scale-fixes.md`, `2026-11-06-merge-duplicate-accounts.md`) with a builder and a reviewer per task and a final whole-branch review per plan. These are the calls made along the way, in order. Each line says what was decided, why, and what it costs if it was the wrong call. Nothing here is deployed, applied or sent.

## Things the owner will notice

1. **A finished season switches itself off — only when nothing is left.** The 15-minute check stops for a season once the league marks it Finished **and** every week is scored, the season badges are settled, the week ledger is clean, and no game day has been added since. If any of these is not true it keeps running as today. *(Cost if wrong: a finished season with an odd leftover keeps today's cost.)* An earlier version missed two cases (a game added after Finished, and Finished flagged before the last week was scored) — the final review caught both and they are fixed.
2. **A season badge switched on after a season ended is not handed out automatically.** It needs a re-score of a week. *(Cost: one manual step if you ever enable a badge after the season.)*
3. **Removing an automatic season award by hand in the Manager now sticks.** Before, the 15-minute check would put it back. *(Cost: if you remove one by mistake, re-score a week to restore it.)*
4. **The over-budget warning only re-checks squads after a price change, a budget change, a new or reopened week.** A fresh save is still judged at the deadline as always. *(Cost: a hand-forged squad gets no early warning; it's still judged at the lock.)*
5. **Tapping a manager on the leaderboard:** if their team can't load, it says "Couldn't load this team." A slow connection just keeps the loading placeholder until it arrives — it never shows a fake "no team". *(Cost: a connection that hangs silently keeps the placeholder until the sheet is reopened, as before.)*
6. **Merged accounts disappear from the Manager's Users page and its account pickers.** They still exist in the database (stamped "merged into …"), and your sign-up export still finds them. *(Cost: you can't browse merged accounts in the Manager.)*
7. **Every outward step previews first:** the merge messages and the login switch print what they would do and only act with `--send`. The real merge only runs with the exact plan code from the practice run you read. *(Cost: one extra command per step.)*
8. **One push per kept account** (not one group push), so a later batch never re-messages people already told. *(Cost: several rows in the Manager's campaign list instead of one.)*
9. **Turning old logins back on always works**, before or after an undo, because it's the safe direction. *(Cost: it could re-enable an old login that was disabled for some other reason — only for the people on the merge list.)*
10. **The merge tool refuses a person whose old account holds data it can't move** — a fantasy team, a registration, awards or tournament history — instead of silently leaving it behind. *(Cost: those people need a deliberate extension, e.g. Parlevino.)*

## Engineering calls (for Fable or a future reviewer)

- Scale T1: `exists()` answers for map nodes only, and every test fake mirrors production (a single value reads as "absent") — fixes the whole class of mismatch, not one call site. The season-settled marker is read with `read() != null`. *(Cost: a future caller wanting single-value existence must use `read()`.)*
- Scale T2: the daily price update finds the latest scored week from History's week numbers (keys only), not from the "Scored" stamp — the stamp is warn-only and never healed, so a missing stamp would have silently skipped a week's prices. *(Cost: one tiny extra read per season per run.)*
- Scale T4: the settled marker is stamped on every completed settle (zero awards included) and means "every scoreable week finalized AND badges settled"; the all-badges-off shortcut and the sweep backfill both re-check the weeks first. *(Cost: a season stuck mid-way keeps doing its normal checks until it's truly over.)*
- Scale T5: a failed read during the "is this season over?" check runs the full sweep with one warning instead of skipping the season. *(Cost: one extra log line type.)*
- Scale T6: the over-budget stamp carries the budget too, and a called-off week clears it so the reopened week re-checks once. *(Cost: one extra full check after a budget edit or a rewind.)*
- Scale final: when the database's keys-only read fails, the season list comes from the one full read (no double download); a failed per-season settings read skips only that season. *(Cost: none.)*
- Scale: `healOpenWeek` still reads every manager's money baseline on most open-week checks (~11 KB a check at league size) — deferred, measured, listed in the follow-ups doc. *(Cost: ~1 MB a day per active season at 60 managers.)*
- Scale tests/tools: the "squads read once" test counts only the over-budget step's reads; the load-test helper takes optional names/uids; the final review ran on Opus because Fable time is the owner's to spend. *(Cost: negligible.)*
- Merge T2 (Manager) ran in parallel with T1 (fan) — different repos, no shared files. *(Cost: none.)*
- Merge T5: the production practice run (read-only) and the Season 16 duplicate check ran during the build. They write nothing. *(Cost: a few hundred KB of reads.)*
- Merge T3: the fan notice gets the account id from the sign-in gate (not a global), closes any open pages before signing out, and closes itself if the person is signed out some other way; merged accounts also skip the "complete your profile" and favorites prompts. *(Cost: none.)*
- Merge T4/T5: the planner and tool turned conventions into enforced guarantees — exact undo values, masked-email check, accurate practice-run text, roster rows must exist (a typo can't create a player), independent map validation, never overwrite a single value with a map, atomic backup file, undo command printed on any stop, refused people make the run end "not OK". *(Cost: a larger tool.)*
- Merge T6: email-hiding also covers addresses with `'` or `_`; the finished message reminds that notices only send if the email function is deployed. *(Cost: none.)*
- Merge T7: account ids are shortened to 6 characters in every error the tool prints, in every mode. *(Cost: slightly less specific error text.)*
- Merge final: real player email and names were removed from test files and the plan (commits are local; nothing was pushed); stamps write "merged into" last so the notice always has the hint; the practice run shows how many old accounts are in player search; the login switch refuses until every notice is sent (override flag exists). *(Cost: the plan code changed to `31ae18c0f5293f4a` — use whatever the latest practice run prints.)*

## Left for later (all recorded in `2026-11-04-fantasy-deferred-follow-ups.md` or the build ledgers)

- A friendly sign-in message for a switched-off old login (today: a generic error; the email they receive names the address to use).
- Plan text D12 still describes one group push (the code and runbook do one per kept account).
- Two test assertions made toothless by the email scrub (`merge_accounts_logic.test.ts:652`, `merge_notice_watch.test.ts:130`).
- If the last week is scored more than a day after its deadline, the Manager can still show it LOCKED (pre-existing; that season simply keeps its normal checks).

---

# Addendum — Parlevino + "bring everything" extension (built 2026-11-08, Fable 5.1 as controller)

The owner's decisions: keep Parlevino's Season 16 Gmail account and fold in the iCloud one; move every merged person's old sign-up records (my recommendation, accepted); one batch of eleven; "build it" without switching to Opus — so Fable ran the build with the builders and reviewers on cheaper models.

## Things the owner will notice

1. **The merge now also moves old sign-up records (paid or unpaid) to the kept account**, for all eleven people. The old account ends up with nothing but the "merged" stamp. *(Cost: the plan code changed; it is `bd98b0592255a300` as of the last read-only dry run.)*
2. **Parlevino's Season 15 move only works while the Season 15 test fantasy data is still there** — and so does undoing it. If the test data has been cleared, the tool refuses both directions and the runbook says to tell Claude. *(Cost: the order in the runbook matters: merge → phone check → clear the test data → Season 16.)*
3. **Undo is all-or-nothing when a stopped run was finished by a later run**: it refuses and tells you to undo the newer backup first. *(Cost: one extra undo step in a rare sequence; nothing can be lost.)*
4. **Old position info (age etc.) is copied only when the new account has none** and may be out of date; the person can fix it in their profile.

## Engineering calls

- The tool must prove it looked for sign-up records: the snapshot carries each league's season list; a missing list refuses the person ("sign-ups were not scanned") instead of silently moving nothing. *(Cost: none.)*
- Whitespace-only sign-up values count as blank and refuse the person — one meaning of "blank" everywhere. *(Cost: a stray record needs a hand fix.)*
- A relink in a fantasy season is allowed only while `TestFill` is present (the "finished and paused" shortcut was dropped: the roster sync would add any roster name missing from the market). The same guard applies to undo. *(Cost: an undo after the fill clear needs Claude — fails safe.)*
- Every DELETE re-reads the old record and the kept copy right before it; `{}`/`[]` are refused as write values; the plan code binds every remove and its order. *(Cost: none.)*
- Undo refuses up front when a later run finished a stopped run's move (data-loss sequence found by review), and leaves a kept copy alone if its record moved to the other status. *(Cost: rare extra steps.)*
- Task 1's builder pulled the tool's read-only sign-up reads forward (one interface); the runbook task ran in parallel with a review (no shared files). *(Cost: none.)*
- The three league sign-up keys are hard-coded (Futsal, Basketball, Flag Football) rather than read from the database — equivalent today. *(Cost: a fourth league sport would need one line.)*

## Left for later
- A hand-deleted old record during a stop also trips the "finished by a later run" refusal (fails safe; the runbook says to tell Claude).
- The Manager "Find duplicates" screen with near-name matching (Season 17).
