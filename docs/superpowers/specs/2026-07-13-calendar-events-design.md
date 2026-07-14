# Calendar Events & Categories (Epic P2) — Design Spec

**Date:** 2026-07-13
**Epic:** Calendar & Events (piece 2 of 5)
**Repos:** infinite_sports_flutter (fan) + InfiniteSportsManagerFlutter (manager), branch `zaya-calendar-events` in both.
**Owner decisions:** category list approved; contact = phone (call/text) + Instagram/Facebook/YouTube links; date ranges + weekly repeating events.

## Goal

Give events real structure (IDs, categories, ranges, repeats, contact/socials,
full-quality flyers), a rebuilt manager event form (create/edit/delete +
flyer upload), and category filter chips on the fan calendar.

## Categories (fixed seed list, extensible later via DB)

Futsal, Basketball, Flag Football, Soccer, Volleyball, Pickleball,
Tournaments, Community.

## Data model

New RTDB node `EventsV2/<pushId>`:

```
Title, Category, Info (short), Details (long, optional)
StartDate, EndDate            (MMDDYYYY; single-day = same value)
Repeat: { Freq: "weekly", Until: MMDDYYYY }   (optional)
StartTime, EndTime            (existing "h:mma" style strings)
Location (name), Address (for maps)
ContactPhone, Instagram, Facebook, Youtube    (all optional)
ImageUrl                      (full-quality flyer in Firebase Storage
                               at EventFlyers/<pushId>.jpg, no compression)
CreatedAt (server timestamp)
```

**Legacy compatibility:** manager writes a mirror row to the old `Events`
list (Title, EventDate=StartDate display format, StartTime, EndTime,
Location, Address, Info, ImageUrl) so not-yet-updated fan apps still see new
events in Around You. New fan app reads `EventsV2` and merges with legacy
`Events` rows (legacy rows keep working via the existing index-based
EventPage; V2 events open EventPage by V2 id).

**Occurrences:** fan app expands each V2 event into calendar days:
every day in [StartDate, EndDate], and for weekly repeats, the same
weekday(s) window repeated until `Repeat.Until`. Dots + day sheets use
occurrences; the event itself is one record.

## Manager app

Rebuild `lib/ui/events/events_page.dart` into:
- Event list (V2 + legacy read-only rows) with edit/delete for V2 events;
  delete also removes the legacy mirror row and the Storage flyer.
- Create/edit form: Title, Category dropdown (seed list), Info, Details,
  date range picker, "Repeats weekly" toggle + Until date, start/end time
  pickers, Location, Address, ContactPhone, Instagram, Facebook, Youtube,
  flyer pick (image_picker, original quality) with upload progress +
  preview. Required: Title, Category, StartDate, StartTime, Location.
- `EventService`: createV2 (push id, Storage upload, dual-write legacy),
  updateV2 (re-mirror legacy), deleteV2 (row + mirror + flyer).

## Fan app

- `Event` model gains the new fields + `id`; `getEventsV2()` in a new
  `lib/misc/event_repo.dart` (stream-friendly read of EventsV2 + legacy
  merge; falls back gracefully offline).
- `eventsByDay` upgraded to occurrence expansion (pure, unit-tested:
  ranges, weekly repeats, until-date inclusive, bad data skipped).
- Calendar tab: horizontal filter chip row (All + categories) between the
  weekday header and the months; multi-select; selected chips use
  colorScheme.primary (gold dark / red light); filtering hides dots and
  day-sheet entries of other categories. Chip choice persists for the
  session only.
- EventPage: accepts V2 events (by id) without visual redesign (P3 does
  the redesign); Attendees keep working for legacy events, V2 attendees
  stored under `EventsV2/<id>/Attendees`.

## Out of scope (P3/P4)

Event page redesign, call/text/social buttons, share, add-to-phone-calendar,
remind-me, notification targeting, favorite sports.

## Error handling

Uploads: failure surfaces a retry snackbar, no partial DB writes (write DB
only after Storage upload succeeds). Fan reads: V2 parse errors skip the
record silently rather than breaking the calendar; legacy behavior unchanged.

## Testing

Unit: occurrence expansion (single, range, weekly repeat, until edge),
category filtering, V2 parse. Widget: chip row filters dots. Manual e2e:
create V2 event with flyer in manager → appears on fan calendar day(s),
filter chips isolate it, day sheet opens it, legacy mirror visible in old
Around You list. Both modes (gold/red).

## Delivery

Branch `zaya-calendar-events` both repos, own worktrees; owner tests both
apps; merge both to `zaya-features` on sign-off.
