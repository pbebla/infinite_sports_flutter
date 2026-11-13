# Support & Feedback Tickets — Design

**Date:** 2026-10-13 · **Owner decisions locked in chat** · Adapted from the owner's friend's
website spec (KinSprig) to our stack: two Flutter apps + Firebase, login wall, FCM.

## Decisions (owner)

1. In-app Help & Feedback form (fan app, drawer + Settings), mirroring the KinSprig layout:
   category cards with emoji + helper text, required message (≤5,000 chars), up to 5
   screenshots (client-side downscale ≤1600px JPEG), auto-captured context (uid, name,
   email, app version, platform iOS/Android, device model, current screen). Dark/gold theme.
2. Categories: Suggestion 💡 · Comment 💬 · Something is broken 🐞 · I need help ❓ ·
   Account or access 🔑 · Something else ✨.
3. Everyone is signed in (login wall) → no anonymous path, no honeypot/IP limits. Light
   per-account rate limit (6 tickets/hour) enforced in rules/function.
4. **User emails: exactly two** — acknowledgment on submit ("Thanks — your reference is
   #N"), and a closing email saying what happened (fixed / added / planned / not doing)
   **plus an auto-generated joke** (trendy, movie/TV-quote flavored, matched to the
   ticket). The Manager close flow shows the generated joke in an editable box — the
   owner can accept, tweak, or fully rewrite before sending. Mid-thread admin replies
   notify by push (+ in-app), NOT email.
5. Admin notification: every new ticket (and user reply) emails support@infinitesports.org
   (Reply-To: the user) + red badge on the Manager drawer (Insiders-inbox pattern).
6. "My Tickets" page (fan): user's tickets with full thread minus internal notes, plain
   statuses (Open · In progress · Waiting for your reply · Answered · Closed), reply box
   (reply → status Open + email to support inbox).
7. Manager Support inbox: live list (status/category/platform/version filters + search),
   thread view (context header, screenshots, replies in order), reply (→ user push,
   status Answered), internal notes (admin-only, never emailed), status control, close
   flow (outcome note + joke box → closing email).
8. Claude handoff: tickets live in RTDB → Claude reads /Support/Tickets/<n> + Storage
   screenshots directly on "ticket N, go".
9. SKIPPED from the website spec (deliberate): IMAP inbound-email threading, Sent-folder
   APPEND, honeypot, IP rate limits, magic-link admin auth, HEIC handling (image_picker
   delivers JPEG), anonymous flow. Email replies from users are not supported — the app is.

## Data (RTDB)

- `Support/Counter` — int, transaction-incremented; ticket id = counter value.
- `Support/Tickets/<n>`: Num, Uid, Name, Email, Category, Status
  (open|in_progress|waiting|answered|closed), CreatedAt, UpdatedAt, AppVersion,
  Platform, Device, Screen, Screenshots[], ClosedOutcome, ClosedNote (the joke/text as
  sent), Thread/<pushId>: {From: user|admin|note, Uid, Name, Text, At, Screenshots[]?}.
- `Support/UserTickets/<uid>/<n>` = true — per-user index (rules-friendly "my tickets").
- `Admins/<uid>` = true — admin allowlist (seeded with the owner; drives rules + inbox).

## Security rules (first private subtree in this DB)

- `Support/Tickets/$n`: read/write-thread if `auth.uid == data.Uid` OR `root.Admins[auth.uid]`;
  create via fan app sets Uid = auth.uid; status/notes writes admin-only (validate).
- `Support/UserTickets/$uid`: read/write only `auth.uid == $uid` (+ admin read).
- Internal notes: stored in Thread with From='note'; FAN app filters them out AND rules
  cannot hide subnodes — acceptable v1 compromise is a separate `Notes/` subtree under the
  ticket readable only by admins (NOT inside Thread). → Notes live at
  `Support/Tickets/<n>/Notes/<pushId>` with admin-only read rule.
- Storage `support/<n>/...`: write by authenticated creator, read owner+admin (storage rules).
- Existing public paths untouched — rules change is additive to /Support and /Admins only.

## Functions (fan repo /functions)

- `onTicketCreated` (RTDB onCreate Support/Tickets/<n>): email ack → user; email
  new-ticket → SUPPORT_EMAIL (Reply-To user, subject "[Infinite Sports <Category>] from
  <Name> (ref #N)").
- `onTicketThreadMessage`: user reply → email support inbox + status Open; admin reply →
  FCM push to user token ("Your ticket #N was answered") + status Answered.
- `onTicketClosed` (Status → closed): closing email → user with outcome + ClosedNote.
- `generateTicketJoke` (callable, admin-only): returns a one-liner matched to
  category+message. Uses Anthropic API (model claude-haiku-4-5-20251001, Messages API,
  ANTHROPIC_API_KEY secret) when the secret exists; otherwise falls back to a canned
  per-category joke bank. Manager calls it in the close flow.
- Email transport: nodemailer SMTP (STARTTLS :587), secrets SUPPORT_SMTP_HOST/PORT/
  USER/PASS + SUPPORT_EMAIL. Store ticket BEFORE any email; send async; HTML-escape all
  user strings; strip newlines from subjects; log sends to `Support/MailLog` (to,
  subject, ok/err, at). If secrets absent → email silently off (functions log a warning).
- iOS parity rule: no RTDB get() anywhere; functions use admin SDK (unaffected) but fan/
  manager clients use once()/streams only.

## Fan app (branch zaya-support)

- `lib/support/support_form_page.dart` (+ drawer & Settings entries), category cards,
  message, screenshot picker (image_picker, downscale, upload to Storage), context
  capture (package_info_plus version, Platform.isIOS, device model via existing deps or
  MediaQuery-safe fallback, current screen label passed by caller).
- `lib/support/my_tickets_page.dart` — live stream of UserTickets index → tickets;
  thread UI (notes invisible by rules), reply box, plain statuses, pull of new messages
  live; badge dot in drawer when a ticket turns Answered (local read marker).
- Push: reuse existing FCM plumbing (token on user node); notification tap → My Tickets.

## Manager app (zaya-features)

- `lib/ui/support/support_inbox_page.dart` + thread page: live streams, filters, search;
  reply, internal notes, status chips; close dialog = outcome selector (Fixed · Added ·
  Planned · Won't do · Other) + joke box with "Generate" button (callable) → preview →
  Close & send. Red badge count (open tickets) on drawer row (Insiders pattern).
- Drawer row "Support" above Registrations.

## Tests

- Functions (vitest): email formatting/escaping/subject-injection, joke fallback bank,
  status transitions, MailLog writes (transport mocked).
- Fan: form validation, category selection, context capture seam, My Tickets rendering/
  reply (Firebase-free seams, house pattern).
- Manager: inbox filters, close-flow joke editing, note privacy (model-level).

## Release

Fan + functions on zaya-support → PR to main (store release to reach players; note iOS
"verify on simulator" items: image_picker flow + push). Manager on zaya-features →
tablet install. SMTP password rotation after go-live (owner).
