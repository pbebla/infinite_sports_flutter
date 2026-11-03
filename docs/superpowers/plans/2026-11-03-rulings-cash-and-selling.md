# Decisions made while building "cash Manager-only" and "Premier League selling" (2026-11-03)

Every decision I (Opus) made on your behalf while the two plans were built, in the order I made them, with what it costs if it turns out wrong. Each was checked by a reviewer. Tell me any you want changed.

## Cash becomes Manager-only

1. **Removing the Cash switch moved one step earlier.** The data change and the screen change had to land together, or the Manager wouldn't build. *If wrong:* nothing.
2. **"Record cash" takes the season, the fan, the amount and, optionally, the pending request it answers.** *If wrong:* a rename.
3. **Your live cash test was handed to you at the end instead of holding up the build.** *If wrong:* one more round trip.
4. **Every money box got stricter, including the season price.** "5,50", "1e3" and "5.499" are refused; there's a $1,000 cap. The season price box used the same lenient reader, and that price becomes the card charge. *If wrong:* a typed "5,50" shows an error instead of quietly saving $550.
5. **A whole-change review ran before the deploy.** *If wrong:* nothing.
6. **The cash whole-change review ran on Opus; the selling one on Fable.** Cash was smaller and already checked task by task. *If wrong:* a slightly weaker last check on cash.
7. **No special code for an old "I paid cash" request.** I checked live data: none exist, and the new rules make new ones impossible. *If wrong:* one owner action on that one fan would show an error after it had actually worked.

## Premier League selling rule

8. **The save rule change left the "delete my team" rule exactly as it was.** *If wrong:* a team can still be deleted in the locked window, as today.
9. **Season 15's old weekly records weren't migrated.** Season 16 starts fresh. *If wrong:* a faked Season 15 test price could last one more week.
10. **No "better of two prices" sale credit** (as Fable advised). Instead, the over-budget warning covers price moves before the deadline. *If wrong:* a fan who ignores the push loses a week.
11. **Accepted a tiny cheat that needs a hacked app:** at most $0.2M per price step. *If wrong:* tiny made-up budget for a cheater.
12. **Closed a loophole:** deleting or breaking your team before a deadline no longer wipes a running loss. The running total carries over. *If wrong:* nothing; it only adds protection.
13. **Five small server cleanups were folded into the next step.** A $0 price counts as missing; one code constant moved; one comment fixed; argument order made consistent; one extra test. *If wrong:* nothing.
14. **The test-season rehearsal tool was updated to behave like the new app**, in the last step. *If wrong:* nothing.
15. **A late duplicate deadline snapshot is skipped** once the week's results exist. Otherwise it could undo a carried loss. *If wrong:* a week scored straight from live teams has no snapshot row; its results stand in, as they already do.
16. **No over-budget warning while you have extended a deadline.** The server pauses its deadline work then, and the warning's deadline would be wrong. *If wrong:* an over-budget team during your extension isn't warned.
17. **No extra push while another alert already shows.** That banner already says "fix it". *If wrong:* one missed push.
18. **Accepted a seconds-wide timing overlap** that can send one outdated warning. The banner corrects itself within 15 minutes. *If wrong:* one wrong push, rarely.
19. **The deadline transfer recount is saved**, so next week's free transfers come from the right count, and a log line is written when it finds missed transfers. *If wrong:* nothing.
20. **Saves reopen exactly 24 hours after a deadline**, matching the moment the app reopens. Without this, the first minutes of every Monday 3 PM would have refused saves and thrown away edits. *If wrong:* a hacked app can save during that 15-minute gap, still charged at the deadline.
21. **Small accuracy fixes:** a code comment was corrected and a rules test made exact. *If wrong:* nothing.
22. **During your deadline extension, the app uses the week the server last wrote.** Otherwise every fan's Save would be blocked during an extension. *If wrong:* during an extension the app can't notice a truly outdated baseline.
23. **The app now charges the same minimum price the server does for players not on last week's team.** This matters for someone whose previous week didn't count. *If wrong:* nothing; it's exact matching with the server.
24. **Small app safety fixes:** the budget isn't "ready" until prices load; two misuse checks; one test renamed. *If wrong:* nothing.
25. **Taking back a player you sold this week shows what you got for him**, because that's what it costs to undo the sale. The Rules tab says "the sale is undone". *If wrong:* a wording tweak.
26. **While the budget is still loading or updating, the bar shows "— left".** The "from sales" and "sells for" lines hide, Save waits, and the app says "still updating". It never shows a guessed number. *If wrong:* a brief "— left" on first open.
27. **Market rows keep showing a player's market price.** Only the Add button follows the real cost; the picker shows the exact cost. *If wrong:* a sold riser can read $9.0M while you have $8.5M left, yet still be addable.
28. **The last step was split.** The test tools and rehearsal were done and reviewed before anything deployed. *If wrong:* nothing.
29. **No extra fix round after the final review.** It said no code change is needed; its four important points are process items for you, listed in my message. Minor follow-ups are noted in the progress log. *If wrong:* a rare rough edge until a follow-up.
30. **I kept my two scratch progress folders instead of deleting them**, because you want to confirm any deletion. *If wrong:* two small hidden folders remain; say "delete them" and I will.
