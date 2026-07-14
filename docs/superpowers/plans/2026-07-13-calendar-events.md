# Calendar Events & Categories (P2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Structured events (EventsV2: ids, categories, ranges, weekly repeats, contact/socials, full-quality flyers), rebuilt manager event manager (create/edit/delete + flyer upload + legacy dual-write), and category filter chips on the fan calendar.

**Architecture:** New RTDB node `EventsV2/<pushId>` is the source of truth for new events; the manager mirrors a legacy `Events` list row per V2 event (key `LegacyIndex` stored on the V2 record) so old fan builds keep seeing new events. The new fan app merges V2 + unmirrored legacy rows, expands occurrences (range + weekly repeat) into per-day buckets, and filters by category.

**Tech stack:** Flutter, firebase_database, firebase_storage, image_picker (manager), Riverpod (manager), vanilla setState (fan).

**Repos/branches:** `zaya-calendar-events` in both worktrees:
- Fan: `C:\Users\zayaa\StudioProjects\infinite_sports_flutter\.claude\worktrees\zaya-nav-glass`
- Manager: `C:\Users\zayaa\StudioProjects\InfiniteSportsManagerFlutter\.claude\worktrees\zaya-calendar-events`

**Shared category seed list (identical string keys both repos):**
`Futsal, Basketball, Flag Football, Soccer, Volleyball, Pickleball, Tournaments, Community`

**Date format:** MMDDYYYY strings (existing convention; fan helpers in utility.dart, manager DateFormatter).

---

### Task 1 (fan): EventV2 model + occurrence expansion

**Files:**
- Modify: `lib/model/event.dart` (add fields: id, category, details, startDate, endDate, repeatFreq, repeatUntil, contactPhone, instagram, facebook, youtube; keep legacy fields; add `Event.fromV2(String id, Map json)` factory parsing MMDDYYYY via existing utility date helpers)
- Modify: `lib/misc/event_utils.dart` — replace `eventsByDay` internals with occurrence expansion:

```dart
/// Every calendar day this event occupies: [start..end], repeated weekly
/// (same weekday span) until repeatUntil when Repeat.Freq == "weekly".
/// Caps at 370 days of expansion to bound bad data.
List<DateTime> occurrenceDays(Event e) { ... }
Map<DateTime, List<CalendarEntry>> eventsByDay(List<Event> events) { ... }
```
  where `CalendarEntry` carries `{Event event, int? legacyIndex, String? v2Id}` (replaces bare MapEntry; calendar_tab + day sheet updated accordingly).
- Test: `test/misc/event_utils_test.dart` — single day, multi-day range dots every covered day, weekly repeat until inclusive, repeat stops at cap, null/garbage dates skipped, category filter helper.

Steps: write failing tests → implement → `flutter test test/misc/event_utils_test.dart` → commit.

### Task 2 (fan): EventsV2 repo + legacy merge

**Files:**
- Create: `lib/misc/event_repo.dart`

```dart
/// Loads EventsV2 (map keyed by push id) + legacy Events list; V2 records
/// with LegacyIndex hide their mirror row from the merged list.
Future<List<Event>> getAllEvents() async { ... }
```
- Modify: `lib/calendar_tab.dart` `_load()` to use `getAllEvents()`.
- Test: `test/misc/event_repo_test.dart` for the pure merge/dedup function `mergeEvents(Map v2, List legacy)`.

### Task 3 (fan): category filter chips on calendar

**Files:**
- Modify: `lib/calendar_tab.dart` — `kEventCategories` const list; horizontal `FilterChip` row ("All" + categories, multi-select, All = empty selection) between weekday header and months; selection filters `byDay` before it reaches CalendarMonthView; chips use colorScheme.primary selected state.
- Test: `test/calendar_month_view_test.dart` add: chip row renders; selecting a category hides other categories' dots (pump CalendarTab-shaped harness with injected data — extract the filter into pure `filterByCategories(byDay, Set<String>)` and unit-test that).

### Task 4 (fan): EventPage V2 support

**Files:**
- Modify: `lib/eventpage.dart` — constructor `EventPage({this.index, this.eventV2})`; V2 path loads from `EventsV2/<id>`, attendees at `EventsV2/<id>/Attendees`; legacy path unchanged. Show category chip + Details paragraph when present (no redesign).
- Modify: `lib/misc/utility.dart` `getEvent(index)` untouched; add `getEventV2(String id)` in event_repo.
- Day sheet + Around You keep working for both entry kinds.

### Task 5 (manager): EventV2Model + EventService V2 CRUD

**Files:**
- Create: `lib/models/event_v2_model.dart` (fields per spec; `fromJson`/`toJson` with Firebase key names Title/Category/Info/Details/StartDate/EndDate/Repeat{Freq,Until}/StartTime/EndTime/Location/Address/ContactPhone/Instagram/Facebook/Youtube/ImageUrl/LegacyIndex/CreatedAt; `toLegacyJson()` producing the old Events row shape)
- Modify: `lib/core/constants/firebase_paths.dart` — add `eventsV2 = 'EventsV2'`.
- Modify: `lib/services/firebase/event_service.dart`:

```dart
Future<String> createEventV2(EventV2Model e, {Uint8List? flyerBytes}) async {
  // 1. push id  2. optional Storage upload EventFlyers/<id>.jpg (no
  // compression, contentType image/jpeg) -> ImageUrl  3. append legacy
  // mirror row, remember index  4. set EventsV2/<id> with LegacyIndex.
}
Future<void> updateEventV2(String id, EventV2Model e, {Uint8List? newFlyer}) // re-set V2 + rewrite legacy row at LegacyIndex
Future<void> deleteEventV2(String id) // remove V2 node, null out legacy row, delete Storage flyer (ignore missing)
Future<Map<String, EventV2Model>> getEventsV2()
```
- Modify: `pubspec.yaml` — add `image_picker`, `firebase_storage` (match fan app major versions).
- Test: `test/event_v2_model_test.dart` — round-trip json, toLegacyJson mapping.

### Task 6 (manager): rebuilt Events UI

**Files:**
- Rewrite: `lib/ui/events/events_page.dart` — list of events (V2 styled cards: flyer thumb, title, category chip, date range; legacy rows dimmed "legacy" badge, read-only) + FAB "New event".
- Create: `lib/ui/events/event_form_page.dart` — form per spec: Title*, Category* dropdown (seed list), Info, Details (multiline), date RANGE (two ListTile pickers, End defaults to Start), "Repeats weekly" switch + Until date picker (visible only when on), Start*/End time pickers (showTimePicker, stored "h:mma" like existing), Location*, Address, ContactPhone, Instagram, Facebook, Youtube, flyer picker (image_picker `pickImage(source: gallery)` NO maxWidth/maxHeight/imageQuality args = original quality) with preview + remove; Save with progress spinner; edit mode pre-fills + Delete button with confirm dialog.
- Provider: reuse `eventServiceProvider`.
- Manual verify: `flutter analyze` + run on emulator.

### Task 7 (both): end-to-end verification

- `flutter test` + `flutter analyze` both repos.
- Build + install BOTH apps on emulator (fan package com.infinitesports.Infinite_Sports_App; manager has its own id).
- Manager: create "Test Futsal Night" (Futsal, next Friday, flyer from emulator gallery) → verify EventsV2 node + legacy mirror row in DB, fan calendar dot on that day, chip filtering, day sheet → EventPage, Around You legacy list shows it.
- Cleanup test event via manager delete (verify mirror + flyer removed).
- Both themes (gold/red) screenshots.

### Task 8: commits + memory

- Commit per task, both repos; update epic memory status.
