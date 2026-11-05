# Decisions made while building "transfers in the app" and "live everywhere" (2026-11-03/04)

Every decision Opus made on your behalf while the two plans were built, in order, with what it costs if it turns out wrong. Each one was checked by a reviewer. Tell me any you want changed.

## Transfers in the app

1. **"Still loading" never counts as "first team".**
   - Until the app has heard from the server, the transfer line says "Transfer count updating…". It never says "your first team is free", which could hide a real points cost.
   - *If wrong:* a brief "updating…" on first open.
2. **Re-filling Season 15 waits for your OK.**
   - Season 15 is the test season. I asked before running the re-fill, as always.
   - *If wrong:* the new transfer line doesn't show on the test season until you say yes.
3. **Re-running an old week can't scramble a newer manager's transfers.**
   - When the server re-runs an old week (a score correction), it skips anyone already working on a later week.
   - *If wrong:* a rarely-active manager's count catches up on his next save.
4. **Three small wording and data choices.**
   - "1 transfer" (not "1 transfers") in the cost line.
   - A label that tells Wildcard from Free Hit apart.
   - A failed read shows as "updating", never as a number.
   - *If wrong:* a wording tweak.
5. **The transfers line waits for the screen's first reveal,** so it never pops in late (your no-pop rule).
   - *If wrong:* the first open waits for one more small read.
6. **Deadline: before Season 16 opens for saving.** Not just before its first week ends. It's deployed now, so this is already met.
   - *If wrong:* nothing.
7. **"Checking your transfers…" only blocks Wildcard and Free Hit.**
   - If chip history can't be read, only those two are held, because they're the ones that can cost points.
   - Triple Captain and Bench Boost behave as before. A spent one would be cancelled at the deadline.
   - *If wrong:* during a rare read failure, a fan could arm a spent Triple Captain and see it cancelled.
8. **No automatic retry for chip history yet.**
   - If chip history fails to load, Wildcard and Free Hit stay held until the app is reopened.
   - *If wrong:* a fan reopens the app to play one after a rare failure.
9. **The transfer feed retries every 30 seconds after a failure.** During a long outage, the line can flicker.
   - *If wrong:* flicker during an outage.

## Live everywhere

10. **Small reads only.** The match page reads just your own team for that week, never every manager's teams.
    - *If wrong:* nothing (same numbers, less data).
11. **The demo seeded a full small league** so the app looked normal against the test database.
    - *If wrong:* the demo needed one more seed pass.
12. **Double-game days: a player stays "Not started" until his last game kicks off.**
    - If he missed game 1 but his team still has game 2 today, his bench player only comes on once game 2 starts. He might still show up, like a Premier League double gameweek.
    - *If wrong:* on a double day an absent starter's auto-sub waits until his team's last game starts.
13. **One place decides who is still to play**, from the day's game list.
    - *If wrong:* an internal tweak.
14. **Four small server choices.**
    - The friendly/league flag counts as a scoring change.
    - Undoing a kickoff clears that week's live numbers.
    - Live timing uses the server clock.
    - The backup check reads the stored week state.
    - *If wrong:* a small note in the design.
15. **No exemption for the "positions not locked" safety stop.** The plan required it, so it's in.
    - *If wrong:* nothing.
16. **Two extra fixes to the live backup.**
    - A Final game reset to "not started" also refreshes live.
    - The 15-minute backup also covers "some games finished, others not started".
    - Both would otherwise leave wrong live numbers on phones.
    - *If wrong:* a few extra server runs on match days.
17. **Live updates arrive as one bundle,** so you never see a new week's header with last week's board. Three duplicate number readers were merged into one (your fix-the-whole-bug-class rule).
    - *If wrong:* a slightly bigger change.
18. **My Team's court shows the team as it was locked that week.**
    - After the week, the server resets your saved team: it switches off Triple Captain and puts back your pre-Free-Hit team. So the court and the ×2/×3 badge are drawn from that week's locked team, never the saved one.
    - *If wrong:* one more small read while the week is locked.
19. **Three "never say something untrue" fixes on My Team.**
    - "Final · N pts" stays until editing reopens.
    - A failed load says plain "Locked" instead of "waiting for kickoff".
    - An unknown player shows no line instead of "0 pts".
    - *If wrong:* one extra wording string.
20. **The Manager live work ran alongside the fan-app work.** They're separate apps, so they can't collide.
    - *If wrong:* nothing.
21. **Manager weeks table: the live row shows "4" under the GW column,** not "GW4", matching the other rows.
    - *If wrong:* a one-line change.
22. **Two small wording choices.**
    - "Bonus (provisional)" is capitalised like the other lines.
    - The match page's "Your gameweek so far" line shows on any game of a live week, including finished ones, because "so far" is true until the week ends.
    - *If wrong:* one word or one condition.
23. **Final fixes before deploy.**
    - The ESPN-style steady order also applies to the Manager's profiles list.
    - "1 pt", never "1 pts", everywhere in both apps.
    - One shared helper replaces four copies.
    - The chip row shows the week's locked chip.
    - No-pass managers no longer see last week's team after reopening.
    - *If wrong:* a slightly bigger pre-deploy change, all covered by the full test runs.
24. **One home-banner line is left for your words.**
    - Between the deadline and kickoff it still says "Fantasy is live — set your squad". It gets replaced by the live line at kickoff.
    - *If wrong:* that line shows for an hour or so before games.
    - **Done 2026-11-04 with your wording.** On match day after the deadline it says "GW2 locked · games today". I also fixed two more times it wrongly said "set your squad":
      - The next morning, until the next week opens at 3 PM, it says plain "GW2 locked", the same as My Team.
      - When you lock the league by hand, it says "Squads locked by the league".
    - *If wrong:* one word change.
    - **Final line added 2026-11-04 (your OK).**
      - Once the week's points are final, the banner shows your result instead, for example "GW2 final · 34 pts · #5". It's the same numbers as My Team, and it stays until the next week opens on Monday at 3 PM.
      - A voided week or a team that didn't count keeps "GW2 locked"; My Team explains why.
      - Fans with no team see "GW2 locked".
