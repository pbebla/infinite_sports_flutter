# Decisions made while building "season setup + schedule changes" (2026-11-05)

These are the decisions I (Opus) made on your behalf while building this plan, each with what it costs if it turns out wrong. A reviewer checked each one, and the final Fable-level review agreed with all of them except the two marked "changed". Tell me any you want different.

## How a new season starts

1. **The season pass is pre-filled from last season in the Start screen.** You can edit the price and payment methods before starting. Cash is never copied, because it's Manager-only. (Fable S1)
   - *If wrong:* nothing — it's editable.
2. **Start needs the season's teams and schedule first.** Week 1's deadline comes from the schedule.
   - *If wrong:* you wait for the schedule before starting.
3. **Returning players are matched season by season, newest first.** Each season is checked by account link first, then by name. A same-name player linked to a different account is treated as a different person. (T6c)
   - *If wrong:* a rare namesake mix-up. The preview shows which season each price came from, so you can catch it.
4. **A custom paywall message isn't carried over.** The default wording applies to a new season. (T6a)
   - *If wrong:* you retype your custom message once per season.
5. **A Start that crashed half-way is cleaned up.** If one died more than 10 minutes ago and left no season behind, the next Start takes over. You never get stuck on "already started". (changed by the final review, T6b)
   - *If wrong:* nothing.
6. **The Start card shows on every Fantasy page whenever the current season has no fantasy yet.** That includes a sport whose current season you may never run fantasy for. (T13a)
   - *If wrong:* a card you don't need. Tell me and I'll hide it per sport.
7. **The Start page never hides a broken server answer.** A garbled reply about the season pass, or an empty player list, shows "check again" instead of a quiet free season. The confirm box no longer says fans can start right away, because with a pass they pay first. (T13b, T13c)
   - *If wrong:* nothing.

## Players who join mid-season

8. **Joiners pay the average price for their position, even if they played before.** That's your rule. Their old position still carries over. (plan ruling)
   - *If wrong:* a returning star is cheap for one season.
9. **If the automatic add fails once, it isn't retried by itself.** The player shows up on the next roster change, or you'll spot them missing on the Players page. (F2)
   - *If wrong:* a joiner is missing for a while, so tell me if you see it.
10. **Fixing a linked player's name typo leaves their old market entry.** It's out of scope for this build. (Task 7)
    - *If wrong:* that player scores nothing until I rename their market entry.

## Deadlines and cancelled days

11. **A deadline can't be set before game day.** It can only be moved within game day, up to the first kickoff. If it were set a day early, teams would reopen 24 hours later, while that week's games were still on. (T9a)
    - *If wrong:* you skip the day instead.
12. **A deadline can't move once a game of that day has started**, and moving it later never reopens teams after kickoff. (Fable M1)
    - *If wrong:* nothing; you skip the day instead if it truly must reopen.
13. **"Called off" is handled only by the 15-minute engine pass.** The reopen and the alert can take up to 15 minutes. Changing a deadline for an open week reaches fans right away. (Fable M2)
    - *If wrong:* up to 15 minutes' delay.
14. **A cancelled week also clears a Void you'd set on it**, so the next game day that takes its number isn't zeroed. (T4b)
    - *If wrong:* you re-void the reopened week if you really wanted it voided.
15. **Two cancelled weeks in a row still give everyone their exact money back.** The engine keeps up to 8 levels of saved money. (T4c)
    - *If wrong:* only after 9 cancelled weeks in a row.
16. **A skipped day never scores, even if its games were finished.** (changed by the final review, I2)
    - *If wrong:* nothing.
17. **"Bring back" is blocked once any game of that day has started.** Bringing back a day you skipped by mistake, after its games started, can't be done in the app — ask me. (R3)
    - *If wrong:* one manual fix.
18. **"Back to automatic" warns when the automatic deadline has already passed**, because the week will lock right away. It's blocked once games have started. (final review I3)
    - *If wrong:* nothing.
19. **Adding a game to an old day** warns that it won't count in fantasy, or that it will lock at once if the day is newer than the last locked week. (T12a, I3)
    - *If wrong:* wording.
20. **One rare schedule edit shows the wrong warning:** moving a locked week's last game to an *earlier* past day says "won't count", but that day actually becomes the reopened week. (R2)
    - *If wrong:* misleading text in a rare edit; the fix is noted for later.
21. **A schedule screen that can't check fantasy says so.** It shows "Couldn't check fantasy for this day" rather than staying silent. A sport with no fantasy shows nothing. (T10b, T12b, T12c)
    - *If wrong:* an extra line now and then.

## Prices after each game day

22. **Prices move the morning after each game day, with hourly tries from 10 AM to 3 PM.** One glitch no longer skips a week. (changed by the final review, I5)
    - *If wrong:* nothing.
23. **A day whose deadline is at or before 10 AM isn't repriced automatically** (morning games). Repricing would land after teams reopen. Sunday-evening futsal isn't affected. (T5a, R4)
    - *If wrong:* you set prices by hand for morning-game weeks. Tell me if you play mornings.

## Behind the scenes (safety plumbing, no visible effect)

24. **The engine saves each manager's money before every lock and puts it back exactly on a cancel.** A cancel marks the week before touching anything. Every lock write double-checks the week, and a cleanup step fixes anything an overlapping run leaves behind. (T3a, T3b, T3c, T3d, T4a, T4d, T4e)
25. **Scoring and cancelling can't run on the same week at the same time.** A scoring run that finds the week being cancelled, or re-dated, stands down. (final review I1, I4)
    - *If wrong:* one ultra-rare three-way overlap could still count a cancelled day. You'd Void it. (R1)
26. **Small technical choices.** A shared settings type lives with the engine. Friendly games count toward the first kickoff, since an earlier lock never leaks picks. Several test values were corrected before building. The clock-change day shows the right weekday. A Manager page shows "Couldn't load the schedule — try again" with Retry. Copy and labels were tidied ("Save deadline", "Skip week", the lock-hour sentence). (P1–P5, T1a, T9b, T10a, T11b, T11c, F1)
    - *If wrong:* wording only.
