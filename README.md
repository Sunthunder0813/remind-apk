# Remind

A smart, AI-assisted notes and reminder app built with **Flutter**, targeting **Android & iOS**.

## App Concept

Remind is a notes/organizer app where users create notes with optional reminders, organize them into **nested folders** (browsed like iOS Notes — tap to drill in, swipe right to archive, swipe left to delete, both instant with Undo), view everything on a **calendar**, and get **AI-suggested reminder times** as they type. Notes support **drag-to-reorder checklists** and **per-item Undo/Redo** on title/content text. The notes list itself is a **toggleable grid/list view** with colorful auto-tinted cards, and both notes and folders can be given a **custom background image theme** (bundled presets or user-uploaded photos) via a single-select edit mode. A dark purple/lilac theme runs throughout, plus an **Android home screen widget** showing today's calendar todos as interactive, per-item checkable rows grouped by note (see "Home Screen Widget" below — now functionally complete). Also includes a **Discover** tab — a Tinder-style swipe feed for browsing anime via the free Jikan API, filterable by genre — a **Liked Anime** tab for reviewing what you've swiped right on, and a **Watchlisted** tab (reached via the center FAB on Liked Anime) for anime moved out of Liked with an optional personal **remark** attached to each entry. Both lists persist across app restarts via Hive.

The **Calendar** tab now also doubles as a lightweight todo list: tapping a day and then the shared center FAB opens the real note editor (not a dialog), pre-tagged to that day, so calendar-created reminders are full notes with optional checklists — kept separate from the main Notes tab. **Only Calendar-tab notes feed the home screen widget**; regular Notes-tab notes remain notification-only and never appear there.

## Core Features

| Feature | Description | Status |
|---|---|---|
| Notes / Folders | Notion-style borderless editor (title + body, no boxed fields), nested folders browsed by tapping in/out | ✅ Done |
| Notes List Layout | Toggleable **2-column masonry grid** (default, via `flutter_staggered_grid_view`) or **single-column list**, switched via an icon in the top AppBar. Folders and notes render as flat, rounded, colored cards (no `Card`/`ListTile` chrome) — folders show a fixed dark slate tile, notes are tinted from a 6-color pastel palette hashed deterministically off the note's `id` (or its explicit `colorValue`/`backgroundImagePath` if set), so colors stay stable across rebuilds. Note cards show an inline checklist preview (up to 4 items + "+N more") when the note has tasks, or a free-text preview otherwise, plus a relative "Edited ..." timestamp. **Calendar-created notes are excluded from this list** (see Calendar Todos below) | ✅ Done |
| Background Theming | Notes and folders can each be given a **custom background image** — either one of 12 bundled preset textures (`assets/backgrounds/`) or a user-uploaded photo (via `image_picker`, copied into permanent app storage so it survives gallery changes). Applied via a dedicated **single-select edit mode**: tap the pencil icon in the AppBar, tap exactly one note or folder, the theme picker bottom sheet opens immediately, pick a background (or "Remove background" if one's already set) and it's applied instantly — no multi-select, no separate "Apply" step. Themed cards get a dark gradient scrim for text legibility and flip their text/icon colors to white. The **note editor screen** also renders the note's background full-screen (behind the AppBar, body, and keyboard toolbar, with the same scrim) when opened. When **browsing inside a themed folder**, the top AppBar itself shows that folder's background + scrim (title/icons only — the note grid underneath stays plain); the root "Notes" view never shows a background. User-uploaded background files are cleaned up from disk both when a background is replaced and when its note/folder is permanently deleted (after the 5s Undo window expires) | ✅ Done |
| Archive | Swipe a note or folder **right** to archive (instant, with Undo); archived folders can still be opened to browse their contents; archived notes open in a true read-only mode (same layout, nothing editable). Swipe gestures are disabled while edit mode (theming) is active, to avoid conflicting with the tap-to-theme gesture | ✅ Done |
| Delete | Swipe a note or folder **left** to delete (instant, with Undo that restores from Hive, not from a pending timer) | ✅ Done |
| Checklists | Type `- task` and press Enter (or tap "Add a task" in the keyboard toolbar) to turn a line into a checkbox; drag the handle (floats in the right gutter) to reorder; swipe a task left to remove it; new tasks auto-focus their text field immediately so you can start typing without an extra tap; empty rows show a rotating realistic placeholder (e.g. "e.g. Buy groceries") instead of a generic "Task" label. Checklist data is a structured Hive field (`Note.checklistItems`, a `List<ChecklistItem>`), not text encoded inside `content` — see Data & Storage below | ✅ Done |
| Undo / Redo (Editor) | Title and content text support **Undo/Redo**, independent of auto-save. Snapshots are pushed on a 500ms typing-pause debounce (not per-keystroke), shown as two icon buttons in the keyboard toolbar (next to the word count, separated by a vertical divider) that grey out and disable themselves when there's nothing to act on. Scoped to text only — checklist and reminder changes are not part of the undo history | ✅ Done |
| Reminders | Bell icon next to the title opens the date+time picker; once set, shows as a small purple pill with change/clear. **On calendar-created notes, the date is implicit** (see Calendar Todos) — tapping the bell skips straight to the time picker instead of re-asking for a date already chosen on the Calendar tab | ✅ Done |
| Calendar Todos (Editor Integration) | Tapping a calendar day, then the shared center FAB, opens the **real `NoteEditorScreen`** (not a dialog) via `addReminderForSelectedDay()`. The note is tagged `isCalendarReminder: true` and stamped with `calendarDate` (the selected day) so it groups under that day on the Calendar tab even with no reminder time set — the reminder bell starts empty by design; the user opts in to a time. These notes are **excluded from the main Notes tab** (filtered out of `_notesInCurrentFolder` in `notes_screen.dart`). Calendar's day list supports **swipe-left-to-delete with Undo** (matching the Notes tab's pattern, reusing the same `showUndoToast` helper) — archive is intentionally not offered here. Every create/edit/delete/toggle on this screen also calls `WidgetService.refreshWidget(...)` to keep the home screen widget in sync | ✅ Done |
| Bold / Italic Formatting | **Removed.** The toolbar's Bold/Italic buttons, the underlying markdown-marker encoding (`*`, `**`, `***`), and the custom `_MarkdownPreviewController` were all taken out. `_contentController` is back to a plain `TextEditingController`. | ❌ Removed |
| Text Color | **Built, then removed.** A toolbar "color fill" button briefly opened an HSV color-wheel dialog (`flutter_colorpicker`) to recolor selected text, storing color as an inline `{{#RRGGBB:text}}` marker in `Note.content` via a `_HighlightPreviewController`. All of it — the marker regex, the dialog, the toolbar button, and the controller subclass — has since been removed. `_contentController` is a plain `TextEditingController` again, and `flutter_colorpicker` is no longer a dependency. | ❌ Removed |
| Pin & Accent Color | **Hive fields only** — `isPinned`/`colorValue` are preserved when editing an existing note, but there is no editor UI to set/change them anymore (icon + 7-swatch picker were removed). `colorValue` IS now read by the notes list grid (overrides the palette hash if set), but there's still no UI to set it directly — only `backgroundImagePath` is settable, via the theming edit mode | 🔲 Fields exist, partial use |
| Word Count | Live count in the keyboard toolbar while editing (char count was removed — words only). Sits on the **left** of the toolbar, followed by a vertical divider, then **Undo/Redo** icons, then a spacer, then "Add a task" on the **right**. Word count is also shown inline below the content in read-only/archived preview mode | ✅ Done |
| Slash Command Menu | **Removed.** Typing `/` no longer opens a menu; all actions (task, reminder) are reachable via the bell icon and keyboard toolbar instead | ❌ Removed |
| Auto-save | Two layers, both writing straight to Hive without navigating away: (1) a 1.2s **debounce** timer that resets on every keystroke in title/content, and (2) a **periodic** `Timer.periodic` that fires every **10 seconds** regardless of typing activity, as a safety net for continuous typing or an app kill before the debounce window elapses. Both call the same `_autoSave()`, which no-ops if there's nothing unsaved or the note is entirely empty. The app bar button is "Done" rather than "Save". **Hardened against duplicate-note creation**: a new note's id is generated once and cached in `_persistedNoteId`, so every subsequent save (debounce, periodic, Done, back-nav) reuses the same id instead of minting a new one; `_saveNote` also guards against re-entrant calls via an `_isSaving` flag and cancels any pending debounce timer on every save | ✅ Done |
| Back Navigation Auto-save | Pressing the system back button or swiping back no longer requires tapping Done first. The screen is wrapped in a `PopScope` with `canPop: false`; its `onPopInvokedWithResult` flushes any pending edits via `_saveNote(popOnSave: false)` and then manually pops with a `true` result, so the notes list still reloads correctly. Guarded by an `_isPopping` flag so a duplicate pop event can't re-trigger the save/pop sequence | ✅ Done |
| AI Smart Suggestions | Watches what you type live and shows a dismissible chip suggesting a reminder time — fully local rule-based parsing, no network call | ✅ Done |
| Calendar View | Month view with reminder dots; tap a day to see/add todos for it directly via the shared FAB (no more in-tab "Add reminder"/"Add one" buttons — those were removed in favor of the FAB being the single entry point). Each day's list shows checkable circle icons (tap to toggle `Note.isCompleted`, with strikethrough + grey-out on completion) and supports swipe-left-to-delete with Undo | ✅ Done |
| Local Notifications | Reminders fire as device notifications | ✅ Done |
| Dark Purple Theme | Material 3 dark palette (`#29262B` / `#3C3541` / `#AC5FDB` / `#E3A2EE`); `inputDecorationTheme` is borderless/unfilled by default app-wide | ✅ Done |
| Discover (Anime Swipe) | Swipe-card anime browser using the Jikan API, filterable by genre (chips fetched live from `/genres/anime`); swipe gives a real-time fade overlay in the swipe direction | ✅ Done |
| Liked Anime | Persisted (Hive-backed) flat grid of everything liked on Discover, with genre filter chips and an adjustable "cards per row" layout setting. Long-press a card opens a small actions menu — **Add to Watchlist** or **Remove from Liked** — both fire instantly (no confirmation dialog) with an Undo toast as the safety net. Tap a card to open a read-only detail popup (image, score, genres, synopsis) with an icon-only close button pinned top-right | ✅ Done |
| Watchlisted | New tab, reached via the center FAB on the Liked Anime tab — same grid/genre-chip/column-settings layout as Liked, but reads/writes a separate persisted list. Long-press opens a menu: **Add/Edit Remarks**, **Clear Remarks** (only shown once a remark exists), and **Move to Liked** — all instant with an Undo toast, no confirmation dialogs. Cards show a top-right badge that switches from a plain bookmark to a glowing purple note icon when a remark is set. The detail popup shows the remark in a bordered "Your remark" callout below the synopsis when present | ✅ Done |
| Remarks (Watchlisted only) | A short free-text note attachable to any watchlisted anime via a dialog (`TextField`, 200 char max). Persisted in Hive on the `SavedAnime.remarks` field; cleared automatically if the anime is moved back to Liked, since remarks are watchlist-only by design | ✅ Done |
| Skeleton Loading | Anime poster images on both the Liked and Watchlisted grids show an animated shimmer placeholder (`SkeletonBox`, no external package) while `Image.network` is still loading, instead of a blank/grey flash | ✅ Done |
| Undo Toast | Shared floating toast (`showUndoToast`, defined in `notes_screen.dart` and exported for reuse, e.g. `import 'notes_screen.dart' show showUndoToast;`) — dark rounded card + purple "Undo" pill + a thin purple countdown bar along the bottom edge that drains over the toast's **3-second** visible window. Reused as-is by `liked_anime_screen.dart`, `watchlisted_screen.dart`, and `calendar_screen.dart` | ✅ Done |
| Home Screen Widget | Android-only "Today's Todos" widget, built via the `home_widget` package (v0.7.0+1). Now renders **grouped, interactive rows**: each Calendar-tab note due today gets a header row (small calendar icon + title + time, if set), one tappable checkbox row per checklist item underneath, and a thin separator row between notes. Tapping a row's checkbox toggles it straight through to the real Hive data and reflects back into the app instantly if it's open. See "Home Screen Widget" below for the full architecture and the cross-isolate caching bug that was the main blocker | ✅ Done (interactive checkboxes working; see Known Issues for one remaining native-layout regression) |

