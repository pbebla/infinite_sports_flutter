# Deleting an account

How account deletion works, and what to do when someone asks. The public promise is on `https://infinite-sports-app.web.app/delete-account` and in the Privacy Policy sections 10 and 11. This page says what the code actually does, which in a few places is more than the promise.

## 1. When someone deletes in the app

The person goes to Settings, then Delete account.

1. They read what is deleted and what is kept.
2. They type `DELETE` (capital letters) and tap "Delete my account".
3. The app asks them to sign in again: their password, Google or Apple. This is a security check, not an error.
4. The account is deleted straight away. They land on the welcome screen and see "Your account was deleted."

It cannot be undone. There is no grace period and no restore button.

**Deleted:**
- The sign-in itself, and the profile (name, email, phone, birthday, gender, city, ZIP).
- The public profile, and notification tokens and settings.
- The profile photo, and its link to any roster spot. This happens automatically. It is more than the public promise, which only offers it on request.
- Fantasy teams, picks, watchlists, badges and mini-league memberships.
- Support requests and their screenshots. They go with the account. (The policy's "up to two years" applies only while the account exists.)
- Event RSVPs and reminders.
- The link between their account and any league or tournament roster spot.
- Their referral code, if they had one.
- On iPhone, for Apple sign-ins, the Sign in with Apple link is cancelled too. This is also more than the promise, and it is waiting on a check by the iOS team (section 5).

**Renamed:**
- On the fantasy leaderboard their row becomes "Deleted manager". Their points and rank stay, so nobody else's rank moves.
- If they owned a mini-league with other members, it passes to the first remaining member, in the order the app stores them. We do not store join times, so it is not necessarily the longest-standing member. A league with nobody else in it is deleted.

**Kept:** see section 4.

## 2. When someone emails a request

1. Check that the email came **from the address on the account**. If it came from a different address, reply asking them to write from the account's own address, or to delete in the app. Do not delete.
2. Open the Manager app, then Users.
3. Find the person. Tap the three dots at the end of their row, then **Delete account...**
4. Type their **first name** to confirm. (If the account has no first name, the box asks for the full name.)
5. Optionally write a short reason, for example "emailed request". It is saved in a small "deleted on" record with no personal details. Do not put emails or phone numbers in it.
6. Tap delete. When it finishes the sheet says: "Removed N records, anonymised N, hand-offs N, files N, pending N". In plain words:
   - **Removed**: items deleted outright.
   - **Anonymised**: items that stay but no longer name the person.
   - **Hand-offs**: mini-leagues passed to another member because the person owned them.
   - **Files**: photo files removed.
   - **Pending**: photo files the server could not remove yet. It finishes them on the next try.
7. Reply to the person with two sentences:
   > Your Infinite Sports account has been deleted and cannot be restored.
   > Payment and league history records are kept as described in our Privacy Policy.

The Manager route is immediate. The 30 days in the policy is the outer limit.

## 3. Messages and what to do

Quoted exactly as the apps show them.

| Where | What you see | What to do |
|---|---|---|
| Manager | "Only an admin can delete accounts." | Your Manager login is not on the admin list. Tell Claude. |
| Manager | "You can't delete your own account from here." | The row is your own login. Delete your own account from the fan app. |
| Manager | "This is an old account that was combined into another one. Delete the kept account instead (p***@example.com)." | The person had two accounts, combined earlier. The masked email tells you which one was kept. Find that one in Users and repeat. |
| Manager | "The deletion did not finish. Tap Delete account to try again - it is safe to repeat." | Tap again. The server remembers what is left and finishes it. If it still fails, tell Claude. |
| Manager | "The server rejected the request (bad account id)." | Tell Claude. |
| Player's app | "This account was combined into another one. Sign in with p***@example.com and delete that account instead." | Tell the player to sign in with the kept account and delete that one. |
| Player's app | "Some data could not be removed. Please try again; if it keeps failing, email contact@infinitesports.org." | The player taps again. If it still fails, they email us and you tell Claude. |
| Player's app | "Please choose the same Google account you signed in with." | They picked a different Google account at the re-sign-in step. Ask them to try again. |
| Player's app | "Something went wrong. Please try again or email contact@infinitesports.org." | Try again. If it repeats, tell Claude. |

The sign-in check ("recent sign-in") is handled by the player's app, which asks them to sign in again. It never happens in the Manager.

## 4. What is never deleted, and why

- **Payment and registration records.** Kept for accounting, typically seven years. They keep the person's **display name** along with the amounts, dates and payment status. The other personal answers (phone, email, form answers, free-text notes) are removed. On request we can replace the display name with a generic entry, as the Privacy Policy promises (tell Claude).
- **League history**: rosters, results, standings and stats. This is the league's history. On request we can replace the name with a generic entry (tell Claude).
- **Votes and predictions.** They are recorded against the account. After deletion they remain as anonymous entries, with no name.
- **Referral rows where the deleted person is the Insider (the one who invited others).** These still hold the names of the people they invited, and they are NOT cleaned up today. This is a known gap. The Insiders program is not live yet. When it launches, those rows must be added to the deletion. Campaign audience lists hold only anonymous ids.
- **A small "deleted on" record** with no personal details: when the account was deleted, by whom (the person or an admin), and any leftover photo files to finish. It lets a retry finish safely.

## 5. For the iOS team (Paul / Bronsin)

Verify on simulator (iPhone; Paul/Bronsin)

On an iPhone simulator or a device, signed in with **Sign in with Apple**, go to Settings > Delete Account, type DELETE and tap "Delete my account". Check that:
1. The Apple sheet appears and Face ID / passcode completes it. Closing the sheet returns to the page with no message.
2. The deletion succeeds: you land on the welcome wall with "Your account was deleted." showing.
3. Xcode's console shows no `Apple token revoke failed` line. If it does show, the delete still went through, but the Apple revoke did not.
4. Afterwards, Settings > Apple ID > Sign-In & Security > Sign in with Apple no longer lists Infinite Sports, which proves the revoke worked.
5. Also on iOS, with a **Google** account: closing the Google sheet returns quietly to the page, and finishing it deletes the account.

Item 3 matters most: the re-sign-in uses only the Apple identity token, and the single-use code is saved for the revoke.

## 6. Testing the flow safely

- Make a **throwaway account** that you control (a new email you own, or a fresh Google or Apple login). Never use a real person's address. If you need an example, use `test@example.com`.
- Test the in-app path on that account. Then make a second throwaway and test the emailed-request path from the Manager.
- Never test deletion on a real player.
- Claude can rehearse the whole thing on a fake database that lives only on the computer. From the `functions/` folder it runs `npm run rehearse:deletion`. It needs Java installed (on this machine, Android Studio's bundled Java works). It prints one line starting `rehearse:deletion OK` when everything passes. It never touches the live database.
