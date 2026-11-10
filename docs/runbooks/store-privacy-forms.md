# Store privacy forms — what to enter (fan app)

The stores compare these forms with the Privacy Policy and with what the app does. The answers below match the policy published at `https://infinite-sports-app.web.app/privacy` (last updated 2026-11-09) and the code as of PR #17. Update this file and the policy together whenever a new data type is added.

Links to paste:

| Field | Value |
|---|---|
| Privacy policy URL (both stores) | `https://infinite-sports-app.web.app/privacy` |
| Terms / EULA URL (App Store Connect, optional) | `https://infinite-sports-app.web.app/terms` |
| Account deletion URL (Play Console, Data safety → Data deletion) | `https://infinite-sports-app.web.app/delete-account` |
| Support URL / email | `https://infinitesports.org` · `contact@infinitesports.org` |

## Google Play — Data safety form

**Overview**
- Does your app collect or share user data? **Yes**
- Is all user data encrypted in transit? **Yes**
- Do you provide a way for users to request data deletion? **Yes** (in-app Settings → Delete Account, and the URL above)
- Account creation: **Yes** — username/password, Google, Apple. Account deletion: in-app + web link.

**Data types** (Collected = sent off the device; Shared = given to a third party for its own purposes — we share nothing for third-party purposes; processors like Firebase and Stripe don't count as "shared" under Google's definition):

| Category | Type | Collected | Required? | Purposes |
|---|---|---|---|---|
| Personal info | Name | Yes | Yes | App functionality, account management |
| Personal info | Email address | Yes | Yes | App functionality, account management |
| Personal info | Phone number | Yes | Yes | App functionality, account management |
| Personal info | Address (city, ZIP) | Yes | Yes | App functionality (city/ZIP only) |
| Personal info | Other (date of birth, gender, how you heard about us) | Yes | Yes | App functionality, analytics (internal counts only) |
| Personal info | User IDs | Yes | Yes | App functionality, account management |
| Financial info | Purchase history (registration/fantasy payment status, amounts) | Yes | Optional | App functionality |
| Financial info | Payment info | **No** — card details go to Stripe directly; the app never holds them | | |
| Location | Approximate / precise location | **No** — used on device only, never sent to our servers | | |
| Photos and videos | Photos | Yes | Optional | App functionality (profile photo, support screenshots) |
| Messages | Other in-app messages (support tickets) | Yes | Optional | App functionality |
| App activity | App interactions (fantasy picks, followed sports, event RSVPs, poll votes) | Yes | Optional | App functionality |
| App activity | Other user-generated content (team names, profile details) | Yes | Optional | App functionality |
| App info & performance | Crash logs / diagnostics | **No** (no analytics or crash SDK) | | |
| Device or other IDs | Device or other IDs (push notification token) | Yes | Optional | App functionality |

For every row: processed ephemerally **No**; data **not** shared with third parties; security practices: encrypted in transit; users can request deletion.

**Target audience & content:** not designed for children; age 13+ (the app blocks under-13 sign-ups). Do **not** opt into the Families program.

**Other declarations:** no ads; no "Real-money gambling, games and contests" (Infinite Fantasy has no entry fee and no prize, so it is outside that policy — if the season pass is ever switched on, re-check this before the next release); Financial features: none (no loans/trading); Health: none.

## Apple — App Privacy (App Store Connect)

**Data linked to the user** (all collected by us, none used for tracking):

| Apple category | Data | Purposes |
|---|---|---|
| Contact info | Name, email address, phone number, physical address (city/ZIP) | App functionality |
| Identifiers | User ID | App functionality |
| User content | Photos, customer support messages, other user content (team names, profile details) | App functionality |
| Purchases | Purchase history (registration/fantasy payment status) | App functionality |
| Usage data | Product interaction (fantasy picks, follows, RSVPs) | App functionality |
| Sensitive info | None (gender and DOB go under "Other data types" → Other) | |
| Other data | Date of birth, gender, referral source | App functionality |

**Not collected:** precise/coarse location (device-only), financial payment details (Stripe), health, contacts, browsing/search history, diagnostics/crash data, advertising data.

**Tracking:** No. **Privacy nutrition label "Data used to track you":** none.

**Required permissions text (Info.plist, already set):** location when-in-use (Around You map), camera and photo library (profile photo / support screenshots). The two "Always" location keys were removed on 2026-11-09 — the app never asks for background location.

**Account deletion (Apple 5.1.1(v)):** the in-app Delete Account must remove the account and its data and revoke Sign in with Apple tokens. See `docs/superpowers/plans/2026-11-09-account-deletion.md` — until it ships, honour emailed requests by hand (tell Claude; the merge/deletion tooling runs against the live database only on the owner's go).

**Third-party AI disclosure (Apple 5.1.2(i)):** the policy §6 names Anthropic and exactly what is sent (public stats only). Nothing else to declare on the form.

## When something changes

- New data type collected → add a row here, a line in the policy §1/§2, and update both store forms before the release.
- Fantasy season pass switched on → Terms §5 "Free to play" must change, and the Play "gambling/contests" + Apple in-app-purchase questions need a fresh look **before** the switch, not after.
- Texting players starts → add the consent checkbox at sign-up/registration (not in the app yet); the policy §7 wording is already in place.
