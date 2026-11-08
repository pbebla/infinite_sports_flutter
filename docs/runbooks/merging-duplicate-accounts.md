# Merging duplicate player accounts - owner runbook

Last checked against the merge tool: 2026-11-08 (fan repo, branch `zaya-fantasy`).

You can run every command below yourself, or tell Claude "run step N" and Claude runs it. Either way the order and your OKs apply. As of 2026-11-08 only the read-only checks (the dry run and the duplicate check) have been run against the live app. Nothing has been changed yet.

## What this does

Some players signed up twice, so their seasons are split across two accounts. The merge tool:

1. Moves every season onto one account (the **kept** account).
2. Marks the other account (the **old** account) as "merged", so it disappears from player search.
3. Tells the player which email to use from now on (email, push, and an in-app message).
4. Last, switches off the old email's login so nobody recreates the duplicate by accident.

It never deletes an account. Sign-ups and payment history, game votes, predictions, event RSVPs and profile photo files stay where they are, on the old account.

This batch is 10 people:

- 8 have a second account. Robert Tatari has three old accounts, so there are 10 old accounts in total.
- 2 have no second account, only a roster entry typed with a different spelling: Roben Tatari ("Robben Tatari", Season 10) and Robert Shamoeilzadeh ("Robert Shamoelzadeh", Season 10). Those rows get linked to their real account. Robert Shamoeilzadeh's first name is currently spelled "Rabert"; the tool fixes it to "Robert".

## Open question for you

The 2026-11-07 duplicate check found one more likely duplicate that is **not** part of these 10: **Parlevino Tamraz**. His roster entries (S12 Nineveh, S13 Hakkari, S14 Nimrod, S15 Ishtar) are on one account, and his Season 16 sign-up is on another.

The tool won't merge him at all while any of his seasons has fantasy set up (Season 15 does, it is the test season). It refuses the whole person, not just that one season. So merging him needs a decision from you:

- Which of his two accounts should be kept?
- Should the tool be extended to handle Season 15, or should he wait until the Season 15 test data is cleared?

Until you decide, he stays as two accounts. Nothing breaks today, but decide him before you build Season 16 rosters (step 7), or his Season 16 sign-up lands on the other account. Ask Claude when you are ready.

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
| 3 | Apply: merge the 10 people | Yes |
| 4 | Check 2 or 3 profiles on your phone | - |
| 5 | Send the notices (emails and push) | Yes |
| 6 | Switch off the old logins | Yes |
| 7 | Before building Season 16 rosters: check for new duplicates | No |

Do the steps in this order. Step 6 must come after step 5, so nobody is locked out before they were told which email to use.

## Step 1: Get ready

1. **Do your final review** of the work on the `zaya-fantasy` branch (both repos).
2. **Deploy the two functions.** One changes player search so merged accounts drop out of it (`onUserWritten`). The other sends the "accounts combined" emails (`onMergeNoticeCreated`).

```bash
npx firebase-tools deploy --only functions:onUserWritten,functions:onMergeNoticeCreated --project infinite-sports-app
```

   It should end with "Deploy complete!". If it asks a question you don't understand, stop and ask Claude.

3. **Ship the app updates** the way you normally release:
   - **Fan app:** shows a "Your accounts were combined" message to anyone still signed in on an old account, then signs them out.
   - **Manager app:** hides merged accounts everywhere you pick a person (link player, assign trophy, tournament rosters, notifications, Fantasy access) and on the Users page.

**Recommendation: wait until the app updates are out before step 3.** Until the fan app update is on phones, someone signed in on an old account sees no message. Their account just quietly vanishes from search. If you decide to go earlier, the email in step 5 still reaches people who never open the app.

**Undo:** the deploy is safe to leave in place. It does nothing until accounts are merged. This tool does not undo app releases. If you need to take an app update back, roll it back through your usual release process.

## Step 2: Dry run (look, don't touch)

```bash
npm run merge:accounts
```

It reads the live data, prints what it would do, and writes nothing. Read the printout. What you want to see:

- `read: 20 accounts (0 with no Users node)`. All the accounts in the list exist.
- `kept-email hints found (masked, not shown): 10 of 10`. If a number is lower, that person's email would say "your other email" instead of showing a partly hidden address. Not harmful, but tell Claude.
- `data this tool does not move (...): checked on the old accounts, 1 fantasy season(s) and 1 registration form(s) (keys only)`. The tool looks (keys only, never the contents) for things on an old account that it does **not** move: Awards, tournaments played, a fantasy manager entry, a registration sign-up. A person who has any of them is **refused** (you would see it under `refusals`), because the merge would leave that behind on an account nobody uses. The 10 people in this batch have none. If someone is refused for this reason, don't go on: tell Claude, the item has to be moved by hand first.
- `public profiles: 10 of 10 old account(s) have a public profile entry right now`. This is how many of the old accounts are in player search today. The safety check in step 3 (the canary) watches one of them leave. If it says `0 of 10`, the canary has nothing to watch and is skipped (a boxed warning shows at apply). Tell Claude before you apply.
- A plan section, with lines per person such as "relink Futsal Season 11, Nineveh, ..." (a roster row moves to the kept account), "add Futsal Season 11 (Nineveh) to seasons played", "copy the profile photo link from an old account", "stamp 1 old account(s) as merged". Check the names and seasons against what you expect.
- `refusals: none`.
- `clusters: 10 in the map - 10 planned, 0 refused, 0 with nothing to do`. In the tool's words a "cluster" is one person.
- `writes: 69 (...)`. On 2026-11-07 this was 20 roster relinks, 16 seasons-played entries, 2 profile photo links, 30 merge stamps (10 old accounts times 3) and 1 first-name fix.
- A **plan code** (the tool calls it the plan digest): `plan digest (MergedAt time excluded): ...`. The 2026-11-07 dry run gave `6b49644c86689a2a`, and the 2026-11-08 dry run gave the same code. The code changes if the data or the list changes, so always use the one your latest dry run prints.
- The last line starts with "To apply exactly this plan:" and then gives the apply command, already filled in with the right plan code. In step 3 you copy only the `npm run ...` part after the colon.

If the dry run shows a refusal, a different count than you expect, or an error: stop and send the printout to Claude. Don't go on.

**Undo:** nothing to undo.

## Step 3: Apply (the real merge)

Only after you have read the dry run and said OK (and, as recommended, after the app updates are out).

From the last line of your latest dry run, copy only the `npm run ...` part (not the words "To apply exactly this plan:"). With the 2026-11-07 plan code it is:

```bash
npm run merge:accounts -- --apply --expect-plan 6b49644c86689a2a
```

If your dry run printed a different code, use that one. A wrong or stale code is simply refused and nothing changes.

What happens:

1. It re-reads everything and checks the plan is exactly the one you read.
2. It saves a **backup** of every spot it will change, in `functions/tools/rehearsal_out/merge_backup_<date and time>.json`. **Keep this file.** It is what undo needs. Don't delete or share it.
3. **Safety check on the first person (the "canary").** It merges one person first, then waits **up to 90 seconds** (it moves on as soon as it sees them gone) for that person's old account to disappear from player search. This proves the deployed function from step 1 really works. It tells you who goes first, and when the check passes it prints `canary passed: the old account left PublicProfiles`. ("PublicProfiles" is the player search list.)
4. Then it merges the other 9, printing a `wrote ...` line for every change. For each old account the "merged" marker is written last, after the partly hidden email and the time, so a crash can never leave an account half-marked.
5. It ends with `DONE - 69 writes for 10 cluster(s).` and a line starting `Undo:`. **Copy that Undo line somewhere safe.**

You can run `--apply` again later; people already merged are skipped and nothing is written twice. A re-run needs a **fresh dry run first** and the **new plan code** that dry run prints: after a partly finished apply the plan is different, so the old code is refused. Each apply run saves its **own** backup file.