## Home Screen Widget

**Status: functionally complete.** The widget shows today's Calendar-tab todos as grouped, interactive rows and stays in sync with the app in both directions — widget → app and app → widget.

### Architecture

Native Kotlin code **never** touches the Hive box file directly — too fragile, risk of corruption from outside Dart's control. Instead:

1. A widget checkbox tap fires `TodoToggleReceiver` (a `BroadcastReceiver`), which writes a small "pending toggle" signal (`{"noteId": ..., "itemId": ...}`) into the `SharedPreferences` store `home_widget` already uses, then wakes a Dart background isolate via `HomeWidgetBackgroundIntent`, and also calls `notifyAppWidgetViewDataChanged` directly so the row redraws without waiting on the Dart round-trip.
2. The Dart background callback (`widgetBackgroundCallback` in `widget_service.dart`) wakes, reads the pending signal via `WidgetService.applyPendingToggle()`, applies it to the real `Note`/`ChecklistItem` Hive objects through `DatabaseService`, clears the signal (dedup guard — see below), then calls `refreshWidget()` again so `todo_rows` reflects the new state.
3. If the main app is alive, `applyPendingToggle()` also sends a `{'noteId', 'itemId'}` message over `IsolateNameServer` to a port the main isolate is listening on (`checklistUpdateStream` in `main.dart`), so an already-open `NoteEditorScreen` or `CalendarScreen` can reflect the change immediately too — see "Cross-screen sync" below.

This keeps Hive's binary format written only by Dart/Hive code, never raw native code — a deliberate, confirmed design decision.

### Widget → App sync, and the cross-isolate Hive caching bug

