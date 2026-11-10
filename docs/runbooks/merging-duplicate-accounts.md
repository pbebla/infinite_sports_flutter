# Merging duplicate player accounts - owner runbook

Last checked against the merge tool: 2026-11-08 (fan repo, branch `zaya-fantasy`), after it learned to handle Parlevino Tamraz and to move old sign-up records, and after its undo learned to refuse once the Season 15 test data has been cleared.

You can run every command below yourself, or tell Claude "run step N" and Claude runs it. Either way the order and your OKs apply. As of 2026-11-08 only the read-only checks (the dry run for all 11 people, and the duplicate check) have been run against the live app. Nothing has been changed yet.

## What this does

Some players signed up twice, so their seasons are split across two accounts. The merge tool:

1. Moves every season onto one account (the **kept** account).
2. Moves each player's old **sign-up records** (paid or unpaid; today's are all Seasons 9 to 15 in the Manager's sign-up lists) to the kept account too. Each record is copied to the kept account first, and only then removed from the old one. Undo puts them back exactly - except after the Season 15 test data has been cleared: then the tool refuses to undo and you tell Claude.
3. Marks the other account (the **old** account) as "merged", so it disappears from player search.
4. Tells the player which email to use from now on (email, push, and an in-app message).
5. Last, switches off the old email's login so nobody recreates the duplicate by accident.

It never deletes an account. The only thing it ever removes is an old account's sign-up record, and only after the identical copy is on the kept account. If a sign-up record changed in the moments before the removal, the tool stops that person right there (see step 3) and carries on with the others. The notes and due/info entries kept next to the sign-up lists are not touched. Game votes, predictions, event RSVPs and profile photo files stay where they are, on the old account.

This batch is 11 people:

- 9 have a second account (Parlevino Tamraz, below, is one of the 9). Robert Tatari has three old accounts, so there are 11 old accounts in total.
- 2 have no second account, only a roster entry typed with a different spelling: Roben Tatari ("Robben Tatari", Season 10) and Robert Shamoeilzadeh ("Robert Shamoelzadeh", Season 10). Those rows get linked to their real account. Robert Shamoeilzadeh's first name is currently spelled "Rabert"; the tool fixes it to "Robert".
- **Parlevino Tamraz** is one of the 9 with a second account, and the newest one. The kept account is his Season 16 account (the Gmail one). The old account is his iCloud account, which holds his roster entries for Seasons 12 to 15 (Nineveh, Hakkari, Nimrod, Ishtar) and his old sign-up records for those four seasons (all paid). His Season 15 row is in the Season 15 fantasy **test** season. The tool only moves a row in a fantasy season while that season's test data is still there, which is why the order rule below matters.

## The order rule: merge first

> **Run the merge (step 3, the apply) BEFORE any of these three Season 16 jobs:**
>
> 1. Clearing the Season 15 test fantasy data (`npm run fill:s15 -- --clear ...`).
> 2. Applying the Season 16 player prices.
> 3. Building Season 16 rosters from sign-ups.
>
> **The check before you start any of the three:** run a fresh dry run (the plain `npm run merge:accounts` from step 2) and look for Parlevino Tamraz's line. It must say `Parlevino Tamraz: already merged - nothing to do`. If he is refused, or his line is missing, stop and tell Claude. Do not put the test data back.
>
> **Why:** Parlevino's Season 15 move is only allowed while the Season 15 test data is still there. If the test data was cleared first, the tool **refuses him** (the whole person, not just that season) and writes nothing for him.
>
> **Two more things that follow from it:**
>
> - **Do the step 4 phone check BEFORE clearing the Season 15 test data.** The tool can only undo the merge while that test data is still there. After it has been cleared, an undo is refused (see "Undo this step" in step 3) and you tell Claude.
> - **This order rule wins over waiting for the app updates.** If the Season 16 deadline needs the merge now, apply early, without waiting for the app updates. The step 5 email still reaches the people who don't have the app update yet.

Only step 3 (the apply) has to come first. The notices and the login switch (steps 5 and 6) can go on their own schedule. Step 7 is the Season 16 order in full.

## Before you start (once)

Open Git Bash and go to the functions folder. Every command in this runbook runs from there.

```bash
cd /c/Users/zayaa/StudioProjects/infinite_sports_flutter/functions
```

Things to know:

- Copy commands exactly. The two dashes before a flag (`npm run merge:accounts -- --apply`) are required.
- Every time you run a command it first spends a few seconds building the tool. That is normal. If it says `tsc` is not recognized, run `npm install` once in this folder and try again.
- If a command says there is no Firebase login, log in once and run it again:

```bash
npx firebase-tools login
```

- The list of who merges into whom is a file Claude wrote: `functions/tools/rehearsal_out/merge_map.json`. It holds account IDs (no emails). Don't share it and don't commit it.
- These commands only look and never change anything: the plain `npm run merge:accounts` (the dry run), `--find-dupes`, `--notify` without `--send`, and `--disable-old-logins` or `--enable-old-logins` without `--send`.
- These change things: `--apply`, `--undo`, `--notify --send`, `--disable-old-logins --send`, `--enable-old-logins --send`.
- The tool is built not to print emails or full account IDs (it cuts IDs to 6 characters), so you can paste any printout to Claude.

## The order, at a glance

| Step | What | Needs your OK first |
|---|---|---|
| 1 | Final review, deploy the two functions, ship the app updates | Yes (your final review) |
| 2 | Dry run: read the list | No (changes nothing) |
| 3 | Apply: merge the 11 people (before any Season 16 job) | Yes |
| 4 | Check 2 or 3 profiles on your phone | - |
| 5 | Send the notices (emails and push) | Yes |
| 6 | Switch off the old logins | Yes |
| 7 | Season 16 jobs: check for new duplicates before building rosters (after step 3) | No |

Do the steps in this order. Step 6 must come after step 5, so nobody is locked out before they were told which email to use. Step 3 must come before clearing the Season 15 test data, applying the Season 16 prices, or building Season 16 rosters, and a fresh dry run must show Parlevino as "already merged - nothing to do" before you start any of them (see the order rule above). Do the step 4 phone check before you clear the Season 15 test data too, because the tool cannot undo the merge after that. If the Season 16 deadline needs the merge, apply before the app updates are out: the order rule wins.

## Step 1: Get ready

1. **Do your final review** of the work on the `zaya-fantasy` branch (both repos). Don't clear the Season 15 test data, apply the Season 16 prices or build Season 16 rosters until step 3 is done and a fresh dry run shows Parlevino as "already merged - nothing to do" (the order rule above).
2. **Deploy the two functions.** One changes player search so merged accounts drop out of it (`onUserWritten`). The other sends the "accounts combined" emails (`onMergeNoticeCreated`).

```bash
npx firebase-tools deploy --only functions:onUserWritten,functions:onMergeNoticeCreated --project infinite-sports-app
```

   It should end with "Deploy complete!". If it asks a question you don't understand, stop and ask Claude.

3. **Ship the app updates** the way you normally release:
   - **Fan app:** shows a "Your accounts were combined" message to anyone still signed in on an old account, then signs them out.
   - **Manager app:** hides merged accounts everywhere you pick a person (link player, assign trophy, tournament rosters, notifications, Fantasy access) and on the Users page.

**Nice to have, but the order rule wins: it is better to have the app updates out before step 3, yet do not hold step 3 back for them if a Season 16 job needs the merge first.** Apply early if the Season 16 deadline needs it. Until the fan app update is on phones, someone signed in on an old account sees no message. Their account just quietly vanishes from search. The email in step 5 still reaches people who never open the app or don't have the update.

**Undo:** the deploy is safe to leave in place. It does nothing until accounts are merged. This tool does not undo app releases. If you need to take an app update back, roll it back through your usual release process.

## Step 2: Dry run (look, don't touch)

```bash
npm run merge:accounts
```

It reads the live data, prints what it would do, and writes nothing. Read the printout. What you want to see:

- `read: 22 accounts (0 with no Users node)`. All the accounts in the list exist.
- `kept-email hints found (masked, not shown): 11 of 11`. If a number is lower, that person's email would say "your other email" instead of showing a partly hidden address. Not harmful, but tell Claude.
- `sign-ups: 12 league season(s) listed ...`. The tool lists the sign-up seasons and reads only the records of the people in the list. It never reads the comments or the amounts due. (The number of seasons is whatever is in the live data.)
- `fantasy test-season check: 1 relinked season(s) have a fantasy Config - a relink there is allowed only when its TestFill marker exists`. This is Parlevino's Season 15 row. It is allowed only because the Season 15 test data is still there (the "TestFill marker"). If the test data had been cleared, he would show up under `refusals` instead.
- `data this tool does not move (...): checked on the old accounts, 1 fantasy season(s) and 1 registration form(s) (keys only)`. The tool looks (keys only, never the contents) for things on an old account that it does **not** move: Awards, tournaments played, a fantasy manager entry, a registration sign-up. A person who has any of them is **refused** (you would see it under `refusals`), because the merge would leave that behind on an account nobody uses. The 11 people in this batch have none. If someone is refused for this reason, don't go on: tell Claude, the item has to be moved by hand first.
- `public profiles: 11 of 11 old account(s) have a public profile entry right now`. This is how many of the old accounts are in player search today. The safety check in step 3 (the canary) watches one of them leave. If it says `0 of 11`, the canary has nothing to watch and is skipped (a boxed warning shows at apply). Tell Claude before you apply.
- A plan section, with lines per person such as "relink Futsal Season 11, Nineveh, ..." (a roster row moves to the kept account), "add Futsal Season 11 (Nineveh) to seasons played", "move his Season 9 sign-up record (Futsal, Paid)" (a sign-up record moves to the kept account; the last word is Paid or NotPaid), "copy the profile photo link from an old account", "stamp 1 old account(s) as merged". Parlevino's Season 15 line ends "(fantasy test season - the market sync stands down)": that note is expected, and it is the one place the tool moves a row in a fantasy season. A line that says "finish moving" instead of "move" means a sign-up record was already copied and only the removal is left (this only happens after an interrupted run). Check the names and seasons against what you expect.
- `refusals: none`.
- `clusters: 11 in the map - 11 planned, 0 refused, 0 with nothing to do`. In the tool's words a "cluster" is one person.
- `writes: 115 (...)`. On 2026-11-08 this was 20 seasons-played entries, 2 profile photo links, 24 roster relinks, 17 sign-up copies, 17 sign-up removes (the sign-up records moving), 33 merge stamps (11 old accounts, 3 stamps each), 1 first-name fix and 1 information field (Parlevino's Age, copied to his kept account).
- A **plan code** (the tool calls it the plan digest): `plan digest (MergedAt time excluded): ...`. The latest dry run (2026-11-10, read-only) printed **`48135c9b50e5e401`** for these 11 people (0 refused, 126 changes, including one "combined from" link per old account so that deleting the kept account later also deletes the old ones). The code changes if the data or the list changes, so always use the one your latest dry run prints. A code from an older run (for example `bd98b0592255a300` from before the combined-from link, or from when the list had 10 people) is refused.
- The last line starts with "To apply exactly this plan:" and then gives the apply command, already filled in with the right plan code. In step 3 you copy only the `npm run ...` part after the colon.

If the dry run shows a refusal, a different count than you expect, or an error: stop and send the printout to Claude. Don't go on.

**Undo:** nothing to undo.

## Step 3: Apply (the real merge)

Only after you have read the dry run and said OK. It is better if the app updates are out first, but the order rule wins: apply early if the Season 16 deadline needs it. This step has to come before clearing the Season 15 test data, applying the Season 16 prices or building Season 16 rosters, and a fresh dry run afterwards has to show Parlevino as "already merged - nothing to do" (the order rule above).

From the last line of your latest dry run, copy only the `npm run ...` part (not the words "To apply exactly this plan:"). With the plan code of the 2026-11-08 dry run it is:

```bash
npm run merge:accounts -- --apply --expect-plan 48135c9b50e5e401
```

If your dry run printed a different code, use that one. A wrong or stale code is simply refused and nothing changes.

What happens:

1. It re-reads everything and checks the plan is exactly the one you read.
2. It saves a **backup** of every spot it will change, in `functions/tools/rehearsal_out/merge_backup_<date and time>.json`. **Keep this file.** It is what undo needs. Don't delete or share it.
3. **Safety check on the first person (the "canary").** It merges one person first, then waits **up to 90 seconds** (it moves on as soon as it sees them gone) for that person's old account to disappear from player search. This proves the deployed function from step 1 really works. It tells you who goes first, and when the check passes it prints `canary passed: the old account left PublicProfiles`. ("PublicProfiles" is the player search list.)
4. Then it merges the other 10, printing a `wrote ...` line for every change and a `removed ...` line for every old sign-up record it takes off an old account. For each person it goes in a safe order: seasons played and profile bits, roster links, then the sign-up copies on the kept account, then the sign-up removals from the old account, and last the "merged" marker (after the partly hidden email and the time), so a crash can never leave an account half-marked. Just before each sign-up removal it checks again that the old record and its copy are both still as expected.
5. It ends with `DONE - 115 writes for 11 cluster(s).` and a line starting `Undo:`. **Copy that Undo line somewhere safe.**

You can run `--apply` again later; people already merged are skipped and nothing is written twice. A re-run needs a **fresh dry run first** and the **new plan code** that dry run prints: after a partly finished apply the plan is different, so the old code is refused. Each apply run saves its **own** backup file.

If something goes wrong:

- **`CANARY FAILED ... STOPPED before any other cluster`.** The player-search function wasn't doing its job (usually the step 1 deploy didn't happen). Only the first person was merged. Run the `Undo:` line it printed, redo the deploy in step 1, run the dry run again, and apply again with the new plan code.
- **`STOPPED by an error after the backup was written`.** Run the `Undo:` line it printed, then send Claude the error text.
- **`REFUSED at apply - changed since the plan`** for a person: someone edited that person's roster, profile or a sign-up record (for example in the Manager) between your dry run and now. That person was skipped and everyone else went through. Run the dry run again, read it, and apply again with the new plan code. It does only what is left. If the reason says **`the fantasy test-season marker is gone`**, the Season 15 test data was cleared while the tool was running. That is what the order rule is for: nothing was written for that person. Don't put the test data back yourself, tell Claude.
- **`STOPPED before a sign-up remove - changed since the cluster was checked`** for a person: a sign-up record changed in the moments before the tool was going to remove it from the old account. The tool did not remove it, wrote nothing more for that person (no "merged" stamp, so they are still in player search) and carried on with the others. The run ends with a failure line (`N cluster(s) STOPPED before a sign-up remove`) and the `Undo:` line. **If a person is STOPPED: first undo THIS run** with the `Undo:` command it printed (see "Undo this step" below; it takes back the whole run, not just that person). **Then run a fresh dry run. If it lists that person under `refusals`, stop and tell Claude. If that person's sign-up lines say "move" or "finish moving", apply again with the new plan code.** Don't skip the undo: if you re-run first and undo the stopped run later, the undo refuses and changes nothing, so that no sign-up record is lost. It prints `Refusing --undo: This run was finished by a later run. Undo that later run's backup first, then undo this one.` The same refusal also appears if a later run finished that person's move, or if its old record was removed by hand after the stop. If you see that, undo the newer run's backup first (the `merge_backup_` file with the later time in its name), then this one. If there is no newer `merge_backup_` file, tell Claude.
- **`Refusing --apply: the plan digest is ... not the ... you expected`.** The data changed since your dry run (for example the Season 15 test data was cleared, which changes Parlevino's part of the plan). Nothing was written. Run the dry run again, read it, and use the new code. If the new dry run lists Parlevino under `refusals`, stop and tell Claude.
- **A boxed `WARNING: THE MIRROR CHECK (CANARY) IS SKIPPED`.** Expected only when you re-run after a partly finished apply. On a first run, tell Claude.

**Undo this step** (puts everything back, including each moved sign-up record back on its old account exactly as it was, and returns the old accounts to player search within a minute or so - except after the Season 15 test data has been cleared: then the tool refuses to undo and you tell Claude, see below). The apply printed a ready-to-copy `Undo:` line with the full backup path. It looks like this (put your backup's file name where it says so):

```bash
npm run merge:accounts -- --undo "tools/rehearsal_out/<your merge_backup_ file name>.json"
```

**If the merge took more than one apply run** (for example the first run stopped on a canary failure or skipped a person, and you applied again), each run saved its own backup. To undo everything, run the undo for **every** run's backup file, **newest first**, then the older ones. Use only files that start with `merge_backup_`, not the `fill_backup_` files in the same folder. The undo only puts back things nobody has touched since. If it prints `LEFT ALONE (changed since the merge)` for something, someone edited it after the merge; the tool refused to overwrite it. Ask Claude. A sign-up record whose old key was edited after the merge is left alone, and the copy on the kept account is left too (`LEFT ALONE ... (its old record changed since the merge)`), so the record is never lost. If an undo instead prints `Refusing --undo: This run was finished by a later run. Undo that later run's backup first, then undo this one.`, nothing was changed. That happens when a later run finished the move or its old record was removed by hand: undo the newer run's backup first, then this one again. If there is no newer `merge_backup_` file, tell Claude.

**One more refusal, and the reason for the step 4 timing.** The undo cannot be used after the Season 15 test data has been cleared. It prints `Refusing --undo: a season in this backup now has live fantasy (the Season 15 test data was cleared). Undoing would change a live fantasy roster. Tell Claude.` and then `Nothing was changed.`, followed by the person and season it is about. Putting Parlevino's old Season 15 row back on a live fantasy season would change a real fantasy roster, so the tool refuses the whole undo and writes nothing, for anyone. If you see it, tell Claude. Don't put the test data back yourself.

**A sign-up record that has moved since the merge.** If a person's sign-up record on the kept account was moved to the other status (Paid or NotPaid) after the merge, the undo leaves both of that person's records for that season alone and prints `LEFT ALONE ... (the kept account's record moved to NotPaid since the merge)` (or `Paid`). Tell Claude, so that nobody ends up with two records.

If you already did step 6, also switch the old logins back on (see step 6 undo). Either order works.

## Step 4: Check on your phone

Before sending anything to players, check 2 or 3 people. **Do this check before you clear the Season 15 test data too:** after that the tool cannot undo the merge (it refuses and you tell Claude), so it is the last easy moment to take everything back. Good ones:

- **Hiram Alvarez**: Futsal Seasons 9, 10, 11 and 14 now on one account, and his profile photo.
- **Robert Tatari**: the one with three old accounts. Seasons 11 to 14 on one account.
- **Robert Shamoeilzadeh**: his first name now reads "Robert", not "Rabert".
- **Parlevino Tamraz**: one account only, with Futsal Seasons 12, 13, 14 and 15 on it and his Season 16 sign-up.

For each, in the fan app:

1. Search the name in the app's search. Only **one** account should show. If an old one still shows, close the app fully, reopen it and search again.
2. Open the profile. **Every season** should show.
3. Optional: in the Manager app, first **close it fully and reopen it** (it keeps its list of accounts until it is reopened), then pick the person somewhere (for example link a player). Only one account should be offered.
If anything looks wrong, undo (step 3's undo) and tell Claude. Don't go on to step 5. (If the Season 15 test data was already cleared, the undo is refused: just tell Claude.)

## Step 5: Tell the players (emails and push)

Only after your OK. **This sends email and push messages to real people and can't be un-sent.**

First the preview. It writes nothing:

```bash
npm run merge:accounts -- --notify
```

You should see 11 notices to write and `push to 9 kept account(s), one campaign each: 9 to write, 0 already there`, ending with `PREVIEW - nothing was written. 11 email(s) and 9 push campaign(s) would go out.` If it says `Refusing --notify ... not stamped yet`, step 3 isn't finished.

Before you send, make sure someone will check the support mailbox over the next few days. The emails come from the support mailer address, so replies to them land there.

When you are happy, send:

```bash
npm run merge:accounts -- --notify --send
```

What goes out:

- **An email to each of the 11 old addresses.** Subject: "Your Infinite Sports accounts were combined". It says all their seasons now show on one profile and to sign in with the kept address from now on. The kept address is shown partly hidden: the first two letters, then dots, then the email provider (shaped like `xx` + dots + `@gmail.com`).
- **One push to each of the 9 kept accounts** (9 pushes, one campaign per kept account): "Your accounts were combined" / "All your seasons are now on this profile." They also show in the Manager's campaign list, 9 rows.

Then check that the emails went. In the Firebase console, open the Realtime Database, then the `MergeNotices` entry. Each old account should show `Status: sent` within a minute or two. `no-email` means that account has no email address, `failed` means the mailer failed, and `sending` stuck for a long time means a send was interrupted. Tell Claude about any of those. Don't re-run on your own.

Running `--notify --send` again writes nothing and sends nothing twice. If you later add one more person to the list and run `--notify --send` again, only that person's email and push go out (the preview tells you the counts first). Everyone already told is left alone.

**Undo:** emails and push messages can't be recalled. Everything else in the system can still be undone - except after the Season 15 test data has been cleared: then the tool refuses to undo step 3 and you tell Claude. If you undo step 3 after sending, the people were told something that is no longer true, so ask Claude how to follow up.

## Step 6: Switch off the old logins

Only after your OK, and **after step 5's emails have gone out**. Your call how long to leave a gap between them. The longer it is, the more people read the email first.

Without this step, anyone who signs in with an old email recreates the duplicate account.

Preview first. It changes nothing:

```bash
npm run merge:accounts -- --disable-old-logins
```

It lists the 11 old logins that would be switched off, and a line `notices: 11 of 11 old account(s) have a settled notice`. If it says `Refusing`, step 3 isn't finished.

**`--send` waits for the emails.** It refuses (and changes nothing) unless every old account's notice shows `sent` or `no-email` in the `MergeNotices` entry, so nobody is locked out before they were told which email to use. If it says some accounts "have not been told yet", go back to step 5 and wait until each shows `Status: sent`. Only if you decide to go ahead anyway, add `--skip-notice-check` to the `--send` command; it prints a loud warning when you do.

Then do it:

```bash
npm run merge:accounts -- --disable-old-logins --send
```

You should see `DONE - 11 old login(s) disabled.` If it says `INCOMPLETE`, run the same command again. It is safe to repeat.

**Undo this step** (switch the old logins back on). Works before or after an `--undo` of step 3. Preview, then do it:

```bash
npm run merge:accounts -- --enable-old-logins
```

```bash
npm run merge:accounts -- --enable-old-logins --send
```

## Step 7: The Season 16 jobs (merge first, then check for new duplicates)

This is the Season 16 order in full:

1. **Run the merge first** (step 3, the apply). It comes before every job below. In particular it comes **before** clearing the Season 15 test data (`npm run fill:s15 -- --clear ...`), because Parlevino's Season 15 move is only allowed while that test data is still there. If the test data was cleared first, the tool refuses him and writes nothing for him.
2. **Check that it worked.** Before you clear the Season 15 test data, apply the Season 16 prices or build Season 16 rosters, run a fresh dry run (step 2's command) and check that Parlevino Tamraz is listed as "already merged - nothing to do". If he is refused or missing, stop and tell Claude. Do not put the test data back. Also do the step 4 phone check now, before the test data goes: after it is cleared the tool cannot undo the merge.
3. **Check for new duplicates** (below), before you build the Season 16 rosters from sign-ups. Merge any new duplicate first, otherwise a duplicate gets baked into the new roster.
4. **Then** the Season 16 jobs: applying the player prices and building the rosters from sign-ups (and clearing the Season 15 test data, whenever you are ready to).

The duplicate check only looks:

```bash
npm run merge:accounts -- --find-dupes Futsal-16
```

("Futsal-16" is the Season 16 registration.) It only matches **exact names**: first plus last name on the account against the roster name. A spelling variant ("Robben" for "Roben", an extra letter, a nickname) is not found, so it still needs a manual look at the rosters. Each candidate line is a sign-up whose name matches a roster player from earlier seasons:

- **"already linked to another account"**: that roster row belongs to a different account than the sign-up. Likely a duplicate person.
- **"unlinked row"**: a roster name with no account behind it. Often it is just an old roster entry nobody linked. Check whether it is the same person, then link the row in the Manager.

The first run listed Carlo Gewargis and Parlevino Tamraz too. Both are in this batch and drop off the list once step 3 is done.

To merge a new duplicate, ask Claude to add that person to the list. Then repeat steps 2 to 6. The 11 people already done show as "already merged - nothing to do", and only the new person is touched.

**Undo:** nothing to undo.

## What players will notice

- **Everyone merged:** one profile in search, with every season on it.
- **Someone signed in on an old account, with the new fan app:** a message "Your accounts were combined". It says which email to use (partly hidden). They tap OK and get signed out.
- **Same person on an older fan app:** no message. Their old account just disappears from search. That is why it is better to have the app release out before step 3, unless the Season 16 deadline needs the merge first (the order rule wins).
- **After step 5:** the email at the old address and the push on the kept account.
- **After step 6:** signing in with the old email fails with the normal wrong-password message ("Username or password is incorrect. Try again."). The email told them which address to use. There is no special message for this case yet. Ask Claude if you want one.
- **Old sign-up records** (paid or unpaid; today's are all paid, Seasons 9 to 15) now sit under the kept account, with the same name and the same status. Nothing about payments changes. The notes and due/info entries beside the sign-up lists were not touched.
- **Profile details from the old account** (for example age or position) are copied only when the new account has none of its own, and they may be out of date. A player can fix them in their profile.

## If you see a message not covered here

Copy the whole printout and send it to Claude. The tool cuts account IDs to 6 characters and is built not to print emails or tokens, so it is safe to paste.