If something goes wrong:

- **`CANARY FAILED ... STOPPED before any other cluster`.** The player-search function wasn't doing its job (usually the step 1 deploy didn't happen). Only the first person was merged. Run the `Undo:` line it printed, redo the deploy in step 1, run the dry run again, and apply again with the new plan code.
- **`STOPPED by an error after the backup was written`.** Run the `Undo:` line it printed, then send Claude the error text.
- **`REFUSED at apply - changed since the plan`** for a person: someone edited that person's roster or profile (for example in the Manager) between your dry run and now. That person was skipped and everyone else went through. Run the dry run again, read it, and apply again with the new plan code. It does only what is left.
- **`Refusing --apply: the plan digest is ... not the ... you expected`.** The data changed since your dry run. Nothing was written. Run the dry run again, read it, and use the new code.
- **A boxed `WARNING: THE MIRROR CHECK (CANARY) IS SKIPPED`.** Expected only when you re-run after a partly finished apply. On a first run, tell Claude.

**Undo this step** (puts everything back and returns the old accounts to player search within a minute or so). The apply printed a ready-to-copy `Undo:` line with the full backup path. It looks like this (put your backup's file name where it says so):

```bash
npm run merge:accounts -- --undo "tools/rehearsal_out/<your merge_backup_ file name>.json"
```

**If the merge took more than one apply run** (for example the first run stopped on a canary failure or skipped a person, and you applied again), each run saved its own backup. To undo everything, run the undo for **every** run's backup file, **newest first**, then the older ones. Use only files that start with `merge_backup_`, not the `fill_backup_` files in the same folder. The undo only puts back things nobody has touched since. If it prints `LEFT ALONE (changed since the merge)` for something, someone edited it after the merge; the tool refused to overwrite it. Ask Claude.

If you already did step 6, also switch the old logins back on (see step 6 undo). Either order works.

## Step 4: Check on your phone

Before sending anything to players, check 2 or 3 people. Good ones:

- **Hiram Alvarez**: Futsal Seasons 9, 10, 11 and 14 now on one account, and his profile photo.
- **Robert Tatari**: the one with three old accounts. Seasons 11 to 14 on one account.
- **Robert Shamoeilzadeh**: his first name now reads "Robert", not "Rabert".

For each, in the fan app:

1. Search the name in the app's search. Only **one** account should show. If an old one still shows, close the app fully, reopen it and search again.
2. Open the profile. **Every season** should show.
3. Optional: in the Manager app, first **close it fully and reopen it** (it keeps its list of accounts until it is reopened), then pick the person somewhere (for example link a player). Only one account should be offered.

If anything looks wrong, undo (step 3's undo) and tell Claude. Don't go on to step 5.

## Step 5: Tell the players (emails and push)

Only after your OK. **This sends email and push messages to real people and can't be un-sent.**

First the preview. It writes nothing:

```bash
npm run merge:accounts -- --notify
```

You should see 10 notices to write and `push to 8 kept account(s), one campaign each: 8 to write, 0 already there`, ending with `PREVIEW - nothing was written. 10 email(s) and 8 push campaign(s) would go out.` If it says `Refusing --notify ... not stamped yet`, step 3 isn't finished.

Before you send, make sure someone will check the support mailbox over the next few days. The emails come from the support mailer address, so replies to them land there.

When you are happy, send:

```bash
npm run merge:accounts -- --notify --send
```

What goes out:

- **An email to each of the 10 old addresses.** Subject: "Your Infinite Sports accounts were combined". It says all their seasons now show on one profile and to sign in with the kept address from now on. The kept address is shown partly hidden: the first two letters, then dots, then the email provider (shaped like `xx` + dots + `@gmail.com`).
- **One push to each of the 8 kept accounts** (8 pushes, one campaign per kept account): "Your accounts were combined" / "All your seasons are now on this profile." They also show in the Manager's campaign list, 8 rows.

Then check that the emails went. In the Firebase console, open the Realtime Database, then the `MergeNotices` entry. Each old account should show `Status: sent` within a minute or two. `no-email` means that account has no email address, `failed` means the mailer failed, and `sending` stuck for a long time means a send was interrupted. Tell Claude about any of those. Don't re-run on your own.

Running `--notify --send` again writes nothing and sends nothing twice. If you later add one more person to the list and run `--notify --send` again, only that person's email and push go out (the preview tells you the counts first). Everyone already told is left alone.

**Undo:** emails and push messages can't be recalled. Everything else in the system can still be undone. If you undo step 3 after sending, the people were told something that is no longer true, so ask Claude how to follow up.

## Step 6: Switch off the old logins

Only after your OK, and **after step 5's emails have gone out**. Your call how long to leave a gap between them. The longer it is, the more people read the email first.

Without this step, anyone who signs in with an old email recreates the duplicate account.

Preview first. It changes nothing:

```bash
npm run merge:accounts -- --disable-old-logins
```

It lists the 10 old logins that would be switched off, and a line `notices: 10 of 10 old account(s) have a settled notice`. If it says `Refusing`, step 3 isn't finished.

**`--send` waits for the emails.** It refuses (and changes nothing) unless every old account's notice shows `sent` or `no-email` in the `MergeNotices` entry, so nobody is locked out before they were told which email to use. If it says some accounts "have not been told yet", go back to step 5 and wait until each shows `Status: sent`. Only if you decide to go ahead anyway, add `--skip-notice-check` to the `--send` command; it prints a loud warning when you do.

Then do it:

```bash
npm run merge:accounts -- --disable-old-logins --send
```

You should see `DONE - 10 old login(s) disabled.` If it says `INCOMPLETE`, run the same command again. It is safe to repeat.

**Undo this step** (switch the old logins back on). Works before or after an `--undo` of step 3. Preview, then do it:

```bash
npm run merge:accounts -- --enable-old-logins
```

```bash
npm run merge:accounts -- --enable-old-logins --send
```

## Step 7: Before building Season 16 rosters from sign-ups

Run this **before** you build the Season 16 rosters from sign-ups, and merge any new duplicate first. Otherwise a duplicate gets baked into the new roster. It only looks:

```bash
npm run merge:accounts -- --find-dupes Futsal-16
```

("Futsal-16" is the Season 16 registration.) It only matches **exact names**: first plus last name on the account against the roster name. A spelling variant ("Robben" for "Roben", an extra letter, a nickname) is not found, so it still needs a manual look at the rosters. Each candidate line is a sign-up whose name matches a roster player from earlier seasons:

- **"already linked to another account"**: that roster row belongs to a different account than the sign-up. Likely a duplicate person. This is how Parlevino Tamraz showed up.
- **"unlinked row"**: a roster name with no account behind it. Often it is just an old roster entry nobody linked. Check whether it is the same person, then link the row in the Manager.

The first run listed Carlo Gewargis too. He is already in this batch and drops off the list once step 3 is done.

To merge a new duplicate, ask Claude to add that person to the list. Then repeat steps 2 to 6. The 10 people already done show as "already merged - nothing to do", and only the new person is touched.

**Undo:** nothing to undo.

## What players will notice

- **Everyone merged:** one profile in search, with every season on it.
- **Someone signed in on an old account, with the new fan app:** a message "Your accounts were combined". It says which email to use (partly hidden). They tap OK and get signed out.
- **Same person on an older fan app:** no message. Their old account just disappears from search. That is why step 1 recommends waiting for the app release.
- **After step 5:** the email at the old address and the push on the kept account.
- **After step 6:** signing in with the old email fails with the normal wrong-password message ("Username or password is incorrect. Try again."). The email told them which address to use. There is no special message for this case yet. Ask Claude if you want one.
- **Sign-ups and payment history** stay on the old account. Nothing about payments changes.

## If you see a message not covered here

Copy the whole printout and send it to Claude. The tool cuts account IDs to 6 characters and is built not to print emails or tokens, so it is safe to paste.
