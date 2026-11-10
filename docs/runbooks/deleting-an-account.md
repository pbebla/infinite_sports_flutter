# Deleting an account

How account deletion works, and what to do when someone asks. The public promise is on `https://infinite-sports-app.web.app/delete-account` and in the Privacy Policy sections 10 and 11. This page agrees with both.

## 1. When someone deletes in the app

The person goes to Settings, then Delete account.

1. They read what is deleted and what is kept.
2. They type `DELETE` (capital letters) and tap "Delete my account".
3. The app asks them to sign in again: their password, Google or Apple. This is a security check, not an error.
4. The account is deleted straight away. They land on the welcome screen and see "Your account was deleted."

It cannot be undone. There is no grace period and no restore button.

**Deleted:**
- The sign-in itself, and the profile (name, email, phone, birthday, gender, city, ZIP, photo).
- The public profile, the profile photo file, and notification settings.
- Fantasy teams, picks, watchlists, badges and mini-league memberships.
- Support tickets and their screenshots.
- Event RSVPs and reminders.
- The link between their name and any league or tournament roster spot.
- Their referral code, if they had one.

**Renamed:**
- On the fantasy leaderboard their row becomes "Deleted manager". Their points and rank stay, so nobody else's rank moves.
- If they owned a mini-league with other members, the league goes to the first remaining member. We do not store join times, so it is the first one in the database's order, not the longest-standing member. A league with no one else in it is deleted.

**Kept:** see section 4.

On iPhone, for Apple sign-ins, the app also cancels the Sign in with Apple link. This is waiting on a check by the iOS team (section 5).

## 2. When someone emails a request

1. Check that the email came **from the address on the account**. If it came from a different address, reply asking them to write from the account's own address, or to delete in the app. Do not delete.
2. Open the Manager app, then Users.
3. Find the person. Tap the three dots at the end of their row, then **Delete account...**
4. Type their **first name** to confirm. (If the account has no first name, the box asks for the full name.)
5. Optionally write a short reason, for example "emailed request". It is saved in the record of the deletion. Do not put emails or phone numbers in it.
6. Tap delete. When it finishes you see counts of what was removed. They are only totals, for your records:
   - **Deleted**: items removed outright.
   - **Anonymised**: items that stay but no longer name the person.
   - **Hand-offs**: mini-leagues passed to another member.
   - **Storage files**: photos and screenshots removed.
7. Reply to the person with two sentences:
   > Your Infinite Sports account has been deleted and cannot be restored.
   > Payment and league history records are kept as described in our Privacy Policy.

Reply within 30 days. The Manager route is immediate, so there is nothing to wait for.

## 3. Messages and what to do

| What you see | What it means | What to do |
|---|---|---|
| "Only an admin can delete accounts" (Manager) | Your Manager login is not on the admin list. | Tell Claude. |
| "You can't delete your own account from here." (Manager) | The row is your own login. | Delete your own account from the fan app instead. |
| "This account was combined into another one..." with a masked email like `p***@example.com` | The person had two accounts and they were combined. The one you picked is the old copy. | Delete the **kept** account. The masked email tells you which one. Find it in Users and repeat. |
| "Some data could not be removed" | Part of the deletion failed. | Tap delete again. The server remembers what is left over and finishes it on the retry. If it still fails, tell Claude. |
| "recent sign-in", or the app asks you to sign in again | A safety check that the person really owns the account. | In the fan app it signs them in again for you. It never happens in the Manager. |
| "Please choose the same Google account you signed in with." (fan app) | They picked a different Google account at the re-sign-in step. | Ask them to try again with the account they use in the app. |

## 4. What is never deleted, and why

- **Payment records** (registration payments, fantasy access payments, amounts and dates). Kept for accounting, typically seven years. Names and free-text notes are removed from them. They are marked as belonging to a deleted account.
- **League history**: rosters, results, standings and stats. This is the league's history. The person's photo and sign-in link are removed. On request we can also replace their name with a generic entry (tell Claude).
- **Votes and predictions.** They are stored against an anonymous id with no name. They stay, and are no longer tied to a person.
- **Referral records and campaign lists.** They hold only anonymous ids. A referral row loses the person's name but still counts for whoever invited them.
- **A small stamp** saying the account was deleted, when, and by whom (the person or an admin). It has no personal details. It also lets a retry finish safely.

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

- Make a **throwaway account** that you control (a new email you own, or a fresh Google or Apple login). Never test on `test@gmail.com` or on anyone's real address.
- Test the in-app path on that account. Then make a second throwaway and test the emailed-request path from the Manager.
- Never test deletion on a real player.
- Claude can rehearse the whole thing on a fake database that lives only on the computer. From the `functions/` folder it runs `npm run rehearse:deletion`. It needs Java installed (on this machine, Android Studio's bundled Java works). It prints one line starting `rehearse:deletion OK` when everything passes. It never touches the live database.