The trickiest bug in this whole feature wasn't in the toggle logic itself — it was that **`Box<Note>.get()` returns stale data across isolates.** Hive's `Box` keeps an in-memory cache after `openBox()`, and each isolate that opens the same box gets its *own separate* in-memory copy, even though both read/write the same file on disk. A `put()` from one isolate updates the file and that isolate's own cache, but never tells any other isolate's already-open `Box` handle to refresh. Since the widget's background callback and the main UI isolate are exactly two such separate isolates, the main isolate's `_syncChecklistFromHive()` was reading `true` from its cache milliseconds after the background isolate had already written `false` to disk.

Fix: `DatabaseService.getNoteByIdFresh(id)` closes and reopens the `notes` box before reading, forcing Hive to re-read from disk instead of trusting the long-lived in-memory cache. This is only called from the one place that needs a cross-isolate-fresh read (`note_editor_screen.dart`'s `_syncChecklistFromHive()`); `getNoteById()` (cached, fast) remains the default everywhere else, since close/reopen has a real cost and isn't safe to call casually from multiple places at once.

### Cross-screen sync

The live sync path is intentionally scoped to three places — **widget, Calendar tab, Note Editor** — not the Notes tab or Archived screen, since calendar reminders and regular notes are different concepts in this app:

- **Widget checkbox tapped while Note Editor is open for that note** → `checklistUpdateStream` fires → `_syncChecklistFromHive()` re-reads fresh from Hive (via `getNoteByIdFresh`) → `setState`. An item the user already toggled in the *current editing session* (`_toggledItemIds`) is never overwritten by this — the session's own pending edit always wins until it's saved.
- **Widget checkbox tapped while Calendar tab is open** → same push message → Calendar reloads its note list from a fresh Hive read.
- **App fully closed when a widget toggle happens** → Hive is still updated correctly; the relevant screen picks up the new state next time it's opened or resumed (`didChangeAppLifecycleState` also triggers a re-sync on resume, as a second safety net beyond the push message, in case the app was merely backgrounded rather than killed).
- **Note saved/edited/deleted from inside the app** → `WidgetService.refreshWidget()` is called, which rebuilds `todo_rows` from the full current note list and pushes it to the widget.

### Native redraw reliability fix

Beyond the Hive caching bug, a second, separate issue caused some app→widget updates (e.g. deleting a note from the Calendar tab) to not visibly refresh the widget even though `todo_rows` had already been correctly rewritten by Dart. `HomeWidget.updateWidget()` triggers `AppWidgetProvider.onUpdate()` on the native side, which re-calls `setRemoteAdapter(...)` — but re-supplying the same adapter intent doesn't reliably force Android to re-run the `RemoteViewsFactory`'s `onDataSetChanged()` on every OS version/launcher. The toggle path already worked because `TodoToggleReceiver` calls `notifyAppWidgetViewDataChanged` explicitly and natively, with no Dart round-trip required — but other callers of `refreshWidget()` (save, delete) only went through `updateWidget()` → `onUpdate()`, which wasn't consistently sufficient.

Fix: `TodoWidgetProvider.updateWidget()` now also calls `appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_list_view)` immediately after `setRemoteAdapter(...)`, so **every** path that calls `HomeWidget.updateWidget()` — not just the toggle-specific native call — reliably forces the ListView to refetch and rebuild via `getViewAt()`.

### Grouped row rendering

`WidgetService.refreshWidget()` builds a flat list of typed rows rather than one note per row:

- `type: "header"` — note title + formatted time (only if `reminderAt` is set; `calendarDate`-only notes show no time).
- `type: "item"` — one per checklist item (`noteId`, `itemId`, `text`, `done`). A note with **no** checklist items falls back to a single synthetic item row using the note's content (or title if content is empty) and `note.isCompleted` as its done state, so a reminder-only note (no checklist) still shows as one checkable line.
- `type: "separator"` — inserted between notes, not after the last one.

`TodoRemoteViewsFactory.getViewAt()` switches on `row.type` and inflates `todo_widget_header_row.xml`, `todo_widget_row.xml`, or `todo_widget_separator_row.xml` accordingly (`getViewTypeCount()` is `3` to match). The checkbox icon uses custom vector drawables (`todo_checkbox_checked.xml` / `todo_checkbox_unchecked.xml`) rather than `android.R.drawable.checkbox_on/off_background` — those stock drawables are legacy "background layer" assets meant to sit behind a real `CheckBox` widget's separate foreground glyph; used alone in a plain `ImageView` they render as invisible/blank on most themes, which was the cause of an earlier bug where tapping the widget checkbox visibly did nothing even though the underlying `done` value was flipping correctly in Hive.

`refreshWidget()` also now filters to `n.isCalendarReminder == true` in addition to the existing today-date check, so a regular Notes-tab note that happens to share today's date never leaks into the widget.

### Files involved

- `android/app/src/main/kotlin/com/example/remind/TodoWidgetProvider.kt` — `AppWidgetProvider`; builds the `RemoteViews`, wires `setRemoteAdapter` + `setPendingIntentTemplate` (so each row's `setOnClickFillInIntent` only needs to supply its own ids) + the native `notifyAppWidgetViewDataChanged` reliability fix described above + tap-header-to-open-app.
- `android/app/src/main/kotlin/com/example/remind/TodoToggleReceiver.kt` — `BroadcastReceiver`; writes the pending-toggle signal, wakes the Dart background callback, and nudges the widget to redraw immediately.
- `android/app/src/main/kotlin/com/example/remind/TodoRemoteViewsService.kt` — `RemoteViewsService` + `RemoteViewsFactory`; parses `todo_rows` JSON each time `onDataSetChanged()` runs, and inflates one of three row layouts per `getViewAt()` call based on `row.type`.
- `android/app/src/main/res/xml/todo_widget_info.xml` — `appwidget-provider` config (250×180dp min, 30-min OS-enforced update period floor, references `todo_widget_layout`).
- `android/app/src/main/res/layout/todo_widget_layout.xml` — outer widget shell: header text + divider + the `ListView` (`@+id/widget_list_view`) that the `RemoteViewsFactory` populates, plus an empty-state `TextView`.
- `android/app/src/main/res/layout/todo_widget_header_row.xml` — one note's header: small calendar icon, bold title, time underneath (only visible if non-empty).
- `android/app/src/main/res/layout/todo_widget_row.xml` — one checklist item row: checkbox `ImageView` + text, with strikethrough paint flags applied when `done`.
- `android/app/src/main/res/layout/todo_widget_separator_row.xml` — thin divider line between notes. **⚠️ See Known Issues — this currently uses a bare `<View>`, which this same README previously flagged as a confirmed `RemoteViews` crash class (`Class not allowed to be inflated android.view.View`); it needs to go back to a zero-height `<LinearLayout>` background trick like the original top-level divider did.**
- `android/app/src/main/res/drawable/todo_checkbox_checked.xml` / `todo_checkbox_unchecked.xml` — custom vector drawables replacing the non-rendering stock Android checkbox background drawables.
- `android/app/src/main/res/drawable/widget_background.xml` — layer-list drawable, soft purple glow ring behind a dark bordered card (unchanged from the static version).
- `lib/services/widget_service.dart` — `refreshWidget(List<Note> allNotes)` builds the grouped header/item/separator row list and pushes it via `HomeWidget.saveWidgetData`/`updateWidget`; `applyPendingToggle()` reads the pending signal, flips the right `ChecklistItem`/`Note.isCompleted` in Hive, and notifies the main isolate via `IsolateNameServer`; `widgetBackgroundCallback` is the `@pragma('vm:entry-point')` top-level entry Dart wakes into.
- `lib/services/database_service.dart` — `getNoteByIdFresh(id)` (close+reopen box, cross-isolate-safe read) alongside the existing cached `getNoteById(id)`.
- `lib/screens/note_editor_screen.dart` — `_syncChecklistFromHive()` (now reads via `getNoteByIdFresh`, not the old date-filtered `todo_rows` JSON), wired to both `checklistUpdateStream` (push) and `didChangeAppLifecycleState` (resume, as a fallback).
- `lib/screens/calendar_screen.dart` — calls `refreshWidget()` after create/delete/toggle; `_swipeDeleteNote` also cancels the note's scheduled notification before deleting.
- Called from: `main.dart` (once on cold start, after `DatabaseService.init()`), `note_editor_screen.dart` (`_saveNote`), `calendar_screen.dart` (create/toggle/delete), `widget_service.dart` itself (`applyPendingToggle`, after every widget-originated toggle).

### Known Issues / Open Items

- **Separator row uses a bare `<View>`.** This README previously documented (and the team confirmed by hitting it once already) that `RemoteViews` only supports a fixed allowlist of view classes, and a plain `<View>` throws `Class not allowed to be inflated android.view.View` at render time. `todo_widget_separator_row.xml` currently uses `<View>` for its divider line inside a `FrameLayout`. This needs to be swapped back to a zero-height `<LinearLayout>` with a background color, matching the pattern already proven safe elsewhere in this widget, before this is considered fully done.
- **Triple-toggle-per-tap, sometimes.** Logcat testing showed a single physical tap occasionally producing two or three `widgetBackgroundCallback` wake-ups in quick succession (each one correctly toggling `done` relative to the last, so an odd count nets out "correct by coincidence" but isn't reliable). The existing dedup guard in `applyPendingToggle()` (clear-signal-before-processing) only protects against the *same* signal being redelivered — it does not address the native side firing multiple distinct broadcasts for one tap. Root cause not yet isolated; suspected candidates are `TodoToggleReceiver` being invoked multiple times by the `RemoteViews` click-handling machinery itself, or `setOnClickFillInIntent` combined with `setPendingIntentTemplate` somehow double-firing on certain Android versions. Not yet fixed.
- **True realtime updates are capped by the OS.** `updatePeriodMillis` has a system-enforced floor of 30 minutes regardless of what's configured — this cannot be bypassed via the standard widget update mechanism. All of the "instant" sync described above works specifically because it's event-driven (explicit `refreshWidget()`/`notifyAppWidgetViewDataChanged()` calls triggered by real actions), not because of polling. There is currently **no** mechanism for the widget to notice on its own that a new day has started (midnight rollover) or that a reminder's time has newly arrived, without some explicit trigger (app open, note saved, checkbox tapped). Adding that would require `AlarmManager`-based scheduling (e.g. via `android_alarm_manager_plus`), which has its own battery/permission tradeoffs and has been discussed but not implemented.
- **Checklist item text round-trip bug, mentioned in earlier project notes, status unconfirmed in this stage.** An earlier known issue described checklist text round-tripping incorrectly (e.g. `"asd"` becoming `"[ ] asd"`) after an app restart. This wasn't specifically retested during the widget-sync debugging covered above — if revisiting, confirm whether it's still reproducible before assuming it's fixed or still open.

## Data & Storage

- **Storage:** Local on-device only (no login/auth, no cloud sync for now), plus a dedicated `backgrounds/` subfolder inside the app's documents directory for user-uploaded theme photos (copied in via `image_picker` + `path_provider`, never referencing the original gallery URI directly)
- **DB:** Hive (lightweight local NoSQL database for Flutter)
- **Models:**
  - `Note` (`typeId: 0`) — `id, title, content, createdAt, updatedAt, reminderAt, categoryId, isArchived, isPinned, colorValue, backgroundImagePath, isCompleted, isCalendarReminder, calendarDate, checklistItems`.
    - `content` is plain free-text only — checklist data lives in `checklistItems` instead (see `ChecklistItem` below).
    - `isCompleted` (`@HiveField(11, defaultValue: false)`) — used by the Calendar tab's checkable circle icon, and as the fallback "done" state for a calendar note with no checklist items when rendered in the widget; unrelated to individual checklist item completion.
    - `isCalendarReminder` (`@HiveField(12, defaultValue: false)`) — true for any note created via the Calendar tab's "New" flow; used to exclude these from the main Notes tab grid/list, and to **include** them (exclusively) in the home screen widget.
    - `calendarDate` (`@HiveField(13, defaultValue: null)`, nullable `DateTime`) — the calendar day a calendar-created note belongs to, **independent of `reminderAt`**. Lets a note group under the right day even with no reminder time chosen yet. Only set on calendar-created notes; regular notes leave it null.
    - `checklistItems` (`@HiveField(14, defaultValue: [])`, `List<ChecklistItem>`) — source of truth for checklist data.
  - `ChecklistItem` (`typeId: 4`) — `id` (stable `String`, NOT regenerated on edit — needed so the widget can address one specific item from outside the app via noteId+itemId), `text` (`String`), `done` (`bool`). Lives in its own file, `lib/models/checklist_item.dart` / `checklist_item.g.dart` (generated).
  - `Category` (`typeId: 1`) — `id, name, parentId, isVisible, createdAt, isArchived, backgroundImagePath` (supports nesting via parent/child relationship). `backgroundImagePath` is `@HiveField(6, defaultValue: null)`, same prefix scheme as `Note`. `isVisible` (`@HiveField(3)`) and `isArchived` (`@HiveField(5)`) both carry `defaultValue` (`true` and `false` respectively) so categories saved before either field existed don't crash on load.
  - `SavedAnime` (`typeId: 3`) — `uniqueKey, source, malId, title, imageUrl, synopsis, score, genres, listType, savedAt, remarks`. Persisted version of `Anime`, storing everything needed to redisplay a liked/watchlisted card fully offline rather than re-fetching from Jikan/AniList on every restart. `listType` ('liked' or 'watchlisted') distinguishes the two lists living in the same Hive box, since they share an identical shape — one box, two filtered views, instead of two near-identical adapters/boxes. `remarks` (`@HiveField(10, defaultValue: null)`) is a nullable `String`, only meaningfully used on watchlisted entries. Converts to/from the plain `Anime` model via `toAnime()` / `SavedAnime.fromAnime()`.
  - `HiveAnimeSource` (`typeId: 2`) — Hive-storable enum (`jikan` / `anilist`) backing `SavedAnime.source`, since plain Dart enums aren't directly storable.
- **Background image path scheme:** a single nullable `String` field on both `Note`/`Category`, prefixed to disambiguate source at render time: `"asset:assets/backgrounds/<name>.jpg"` for one of the 12 bundled presets (loaded via `Image.asset`), or `"file:<absolute path>"` for a user-uploaded photo copied into app storage (loaded via `Image.file`). Resolution helpers exist independently in `notes_screen.dart`, `note_editor_screen.dart`, and `home_screen.dart` (each renders backgrounds in a different context — card, full-screen, AppBar — so each keeps its own small resolver rather than sharing one).
- **External API:** Jikan (unofficial MyAnimeList REST API, free, no key) — used by Discover, Liked Anime, and Watchlisted. Anime *metadata* itself is fetched live from Jikan on Discover, but once liked/watchlisted it's persisted as a `SavedAnime` row so the Liked/Watchlisted tabs work fully offline and survive app restarts.
- **Likes/Watchlist persistence:** `AnimeLikeService.instance` (a `ChangeNotifier`) is the single source of truth, backed by Hive via `DatabaseService` rather than being purely in-memory. `loadFromHive()` is called once at startup (after `DatabaseService.init()`) to populate an in-memory cache (`_liked`, `_watchlisted`, `_remarks`) from Hive, so the rest of the app keeps reading those lists synchronously — no `await` needed at call sites — while every mutation (`like`, `unlike`, `moveToWatchlist`, `moveToLiked`, `removeFromWatchlist`, `setRemark`) writes straight back to Hive. Liked and Watchlisted both now survive app restarts; only the **"cards per row" grid setting** remains session-only (a layout preference, not data worth persisting).
- **Schema migrations:** adding a new `@HiveField` to any model requires the field's **`@HiveField` annotation itself** to declare a `defaultValue` (e.g. `@HiveField(7, defaultValue: false)`) — a constructor default alone (`this.isArchived = false`) does **not** make `hive_generator` emit null-safe read code. Without it, old records on disk that predate the field crash on load (`type 'Null' is not a subtype of type 'bool'`) the next time `build_runner` regenerates the adapter, because the generated `read()` does a bare cast on a missing/null value. This has bitten `Note` (`isArchived`, `isPinned`, `isCompleted`, `isCalendarReminder`, `calendarDate`, `checklistItems`), `Category` (`isVisible`, `isArchived`), and `SavedAnime.remarks` — all carry `defaultValue` for this reason. Always re-run `dart run build_runner build --delete-conflicting-outputs` after any model change. Prefer adding `defaultValue` (preserves existing data) over wiping the emulator's app data; never hand-patch `.g.dart` files directly since they're overwritten on every regen anyway. **New models** need their adapter registered in `database_service.dart`'s `init()` via `Hive.registerAdapter(...)` BEFORE any box containing that type is opened/saved to, or Hive throws.
- **Cross-isolate Hive reads are NOT automatically fresh.** A `Box`'s in-memory cache is per-isolate; a write from one isolate (e.g. the widget's background callback) does not invalidate another already-open isolate's cached `Box` handle (e.g. the main UI isolate's `DatabaseService.instance`). Code that must observe a write made by a *different* isolate needs to force a real disk re-read — see `DatabaseService.getNoteByIdFresh()` in the Home Screen Widget section above. This is a Hive-wide consideration, not specific to notes — keep it in mind if any other cross-isolate read paths are added later (e.g. if Discover/Liked/Watchlisted ever gain a background-isolate component).
- **Pre-existing data created before a field existed** does not get backfilled automatically — e.g. notes with checklists created before `checklistItems` existed will show an empty checklist the first time they're opened post-upgrade, since their checklist data was still living as old encoded lines inside `content` and nothing currently migrates that forward. No migration script has been written for this; flagged as a known gap, not yet prioritized.

## Project Structure

lib/

├── main.dart                      # App entry point. Initializes Hive + notifications, populates AnimeLikeService's cache, pushes today's todos to the Android home screen widget once on cold start (`WidgetService.refreshWidget(...)`), registers the `checklistUpdateStream`/`IsolateNameServer` port the widget's background isolate pushes toggle notifications into, then wires theme + home screen.

├── theme/

│   └── app_theme.dart             # Dark purple/lilac Material 3 theme; inputDecorationTheme is borderless/unfilled by default

├── screens/

│   ├── home_screen.dart           # Main shell — bottom nav: Notes / Discover / Liked / Calendar, notched FAB. Owns the single top AppBar shared by all tabs (left-aligned title via `titleSpacing`, no reserved `leading` slot — the Notes tab's back arrow is inlined into the title `Row` instead so all four tab titles sit flush left). On the Notes tab, AppBar actions are grid/list toggle, edit-theme (pencil) toggle, and archive. When browsing inside a themed folder, the AppBar's `flexibleSpace` paints that folder's background image + scrim behind the title/actions (resolved via its own `_resolveBackgroundImage` helper); the root Notes view never shows a background. Wrapped in `PreferredSize` since the background-aware `AppBar` is built lazily inside a `Builder`.

│   ├── notes_screen.dart          # Folder browser + notes list; instant swipe-archive (right) and swipe-delete (left), both with Undo. Toggleable grid (`MasonryGridView.count`, 2 columns)/list view. Single-select theming edit mode (`toggleEditMode`/`isEditMode`, exposed to `HomeScreen` via `GlobalKey`) — tapping a note/folder while in edit mode opens `ThemePickerSheet` immediately for just that item. Exposes `currentFolderBackgroundPath` so `HomeScreen`'s AppBar can theme itself when inside a themed folder. Calls `widget.onStateChanged` (a callback passed in from `HomeScreen`) on every folder-nav/grid-toggle/edit-mode change so the parent's AppBar reliably rebuilds. Orphaned user-uploaded background files are swept from disk on both background replacement and permanent note/folder deletion (after the 5s Undo window). Also defines the shared top-level **`showUndoToast()`** helper (dark rounded card + purple "Undo" pill + a thin draining countdown bar along the bottom, auto-dismissing after **3 seconds**) — public and reused by `liked_anime_screen.dart`, `watchlisted_screen.dart`, AND `calendar_screen.dart`. `_notesInCurrentFolder` filters out any note where `isCalendarReminder == true`, keeping calendar todos off this tab. Card-preview checklist parsing (`_parseChecklistPreview`/`_freeTextPreview`) reads `Note.checklistItems` directly instead of regexing `content`.

│   ├── note_editor_screen.dart    # Create/edit/read-only note — borderless title+body, reminder bell, word count + Undo/Redo + add-task in a keyboard-docked toolbar, drag-reorder checklist, two-layer auto-save (debounce + periodic) with duplicate-save guards, and a PopScope that auto-saves on back navigation. Renders the note's `backgroundImagePath` (if set) full-screen behind the AppBar/body/toolbar via a `Stack` + scrim. Accepts `isCalendarReminder`/`initialCalendarDate` constructor params for the Calendar tab's "New" flow. The reminder bell (`_pickReminder`) skips the date picker entirely when `_calendarDate != null`, going straight to the time picker. Checklist rows are backed by the `ChecklistItem` model (`_ChecklistItem.fromModel()`/`.toModel()` convert between the editor's UI-only wrapper and the persisted Hive object); `content` is saved as plain free-text only via `_buildFinalContent()`, with `checklistItems` saved separately via `_buildChecklistItems()`. **Listens to the global `checklistUpdateStream`** (a widget-toggle push notification from `main.dart`) and to `didChangeAppLifecycleState` resume events, both calling `_syncChecklistFromHive()` — which reads via `DatabaseService.getNoteByIdFresh()` (a cross-isolate-safe, cache-bypassing read) rather than the old date-filtered `todo_rows` JSON, so a widget-originated toggle reflects correctly here regardless of whether the note has a reminder set for today. Items the current editing session has itself toggled (`_toggledItemIds`) are never silently overwritten by an external sync.

│   ├── archived_screen.dart       # Lists archived notes (read-only preview via NoteEditorScreen(readOnly: true)) and archived folders (tap to browse contents, Unarchive button)

│   ├── discover_screen.dart       # Tinder-style anime swipe feed (Jikan API) with a horizontal genre filter chip bar, direction-fade overlay

│   ├── liked_anime_screen.dart    # Liked anime, grouped/filterable, adjustable grid columns. Long-press opens a small actions-menu dialog (Add to Watchlist / Remove from Liked) — both instant via `_moveToWatchlist`/`_removeFromLiked`, no confirmation dialogs, each backed by `showUndoToast`. Defines `_showAnimeDetailDialog` (duplicated identically in `watchlisted_screen.dart`). Grid card images use `loadingBuilder` + `SkeletonBox` for a shimmer placeholder while loading.

│   ├── watchlisted_screen.dart    # New full-screen page, pushed from the center FAB on the Liked Anime tab. Mirrors `LikedAnimeScreen`'s layout but reads/writes `AnimeLikeService`'s watchlisted list instead. Long-press opens a 2–3 item actions menu: **Add/Edit Remarks**, **Clear Remarks**, and **Move to Liked** — all instant with an Undo toast.

│   └── calendar_screen.dart       # Month calendar (`TableCalendar`). `addReminderForSelectedDay()` opens the real `NoteEditorScreen` (tagged `isCalendarReminder: true`, `initialCalendarDate` = selected day) instead of a quick-add dialog. `_notesForDay()`/`_eventLoader()` group by `note.calendarDate ?? note.reminderAt`'s date (so a no-time-set calendar todo still shows under the right day). `_loadNotes()` includes notes where `isCalendarReminder == true`. Each day's list row shows a tappable circle icon (`_toggleCompleted`, flips `Note.isCompleted` + strikethrough/grey-out), and is wrapped in a `Dismissible` (swipe-left only) calling `_swipeDeleteNote` — instant delete (cancels the note's scheduled notification first) + `showUndoToast` (imported from `notes_screen.dart`), matching the Notes tab's delete pattern minus the archive direction. `_toggleCompleted`, the create flow, and the delete flow all call `WidgetService.refreshWidget(...)` to keep the home screen widget in sync. The old in-tab "Add reminder" header button and "Add one" empty-state button were both removed — the shared FAB is the only entry point for adding a calendar todo.

├── models/

│   ├── note.dart                  # Note model — see Data & Storage above for the full current field list (`typeId: 0`)

│   ├── checklist_item.dart        # `ChecklistItem` (`typeId: 4`) — `id` (String), `text`, `done`. Source of truth for checklist data, referenced by `Note.checklistItems`.

│   ├── category.dart              # Category/folder model (`typeId: 1`) — `id, name, parentId, isVisible, isArchived, backgroundImagePath`

│   ├── anime.dart                 # Plain Dart model for Jikan anime data, includes genres

│   ├── anime_genre.dart           # Plain Dart model for a Jikan genre (malId, name)

│   └── saved_anime.dart           # Hive-persisted version of Anime — `SavedAnime` (`typeId: 3`) + the `HiveAnimeSource` enum adapter (`typeId: 2`) it depends on.

├── services/

│   ├── database_service.dart      # Hive DB singleton — CRUD for notes, categories, AND `SavedAnime`. `init()` registers ALL adapters before opening any box — `NoteAdapter`, `CategoryAdapter`, `HiveAnimeSourceAdapter`, `SavedAnimeAdapter`, `ChecklistItemAdapter` (registered before the `notes` box opens, since `Note` embeds `List<ChecklistItem>`). Exposes `getNoteById(id)` (cached, fast) and `getNoteByIdFresh(id)` (closes + reopens the `notes` box to force a real disk read, bypassing this isolate's in-memory cache — needed specifically for cross-isolate reads after the widget's background callback writes a change). Also exposes `getSavedAnime(listType)`, `saveSavedAnime()`, `deleteSavedAnime()`, `isSavedAnime()`, and `getSavedAnimeEntry()`.

│   ├── notification_service.dart  # Schedules/cancels local notifications for note reminders

│   ├── ai_suggestion_service.dart # Local rule-based reminder time suggestion from note text

│   ├── anime_api_service.dart     # Fetches anime + genre data from the Jikan REST API

│   ├── anime_like_service.dart    # `ChangeNotifier` singleton — Hive-backed (via `DatabaseService`), so both liked AND watchlisted lists survive app restarts.

│   ├── background_image_service.dart # Singleton handling theme background images — picks from gallery via `image_picker`, copies into a permanent `backgrounds/` folder, and deletes previously-uploaded files when replaced/owner deleted.

│   └── widget_service.dart        # `WidgetService.refreshWidget(List<Note> allNotes)` — filters to today's Calendar-tab notes (`isCalendarReminder == true` + date match), builds grouped header/item/separator rows for the Android home screen widget, pushes via `home_widget`'s `saveWidgetData`/`updateWidget`. `applyPendingToggle()` reads the native side's pending-toggle signal, flips the right Hive data, and notifies the main isolate via `IsolateNameServer` if it's listening. `widgetBackgroundCallback` is the top-level `@pragma('vm:entry-point')` entry point the widget wakes Dart into. Called from `main.dart` (cold start) and `calendar_screen.dart`/`note_editor_screen.dart` (every relevant mutation).

└── widgets/

    ├── theme_picker_sheet.dart    # `showThemePickerSheet()` — bottom sheet for choosing a note/folder background.

    └── skeleton_loader.dart       # `SkeletonBox` — shimmer-style placeholder used as the `loadingBuilder` for anime poster images.

android/app/src/main/

├── kotlin/com/example/remind/

│   ├── MainActivity.kt            # Standard Flutter MainActivity (unmodified)

│   ├── TodoWidgetProvider.kt      # `AppWidgetProvider` for the home screen widget — builds `RemoteViews`, wires `setRemoteAdapter`/`setEmptyView`/`setPendingIntentTemplate`, forces `notifyAppWidgetViewDataChanged` after every adapter (re)bind for reliable redraws, wires tap-header-to-open-app via a launch `PendingIntent`.

│   ├── TodoToggleReceiver.kt      # `BroadcastReceiver` for a tapped checkbox row — writes the pending-toggle signal into `SharedPreferences`, wakes the Dart background callback via `HomeWidgetBackgroundIntent`, and directly calls `notifyAppWidgetViewDataChanged` for an immediate native-side redraw nudge.

│   └── TodoRemoteViewsService.kt  # `RemoteViewsService` + `RemoteViewsFactory` — parses the grouped `todo_rows` JSON on every `onDataSetChanged()`, and inflates one of three row layouts per `getViewAt()` based on `row.type` (`header` / `item` / `separator`).

├── res/xml/todo_widget_info.xml   # Widget metadata — min size, update period (OS-floored at 30 min regardless of value), initial layout reference.

├── res/layout/todo_widget_layout.xml      # Outer widget shell — header text, divider, the `ListView` the factory populates, empty-state text.

├── res/layout/todo_widget_header_row.xml  # One note's header row — calendar icon, title, time (if set).

├── res/layout/todo_widget_row.xml         # One checklist item row — checkbox `ImageView` + text, strikethrough when done.

├── res/layout/todo_widget_separator_row.xml # Divider row between notes. ⚠️ Currently uses a bare `<View>` — see Known Issues, this needs fixing back to the zero-height-`LinearLayout` pattern.

├── res/drawable/widget_background.xml     # Layer-list drawable — purple glow ring behind a dark bordered card.

├── res/drawable/todo_checkbox_checked.xml   # Custom vector drawable — filled checkbox state.

├── res/drawable/todo_checkbox_unchecked.xml # Custom vector drawable — outline checkbox state.

├── res/drawable/todo_bullet.xml   # Small purple oval, currently unused leftover from the static-widget stage.

└── AndroidManifest.xml            # Registers `TodoWidgetProvider` (with `@xml/todo_widget_info` metadata) and `TodoToggleReceiver` as a `<receiver>`.

Note: categories_screen.dart has been removed — folder browsing is now built directly into notes_screen.dart.

## Background Assets

`assets/backgrounds/` contains 12 bundled preset textures (3:4 portrait, ~600×800px, JPEG, each under ~50KB), declared in `pubspec.yaml` under `flutter: assets:`. Filenames (referenced verbatim in `kPresetBackgroundFiles` in `theme_picker_sheet.dart`):

```
dusty_blue.jpg      sage_grain.jpg       terracotta_wash.jpg  lavender_blur.jpg
cream_paper.jpg     charcoal_dots.jpg    blush_gradient.jpg   mustard_lines.jpg
teal_blur.jpg       coral_wash.jpg       stone_grain.jpg      plum_gradient.jpg
```

If adding more presets later, drop the file into this folder and add its base filename (no extension) to `kPresetBackgroundFiles`.

## Tech Stack

- **Framework:** Flutter (stable channel)
- **Platforms:** Android, iOS (Windows dev machine — iOS builds require macOS/cloud Mac service later)
- **State management:** `setState` + a couple of `ChangeNotifier` singletons (`AnimeLikeService`) for cross-tab live updates. May move to Riverpod/Bloc as complexity grows.
- **Local DB:** Hive (notes, categories, persisted liked/watchlisted anime, and structured checklist items)
- **Notifications:** `flutter_local_notifications` + `timezone`
- **Calendar:** `table_calendar`
- **Networking:** `http` (used by `AnimeApiService`)
- **Grid layout:** `flutter_staggered_grid_view` (powers the notes list's 2-column masonry grid)
- **Image picking/storage:** `image_picker` (gallery photo selection for custom backgrounds) + `path_provider` (locating app documents directory to permanently store copied uploads)
- **Home screen widget:** `home_widget: ^0.7.0+1` — Android-only so far; pairs Dart-side `saveWidgetData`/`updateWidget`/background-isolate callbacks with native Kotlin (`AppWidgetProvider` + `BroadcastReceiver` + `RemoteViewsService` + XML layouts/drawables) for fully interactive, two-way-synced checklist rows.
- **Design system:** Material 3, dark purple `ColorScheme` defined in `theme/app_theme.dart`; app-wide `inputDecorationTheme` is borderless and unfilled — boxed inputs (e.g. the New Folder dialog) opt in explicitly per-field with their own `border:`
- **Removed dependency:** `flutter_colorpicker` was added for the text-color feature and then removed along with the feature itself — it should not appear in `pubspec.yaml` anymore.

## Getting Started (Standard Flutter)

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

Requires Flutter SDK installed and a connected device/emulator. Run `flutter doctor` to verify your environment.

### Windows-specific setup
Flutter plugin builds require symlink support on Windows. If `flutter run` fails with a symlink error, enable Developer Mode:
```bash
start ms-settings:developers
```

### Android-specific setup
- `flutter_local_notifications` requires core library desugaring — already configured in `android/app/build.gradle.kts`.
- Required manifest permissions (already added): `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`, `RECEIVE_BOOT_COMPLETED`, `INTERNET`, `READ_MEDIA_IMAGES` (Android 13+ gallery access for `image_picker`), `READ_EXTERNAL_STORAGE` (capped at `maxSdkVersion="32"`, fallback for older API levels).
- If notifications silently don't fire: check **Settings → Apps → Remind → Notifications** (must be On), **Battery** (set to Unrestricted), and **Permissions → Alarms & Reminders** (must be Allowed).
- If the gallery picker silently fails or crashes on first use, double check the two media permissions above are present in `AndroidManifest.xml`.
- Camera (live photo capture) and microphone (voice dictation) permissions are **still not** added — only gallery *selection* was added for background theming; live camera capture remains explicitly deferred.
- A `NetworkCapability ... out of range` crash from `com.google.android.gms.persistent` in logcat is a Google Play Services system process issue on some emulator images, unrelated to this app's code — safe to ignore.
- **Home screen widget setup:** any change to a file under `android/app/src/main/{kotlin,res}/` requires a **full rebuild and reinstall** — `flutter clean && flutter run` (or `flutter clean && flutter pub get && flutter run`). Hot reload and hot restart only affect the Dart VM inside an already-running process; they do **not** recompile or redeploy native Android/Kotlin code, drawables, or layout XML, no matter how minor the change. After a successful rebuild, **remove the existing widget instance from the home screen and re-add it fresh** — Android caches widget layouts/factories per-instance and won't always pick up a layout or drawable-id change on an already-placed widget.
- **`RemoteViews` only supports a fixed allowlist of view classes** (`LinearLayout`, `TextView`, `ImageView`, `Button`, etc.) — a plain `<View>` (e.g. used as a quick divider) throws `Class not allowed to be inflated android.view.View` at render time, surfacing as "Can't load widget" on the home screen. Always use a zero-height `<LinearLayout>` with a background color for divider lines in widget layouts instead. (Currently violated in `todo_widget_separator_row.xml` — see Known Issues above.)
- **Widget update period is OS-floored at 30 minutes**, regardless of what `updatePeriodMillis` is set to in `todo_widget_info.xml` — Android will not allow a standard widget provider to poll faster than this for battery reasons, and no app-level configuration can override it. All "instant" sync in this app comes from explicit event-driven calls (`refreshWidget()`, `notifyAppWidgetViewDataChanged()`), not from shortening this value.
- **A `Box`'s in-memory cache is per-isolate, not shared.** A write from one isolate (e.g. the widget's background callback) is not automatically visible to another isolate's already-open `Box` handle (e.g. the main UI isolate) — `box.get()` can return stale data indefinitely until that isolate's box is reopened. See `DatabaseService.getNoteByIdFresh()` and the Home Screen Widget section above.
- `home_widget: 0.7.0+1`'s `HomeWidget.updateWidget(...)` takes a `name:` parameter (the Android provider class name as a String), not `android:` — easy to assume otherwise from older docs/examples.

## Notes for AI Assistants

- This is a **learning project** — the developer is new to Flutter, so prefer clear, well-commented code and step-by-step explanations over terse advanced patterns. The developer's strongly preferred working style across sessions: exact, copy-pasteable find-and-replace code blocks with precise, Ctrl+F-able `old_str`/`new_str` text — no unsolicited explanations or design discussions unless they ask.
- Stick to **lowercase_with_underscores** for file/package names per Dart conventions.
- No authentication/login system yet — all data is local-only by design (for now).
- When adding new features, follow the existing `screens/ widgets/ models/ services/ theme/` folder convention.
- The dark purple theme (`AppTheme.lightTheme` — name is legacy, the theme itself is now dark) should be reused, not redefined, in new screens/widgets. Avoid hardcoded colors like `Colors.black87` or `Colors.grey.shadeXXX` in new code — they don't adapt to the dark palette. Prefer `Theme.of(context).colorScheme.*` or `Colors.white` / `Colors.white70` / `Colors.white38` for text on dark surfaces. **Exception:** note/folder cards and the themed editor intentionally use literal `Colors.black87`/`Colors.white`/etc. for text drawn directly on top of a colored card or background image.
- `DatabaseService.instance` is the single source of truth for all Hive reads/writes — never open Hive boxes directly in screens. **Exception:** `getNoteByIdFresh()` itself closes/reopens the `notes` box internally, but this is encapsulated inside `DatabaseService` — callers still never touch a `Box` directly.
- `NotesScreenState` (public) exposes `showAddOptions()`, `goBack()`, `isAtRoot`, `currentFolderName`, `currentFolderBackgroundPath`, `isGridView`/`toggleGridView()`, `isEditMode`/`toggleEditMode()`, and `openArchived()` — all driven by `HomeScreen` via `GlobalKey<NotesScreenState>`. `CalendarScreenState` (public) exposes `addReminderForSelectedDay()` the same GlobalKey-driven way.
- A note's `categoryId` is set **once**, either from the existing note (editing) or from `initialCategoryId` (the folder it was created inside) — there's no category dropdown in the editor; folder placement is implicit from where "New Note" was tapped. Calendar-created notes don't get a `categoryId` at all (always null) since they're not meant to live inside the Notes folder structure.
- **Checklist items are a proper Hive model — NOT text encoded inside `content`.** `ChecklistItem` (`typeId: 4`) has a stable string `id`, `text`, `done`. `Note.checklistItems` (`@HiveField(14)`) is the source of truth; `note_editor_screen.dart`'s `_buildChecklistItems()` builds the persisted list on save, `_ChecklistItem.fromModel()` rebuilds the editor's UI-wrapper list on load. `content` is plain free-text only — there is no parsing step left for checklist lines inside it. `notes_screen.dart`'s card-preview functions match this (`_parseChecklistPreview(Note note)` / `_freeTextPreview(Note note)`, both take the whole `Note` rather than a content string). **An earlier-reported round-trip bug (checklist text coming back wrong after restart) has not been specifically reconfirmed during this widget-sync work — verify it's still reproducible before assuming it's resolved or still open.**
- The `id` field on the editor's UI-only `_ChecklistItem` class is a stable `String` (format: `"<microsecondsSinceEpoch>_<counter>"`) specifically so the home screen widget can address one specific checklist item from outside the app (a widget tap only has noteId+itemId to go on, no concept of "current list position"). `_taskPlaceholderFor` hashes the string (`id.hashCode.abs() % length`) rather than assuming an `int` id.
- **Undo/Redo (editor) is text-only and intentionally separate from auto-save's own state.** `_undoStack`/`_redoStack` hold `_EditSnapshot(title, content)` pairs, pushed via a 500ms debounce distinct from auto-save's 1.2s debounce. Checklist and reminder state are NOT part of this history; only title/content text.
- **Pin/Color picker and the slash command menu were both removed from the editor UI.** `Note.isPinned` and `Note.colorValue` remain real Hive fields and `_saveNote()` preserves whatever value an existing note already had. Re-adding pin/color UI is a known possible follow-up — confirm with the developer before doing so.
- Swipe actions in `notes_screen.dart` (archive on right swipe, delete on left swipe, for both notes and folders) are **instant, not timer-deferred**. `calendar_screen.dart` has its own swipe-left-to-delete (`_swipeDeleteNote`), reusing `notes_screen.dart`'s `showUndoToast` via `import 'notes_screen.dart' show showUndoToast;` rather than duplicating the styling — but does NOT offer archive (swipe-right), since that wasn't requested for the Calendar tab.
- **The shared `showUndoToast()` auto-dismiss window is 3 seconds.** **Note:** the note/folder background-image cleanup delays in `notes_screen.dart` still use their own separate 5-second `Future.delayed` timers, gated independently of the toast — known mismatch, not yet resolved, unrelated to the widget-sync work in this stage.
- **Background theming is single-select, not multi-select.** Don't reintroduce Set-based multi-selection without confirming with the developer first.
- `NoteEditorScreen` has a `readOnly` constructor flag AND `isCalendarReminder`/`initialCalendarDate` (for the Calendar tab's "New" flow only — both default to `false`/`null` so existing call sites from `notes_screen.dart` are unaffected).
- **Bold/Italic and Text Color were both built, then fully removed.** Treat resurrecting either as a fresh scoping conversation.
- Image attachments (camera capture / inline photos) and voice-to-text dictation remain **explicitly deferred**.
- `AiSuggestionService` is fully offline/local — no API key, no network call.
- `NoteEditorScreen` has **two auto-save layers** (1.2s debounce + 10s periodic `Timer.periodic`).
- **Back navigation also auto-saves**, via `PopScope(canPop: false, ...)`.
- `notes_screen.dart`'s top-of-screen header lives in `HomeScreen`'s shared AppBar, not in `NotesScreen`'s own body.
- `AnimeLikeService.instance` remains the single source of truth for liked/watchlisted anime and remarks — entirely untouched by the widget-sync work.
- **Calendar tab's in-row "Add reminder" header button and the empty-state "Add one" button were both removed at the developer's request** — the shared bottom FAB is the sole entry point for adding a calendar todo. Don't reintroduce either button without checking first.
- **Home screen widget is functionally complete for its core scope** (grouped interactive checklist rows, two-way sync between widget and app). It is **not** "realtime" in the sense of reacting to the passage of time on its own (midnight rollover, a reminder's time arriving) — only to explicit actions (app save/delete/toggle, or a widget tap). See the Known Issues subsection under Home Screen Widget for the open separator-layout regression and the occasional triple-toggle-per-tap issue before assuming this feature needs no further work. Don't restart the architecture (signal-via-SharedPreferences + Dart background callback, native code never writes Hive directly) — it's deliberate and working; any further work should build on it, not replace it.
- Jikan (`https://api.jikan.moe/v4`) is a free, unofficial, rate-limited public API — batch/throttle requests, don't hammer it.