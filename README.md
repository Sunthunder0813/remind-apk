# Remind

A smart, AI-assisted notes and reminder app built with **Flutter**, targeting **Android & iOS**.

## App Concept

Remind is a notes/organizer app where users create notes with optional reminders, organize them into **nested folders** (browsed like iOS Notes — tap to drill in, swipe right to archive, swipe left to delete, both instant with Undo), view everything on a **calendar**, and get **AI-suggested reminder times** as they type. Notes support **drag-to-reorder checklists** and **per-item Undo/Redo** on title/content text. The notes list itself is a **toggleable grid/list view** with colorful auto-tinted cards, and both notes and folders can be given a **custom background image theme** (bundled presets or user-uploaded photos) via a single-select edit mode. A dark purple/lilac theme runs throughout, plus an **Android home screen widget** showing today's calendar todos (built, mid-upgrade — see "Home Screen Widget" below). Also includes a **Discover** tab — a Tinder-style swipe feed for browsing anime via the free Jikan API, filterable by genre — a **Liked Anime** tab for reviewing what you've swiped right on, and a **Watchlisted** tab (reached via the center FAB on Liked Anime) for anime moved out of Liked with an optional personal **remark** attached to each entry. Both lists persist across app restarts via Hive.

The **Calendar** tab now also doubles as a lightweight todo list: tapping a day and then the shared center FAB opens the real note editor (not a dialog), pre-tagged to that day, so calendar-created reminders are full notes with optional checklists — kept separate from the main Notes tab.

## Core Features

| Feature | Description | Status |
|---|---|---|
| Notes / Folders | Notion-style borderless editor (title + body, no boxed fields), nested folders browsed by tapping in/out | ✅ Done |
| Notes List Layout | Toggleable **2-column masonry grid** (default, via `flutter_staggered_grid_view`) or **single-column list**, switched via an icon in the top AppBar. Folders and notes render as flat, rounded, colored cards (no `Card`/`ListTile` chrome) — folders show a fixed dark slate tile, notes are tinted from a 6-color pastel palette hashed deterministically off the note's `id` (or its explicit `colorValue`/`backgroundImagePath` if set), so colors stay stable across rebuilds. Note cards show an inline checklist preview (up to 4 items + "+N more") when the note has tasks, or a free-text preview otherwise, plus a relative "Edited ..." timestamp. **Calendar-created notes are excluded from this list** (see Calendar Todos below) | ✅ Done |
| Background Theming | Notes and folders can each be given a **custom background image** — either one of 12 bundled preset textures (`assets/backgrounds/`) or a user-uploaded photo (via `image_picker`, copied into permanent app storage so it survives gallery changes). Applied via a dedicated **single-select edit mode**: tap the pencil icon in the AppBar, tap exactly one note or folder, the theme picker bottom sheet opens immediately, pick a background (or "Remove background" if one's already set) and it's applied instantly — no multi-select, no separate "Apply" step. Themed cards get a dark gradient scrim for text legibility and flip their text/icon colors to white. The **note editor screen** also renders the note's background full-screen (behind the AppBar, body, and keyboard toolbar, with the same scrim) when opened. When **browsing inside a themed folder**, the top AppBar itself shows that folder's background + scrim (title/icons only — the note grid underneath stays plain); the root "Notes" view never shows a background. User-uploaded background files are cleaned up from disk both when a background is replaced and when its note/folder is permanently deleted (after the 5s Undo window expires) | ✅ Done |
| Archive | Swipe a note or folder **right** to archive (instant, with Undo); archived folders can still be opened to browse their contents; archived notes open in a true read-only mode (same layout, nothing editable). Swipe gestures are disabled while edit mode (theming) is active, to avoid conflicting with the tap-to-theme gesture | ✅ Done |
| Delete | Swipe a note or folder **left** to delete (instant, with Undo that restores from Hive, not from a pending timer) | ✅ Done |
| Checklists | Type `- task` and press Enter (or tap "Add a task" in the keyboard toolbar) to turn a line into a checkbox; drag the handle (floats in the right gutter) to reorder; swipe a task left to remove it; new tasks auto-focus their text field immediately so you can start typing without an extra tap; empty rows show a rotating realistic placeholder (e.g. "e.g. Buy groceries") instead of a generic "Task" label. **Checklist data is now a structured Hive field (`Note.checklistItems`, a `List<ChecklistItem>`), not text encoded inside `content`** — see Data & Storage below. ⚠️ **Known bug, currently being debugged:** checklist item text round-trips incorrectly after closing and reopening the app — a typed task like `"asd"` comes back as `"[ ] asd"` on reload, on BOTH calendar-created and regular Notes-tab notes. Root cause not yet isolated; suspect either the generated `ChecklistItemAdapter` (`checklist_item.g.dart`) or a stale/duplicate adapter registration in `database_service.dart`. Next debugging step was to inspect `checklist_item.g.dart` directly | 🐛 Bug in progress |
| Undo / Redo (Editor) | Title and content text support **Undo/Redo**, independent of auto-save. Snapshots are pushed on a 500ms typing-pause debounce (not per-keystroke), shown as two icon buttons in the keyboard toolbar (next to the word count, separated by a vertical divider) that grey out and disable themselves when there's nothing to act on. Scoped to text only — checklist and reminder changes are not part of the undo history | ✅ Done |
| Reminders | Bell icon next to the title opens the date+time picker; once set, shows as a small purple pill with change/clear. **On calendar-created notes, the date is implicit** (see Calendar Todos) — tapping the bell skips straight to the time picker instead of re-asking for a date already chosen on the Calendar tab | ✅ Done |
| Calendar Todos (Editor Integration) | Tapping a calendar day, then the shared center FAB, now opens the **real `NoteEditorScreen`** (not a dialog) via `addReminderForSelectedDay()`. The note is tagged `isCalendarReminder: true` and stamped with `calendarDate` (the selected day) so it groups under that day on the Calendar tab even with no reminder time set — the reminder bell starts empty by design; the user opts in to a time. These notes are **excluded from the main Notes tab** (filtered out of `_notesInCurrentFolder` in `notes_screen.dart`). Calendar's day list now also supports **swipe-left-to-delete with Undo** (matching the Notes tab's pattern, reusing the same `showUndoToast` helper) — archive is intentionally not offered here | ✅ Done |
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
| Undo Toast | Shared floating toast (`showUndoToast`, defined in `notes_screen.dart` and exported for reuse, e.g. `import 'notes_screen.dart' show showUndoToast;`) — dark rounded card + purple "Undo" pill + a thin purple countdown bar along the bottom edge that drains over the toast's **3-second** visible window. Reused as-is by `liked_anime_screen.dart`, `watchlisted_screen.dart`, and now `calendar_screen.dart` | ✅ Done |
| Home Screen Widget | Android-only "Today's Todos" widget showing today's calendar reminders, built via the `home_widget` package (v0.7.0+1). Currently renders as a single static text block (one line per todo, `•`/`✓` prefix) inside a custom rounded purple-bordered card layout (`todo_widget_layout.xml` + `widget_background.xml` layer-list drawable), refreshed via `WidgetService.refreshWidget()` called after every relevant Calendar/note mutation and once on app cold-start in `main.dart`. Tapping the widget opens the app (`HomeWidgetLaunchIntent` wired in `TodoWidgetProvider.kt`). **Mid-upgrade to per-item interactive checkboxes** — see "Home Screen Widget — In Progress" below for the architecture being built | 🚧 In progress (static version working; interactive checkboxes not yet built) |

## Home Screen Widget — In Progress

The static widget (single text block, tap-to-open-app) is built and confirmed working after resolving an early `RemoteViews` crash (`Class not allowed to be inflated android.view.View` — a literal `<View>` divider isn't on `RemoteViews`' allowed-class list; replaced with a zero-height `<LinearLayout>`, which is allowed).

**Goal:** let the user check off a calendar note's checklist items directly from the widget, without opening the app, while keeping the change synced back into the app's real Hive data.

**Agreed architecture** (confirmed with the developer before building): native Kotlin code must **never** touch the Hive box file directly — too fragile, risk of corruption from outside Dart's control. Instead:

1. Widget tap (in a future `RemoteViewsService`-backed row) fires a `BroadcastReceiver` in native Kotlin.
2. That receiver writes a small "pending toggle" signal (noteId + itemId) into the `SharedPreferences` store `home_widget` already uses for `todo_list`.
3. A Dart-side background callback (`home_widget`'s `registerBackgroundCallback`) wakes up, reads the pending signal, applies it safely to the real `Note`/`ChecklistItem` Hive objects via `DatabaseService`, then re-renders/pushes the widget's display data.

This was chosen specifically so Hive's binary format is only ever written by Dart/Hive code, never raw native code.

**Stages, in order (Stages 1–2 complete, 3–4 not started):**

- **Stage 1 — ✅ Done.** Calendar's `addReminderForSelectedDay()` now opens the real `NoteEditorScreen` instead of a quick-add dialog, tagged `isCalendarReminder: true` with `calendarDate` set to the selected day. Reminder bell starts empty; date is implicit via `calendarDate`, not `reminderAt`.
- **Stage 2 — ✅ Done (but see the open bug above).** Checklist items became a proper Hive model (`ChecklistItem`, `typeId: 4`, fields `id` (String), `text`, `done`) stored on `Note.checklistItems` (`@HiveField(14)`, a `List<ChecklistItem>`). This is now the **source of truth** — `Note.content` is plain free-text only; the old `- [ ] task` / `- [x] task` line-encoding inside `content` was removed entirely from the editor's read/write path. The editor's internal `_ChecklistItem` UI class (holds `TextEditingController`/`FocusNode`) wraps/unwraps the persisted model via `.fromModel()`/`.toModel()`, keeping the same stable string `id` across edits (needed later so the widget can address one specific item from outside the app). `notes_screen.dart`'s card-preview parsing (`_parseChecklistPreview`/`_freeTextPreview`) was updated to read `note.checklistItems` directly instead of regexing `content`.
- **Stage 3 — Not started.** Render the widget's checklist as real per-item interactive rows (not one static text blob) via a `RemoteViewsService` + `RemoteViewsFactory` (Android's pattern for a "ListView"-style widget with independently clickable rows).
- **Stage 4 — Not started.** Wire tap-to-toggle: a `BroadcastReceiver` registered for a custom action, reading the tapped row's noteId+itemId, writing the pending-toggle signal, and triggering the Dart background callback described above to actually flip `ChecklistItem.done` in Hive and refresh the widget.

### Files already in place for the widget (static version)

- `android/app/src/main/kotlin/com/example/remind/TodoWidgetProvider.kt` — `AppWidgetProvider` subclass, reads `todo_list` from `HomeWidgetPlugin.getData(context)`, populates `RemoteViews`, wires `HomeWidgetLaunchIntent.getActivity(...)` to the whole card (`R.id.widget_root`) for tap-to-open.
- `android/app/src/main/res/xml/todo_widget_info.xml` — `appwidget-provider` config (250×180dp min, 30-min update period, references `todo_widget_layout`).
- `android/app/src/main/res/layout/todo_widget_layout.xml` — the widget's visual layout: header row (clock emoji + "Today's Todos" title in `#E3A2EE`), a 1dp divider (`<LinearLayout>`, NOT `<View>` — see bug note above), and the todo-list `TextView` (`@+id/widget_todo_list`).
- `android/app/src/main/res/drawable/widget_background.xml` — layer-list drawable faking a soft purple glow: an outer semi-transparent purple rounded rect, inset by an opaque dark card with a crisp purple stroke border.
- `android/app/src/main/res/drawable/todo_bullet.xml` — a small purple oval, currently unused (kept as a building block for Stage 3's per-row bullet, if needed once rows are real `RemoteViews` items instead of plain text glyphs).
- `lib/services/widget_service.dart` — `WidgetService.refreshWidget(List<Note> allNotes)`: filters to today's notes (by `reminderAt`'s date), builds the `•`/`✓`-prefixed text block, calls `HomeWidget.saveWidgetData<String>('todo_list', text)` then `HomeWidget.updateWidget(name: 'TodoWidgetProvider')`. **Note:** the named parameter is `name:`, not `android:`, for `home_widget: 0.7.0+1` — this caught us once already (an `undefined_named_parameter` error); don't "fix" it back to `android:` if revisiting this file.
- Called from: `main.dart` (once on cold start, after `DatabaseService.init()`), `calendar_screen.dart` (after creating/toggling/deleting a todo).

### Known non-blocking warnings (safe to ignore)

- `WARNING: Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): home_widget` — a forward-looking deprecation notice from Flutter about `home_widget`'s build setup, not a current build failure.
- `warning: [options] source value 8 is obsolete...` (Java 8 obsolete warnings during Gradle build) — also non-blocking.
- `hive_generator` analyzer-version-mismatch warning during `build_runner` — cosmetic, doesn't stop the build from succeeding.

## Data & Storage

- **Storage:** Local on-device only (no login/auth, no cloud sync for now), plus a dedicated `backgrounds/` subfolder inside the app's documents directory for user-uploaded theme photos (copied in via `image_picker` + `path_provider`, never referencing the original gallery URI directly)
- **DB:** Hive (lightweight local NoSQL database for Flutter)
- **Models:**
  - `Note` (`typeId: 0`) — `id, title, content, createdAt, updatedAt, reminderAt, categoryId, isArchived, isPinned, colorValue, backgroundImagePath, isCompleted, isCalendarReminder, calendarDate, checklistItems`.
    - `content` is now **plain free-text only** — the old `- [ ] task` line-encoding was fully removed; checklist data lives in `checklistItems` instead (see `ChecklistItem` below).
    - `isCompleted` (`@HiveField(11, defaultValue: false)`) — used by the Calendar tab's checkable circle icon; unrelated to checklist item completion.
    - `isCalendarReminder` (`@HiveField(12, defaultValue: false)`) — true for any note created via the Calendar tab's "New" flow; used to exclude these from the main Notes tab grid/list.
    - `calendarDate` (`@HiveField(13, defaultValue: null)`, nullable `DateTime`) — the calendar day a calendar-created note belongs to, **independent of `reminderAt`**. Lets a note group under the right day even with no reminder time chosen yet. Only set on calendar-created notes; regular notes leave it null.
    - `checklistItems` (`@HiveField(14, defaultValue: [])`, `List<ChecklistItem>`) — **source of truth** for checklist data (see Checklists bug note above for the currently-open round-trip issue).
  - `ChecklistItem` (`typeId: 4`, new in this stage) — `id` (stable `String`, NOT regenerated on edit — needed so the eventual widget can address one specific item from outside the app), `text` (`String`), `done` (`bool`). Lives in its own file, `lib/models/checklist_item.dart` / `checklist_item.g.dart` (generated).
  - `Category` (`typeId: 1`) — `id, name, parentId, isVisible, createdAt, isArchived, backgroundImagePath` (supports nesting via parent/child relationship). `backgroundImagePath` is `@HiveField(6, defaultValue: null)`, same prefix scheme as `Note`. `isVisible` (`@HiveField(3)`) and `isArchived` (`@HiveField(5)`) both carry `defaultValue` (`true` and `false` respectively) so categories saved before either field existed don't crash on load.
  - `SavedAnime` (`typeId: 3`) — `uniqueKey, source, malId, title, imageUrl, synopsis, score, genres, listType, savedAt, remarks`. Persisted version of `Anime`, storing everything needed to redisplay a liked/watchlisted card fully offline rather than re-fetching from Jikan/AniList on every restart. `listType` ('liked' or 'watchlisted') distinguishes the two lists living in the same Hive box, since they share an identical shape — one box, two filtered views, instead of two near-identical adapters/boxes. `remarks` (`@HiveField(10, defaultValue: null)`) is a nullable `String`, only meaningfully used on watchlisted entries. Converts to/from the plain `Anime` model via `toAnime()` / `SavedAnime.fromAnime()`.
  - `HiveAnimeSource` (`typeId: 2`) — Hive-storable enum (`jikan` / `anilist`) backing `SavedAnime.source`, since plain Dart enums aren't directly storable.
- **Background image path scheme:** a single nullable `String` field on both `Note`/`Category`, prefixed to disambiguate source at render time: `"asset:assets/backgrounds/<name>.jpg"` for one of the 12 bundled presets (loaded via `Image.asset`), or `"file:<absolute path>"` for a user-uploaded photo copied into app storage (loaded via `Image.file`). Resolution helpers exist independently in `notes_screen.dart`, `note_editor_screen.dart`, and `home_screen.dart` (each renders backgrounds in a different context — card, full-screen, AppBar — so each keeps its own small resolver rather than sharing one).
- **External API:** Jikan (unofficial MyAnimeList REST API, free, no key) — used by Discover, Liked Anime, and Watchlisted. Anime *metadata* itself is fetched live from Jikan on Discover, but once liked/watchlisted it's persisted as a `SavedAnime` row so the Liked/Watchlisted tabs work fully offline and survive app restarts.
- **Likes/Watchlist persistence:** `AnimeLikeService.instance` (a `ChangeNotifier`) is the single source of truth, backed by Hive via `DatabaseService` rather than being purely in-memory. `loadFromHive()` is called once at startup (after `DatabaseService.init()`) to populate an in-memory cache (`_liked`, `_watchlisted`, `_remarks`) from Hive, so the rest of the app keeps reading those lists synchronously — no `await` needed at call sites — while every mutation (`like`, `unlike`, `moveToWatchlist`, `moveToLiked`, `removeFromWatchlist`, `setRemark`) writes straight back to Hive. Liked and Watchlisted both now survive app restarts; only the **"cards per row" grid setting** remains session-only (a layout preference, not data worth persisting).
- **Schema migrations:** adding a new `@HiveField` to any model requires the field's **`@HiveField` annotation itself** to declare a `defaultValue` (e.g. `@HiveField(7, defaultValue: false)`) — a constructor default alone (`this.isArchived = false`) does **not** make `hive_generator` emit null-safe read code. Without it, old records on disk that predate the field crash on load (`type 'Null' is not a subtype of type 'bool'`) the next time `build_runner` regenerates the adapter, because the generated `read()` does a bare cast on a missing/null value. This has now bitten `Note` (`isArchived`, `isPinned`, `isCompleted`, `isCalendarReminder`, `calendarDate`, `checklistItems`), `Category` (`isVisible`, `isArchived`), and `SavedAnime.remarks` — all carry `defaultValue` for this reason. Always re-run `dart run build_runner build --delete-conflicting-outputs` after any model change. Prefer adding `defaultValue` (preserves existing data) over wiping the emulator's app data; never hand-patch `.g.dart` files directly since they're overwritten on every regen anyway. **New models** (like `ChecklistItem`) need their adapter registered in `database_service.dart`'s `init()` via `Hive.registerAdapter(...)` BEFORE any box containing that type is opened/saved to, or Hive throws.
- **Pre-existing data created before a field existed** does not get backfilled automatically — e.g. notes with checklists created before `checklistItems` existed will show an empty checklist the first time they're opened post-upgrade, since their checklist data was still living as old encoded lines inside `content` and nothing currently migrates that forward. No migration script has been written for this; flagged as a known gap, not yet prioritized.

## Project Structure

lib/

├── main.dart                      # App entry point. Initializes Hive + notifications, populates AnimeLikeService's cache, pushes today's todos to the Android home screen widget once on cold start (`WidgetService.refreshWidget(...)`), then wires theme + home screen.

├── theme/

│   └── app_theme.dart             # Dark purple/lilac Material 3 theme; inputDecorationTheme is borderless/unfilled by default

├── screens/

│   ├── home_screen.dart           # Main shell — bottom nav: Notes / Discover / Liked / Calendar, notched FAB. Owns the single top AppBar shared by all tabs (left-aligned title via `titleSpacing`, no reserved `leading` slot — the Notes tab's back arrow is inlined into the title `Row` instead so all four tab titles sit flush left). On the Notes tab, AppBar actions are grid/list toggle, edit-theme (pencil) toggle, and archive. When browsing inside a themed folder, the AppBar's `flexibleSpace` paints that folder's background image + scrim behind the title/actions (resolved via its own `_resolveBackgroundImage` helper); the root Notes view never shows a background. Wrapped in `PreferredSize` since the background-aware `AppBar` is built lazily inside a `Builder`.

│   ├── notes_screen.dart          # Folder browser + notes list; instant swipe-archive (right) and swipe-delete (left), both with Undo. Toggleable grid (`MasonryGridView.count`, 2 columns)/list view. Single-select theming edit mode (`toggleEditMode`/`isEditMode`, exposed to `HomeScreen` via `GlobalKey`) — tapping a note/folder while in edit mode opens `ThemePickerSheet` immediately for just that item. Exposes `currentFolderBackgroundPath` so `HomeScreen`'s AppBar can theme itself when inside a themed folder. Calls `widget.onStateChanged` (a callback passed in from `HomeScreen`) on every folder-nav/grid-toggle/edit-mode change so the parent's AppBar reliably rebuilds. Orphaned user-uploaded background files are swept from disk on both background replacement and permanent note/folder deletion (after the 5s Undo window). Also defines the shared top-level **`showUndoToast()`** helper (dark rounded card + purple "Undo" pill + a thin draining countdown bar along the bottom, auto-dismissing after **3 seconds**) — public and reused by `liked_anime_screen.dart`, `watchlisted_screen.dart`, AND now `calendar_screen.dart`. `_notesInCurrentFolder` filters out any note where `isCalendarReminder == true`, keeping calendar todos off this tab. Card-preview checklist parsing (`_parseChecklistPreview`/`_freeTextPreview`) now reads `Note.checklistItems` directly instead of regexing `content`.

│   ├── note_editor_screen.dart    # Create/edit/read-only note — borderless title+body, reminder bell, word count + Undo/Redo + add-task in a keyboard-docked toolbar, drag-reorder checklist, two-layer auto-save (debounce + periodic) with duplicate-save guards, and a PopScope that auto-saves on back navigation. Renders the note's `backgroundImagePath` (if set) full-screen behind the AppBar/body/toolbar via a `Stack` + scrim. Accepts `isCalendarReminder`/`initialCalendarDate` constructor params for the Calendar tab's "New" flow. The reminder bell (`_pickReminder`) skips the date picker entirely when `_calendarDate != null`, going straight to the time picker. Checklist rows are backed by the new `ChecklistItem` model (`_ChecklistItem.fromModel()`/`.toModel()` convert between the editor's UI-only wrapper and the persisted Hive object); `content` is saved as plain free-text only via `_buildFinalContent()`, with `checklistItems` saved separately via `_buildChecklistItems()`.

│   ├── archived_screen.dart       # Lists archived notes (read-only preview via NoteEditorScreen(readOnly: true)) and archived folders (tap to browse contents, Unarchive button)

│   ├── discover_screen.dart       # Tinder-style anime swipe feed (Jikan API) with a horizontal genre filter chip bar, direction-fade overlay

│   ├── liked_anime_screen.dart    # Liked anime, grouped/filterable, adjustable grid columns. Long-press opens a small actions-menu dialog (Add to Watchlist / Remove from Liked) — both instant via `_moveToWatchlist`/`_removeFromLiked`, no confirmation dialogs, each backed by `showUndoToast`. Defines `_showAnimeDetailDialog` (duplicated identically in `watchlisted_screen.dart`). Grid card images use `loadingBuilder` + `SkeletonBox` for a shimmer placeholder while loading.

│   ├── watchlisted_screen.dart    # New full-screen page, pushed from the center FAB on the Liked Anime tab. Mirrors `LikedAnimeScreen`'s layout but reads/writes `AnimeLikeService`'s watchlisted list instead. Long-press opens a 2–3 item actions menu: **Add/Edit Remarks**, **Clear Remarks**, and **Move to Liked** — all instant with an Undo toast.

│   └── calendar_screen.dart       # Month calendar (`TableCalendar`). `addReminderForSelectedDay()` now opens the real `NoteEditorScreen` (tagged `isCalendarReminder: true`, `initialCalendarDate` = selected day) instead of the old quick-add dialog. `_notesForDay()`/`_eventLoader()` group by `note.calendarDate ?? note.reminderAt`'s date (so a no-time-set calendar todo still shows under the right day). `_loadNotes()` now includes notes where EITHER `reminderAt != null` OR `calendarDate != null`. Each day's list row shows a tappable circle icon (`_toggleCompleted`, flips `Note.isCompleted` + strikethrough/grey-out), and is wrapped in a `Dismissible` (swipe-left only) calling `_swipeDeleteNote` — instant delete + `showUndoToast` (imported from `notes_screen.dart`), matching the Notes tab's delete pattern minus the archive direction. Both `_toggleCompleted` and the create/delete flows call `WidgetService.refreshWidget(...)` to keep the home screen widget in sync. The old in-tab "Add reminder" header button and "Add one" empty-state button were both removed — the shared FAB is now the only entry point for adding a calendar todo.

├── models/

│   ├── note.dart                  # Note model — see Data & Storage above for the full current field list (`typeId: 0`)

│   ├── checklist_item.dart        # NEW. `ChecklistItem` (`typeId: 4`) — `id` (String), `text`, `done`. Source of truth for checklist data, referenced by `Note.checklistItems`.

│   ├── category.dart              # Category/folder model (`typeId: 1`) — `id, name, parentId, isVisible, isArchived, backgroundImagePath`

│   ├── anime.dart                 # Plain Dart model for Jikan anime data, includes genres

│   ├── anime_genre.dart           # Plain Dart model for a Jikan genre (malId, name)

│   └── saved_anime.dart           # Hive-persisted version of Anime — `SavedAnime` (`typeId: 3`) + the `HiveAnimeSource` enum adapter (`typeId: 2`) it depends on.

├── services/

│   ├── database_service.dart      # Hive DB singleton — CRUD for notes, categories, AND `SavedAnime`. `init()` registers ALL adapters before opening any box — `NoteAdapter`, `CategoryAdapter`, `HiveAnimeSourceAdapter`, `SavedAnimeAdapter`, and now `ChecklistItemAdapter` (registered before the `notes` box opens, since `Note` now embeds `List<ChecklistItem>`). Exposes `getSavedAnime(listType)`, `saveSavedAnime()`, `deleteSavedAnime()`, `isSavedAnime()`, and `getSavedAnimeEntry()`.

│   ├── notification_service.dart  # Schedules/cancels local notifications for note reminders

│   ├── ai_suggestion_service.dart # Local rule-based reminder time suggestion from note text

│   ├── anime_api_service.dart     # Fetches anime + genre data from the Jikan REST API

│   ├── anime_like_service.dart    # `ChangeNotifier` singleton — Hive-backed (via `DatabaseService`), so both liked AND watchlisted lists survive app restarts.

│   ├── background_image_service.dart # Singleton handling theme background images — picks from gallery via `image_picker`, copies into a permanent `backgrounds/` folder, and deletes previously-uploaded files when replaced/owner deleted.

│   └── widget_service.dart        # NEW. `WidgetService.refreshWidget(List<Note> allNotes)` — filters to today's notes, builds the text block for the Android home screen widget, pushes it via `home_widget`'s `saveWidgetData`/`updateWidget`. Called from `main.dart` (cold start) and `calendar_screen.dart` (every todo mutation).

└── widgets/

    ├── theme_picker_sheet.dart    # `showThemePickerSheet()` — bottom sheet for choosing a note/folder background.

    └── skeleton_loader.dart       # `SkeletonBox` — shimmer-style placeholder used as the `loadingBuilder` for anime poster images.

android/app/src/main/

├── kotlin/com/example/remind/

│   ├── MainActivity.kt            # Standard Flutter MainActivity (unmodified)

│   └── TodoWidgetProvider.kt      # NEW. `AppWidgetProvider` for the home screen widget — reads `todo_list` from `HomeWidgetPlugin.getData(context)`, populates `RemoteViews`, wires tap-to-open via `HomeWidgetLaunchIntent`.

├── res/xml/todo_widget_info.xml   # NEW. Widget metadata — min size, update period, initial layout reference.

├── res/layout/todo_widget_layout.xml  # NEW. Widget's visual layout (header + divider + todo-list TextView).

├── res/drawable/widget_background.xml # NEW. Layer-list drawable — purple glow ring behind a dark bordered card.

├── res/drawable/todo_bullet.xml   # NEW, currently unused. Small purple oval, kept as a Stage 3 building block.

└── AndroidManifest.xml            # Has a new `<receiver android:name="TodoWidgetProvider" .../>` block registering the widget provider + its `@xml/todo_widget_info` metadata.

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
- **Local DB:** Hive (notes, categories, persisted liked/watchlisted anime, and now structured checklist items)
- **Notifications:** `flutter_local_notifications` + `timezone`
- **Calendar:** `table_calendar`
- **Networking:** `http` (used by `AnimeApiService`)
- **Grid layout:** `flutter_staggered_grid_view` (powers the notes list's 2-column masonry grid)
- **Image picking/storage:** `image_picker` (gallery photo selection for custom backgrounds) + `path_provider` (locating app documents directory to permanently store copied uploads)
- **Home screen widget:** `home_widget: ^0.7.0+1` — Android-only so far; pairs Dart-side `saveWidgetData`/`updateWidget` calls with native Kotlin (`AppWidgetProvider` + XML layout/drawables).
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
- **Home screen widget setup:** after adding/changing any file under `android/app/src/main/res/{layout,xml,drawable}/` or `kotlin/com/example/remind/`, run `flutter clean` before `flutter run` — incremental Android builds have repeatedly failed to pick up new/changed widget resource files without a full clean first. After a successful rebuild, **remove the existing widget instance from the home screen and re-add it fresh** — Android caches widget layouts per-instance and won't always pick up a layout change on an already-placed widget.
- **`RemoteViews` only supports a fixed allowlist of view classes** (`LinearLayout`, `TextView`, `ImageView`, `Button`, etc.) — a plain `<View>` (e.g. used as a quick divider) throws `Class not allowed to be inflated android.view.View` at render time, surfacing as "Can't load widget" on the home screen. Always use a zero-height `<LinearLayout>` for divider lines in widget layouts instead.
- `home_widget: 0.7.0+1`'s `HomeWidget.updateWidget(...)` takes a `name:` parameter (the Android provider class name as a String), not `android:` — easy to assume otherwise from older docs/examples.

## Notes for AI Assistants

- This is a **learning project** — the developer is new to Flutter, so prefer clear, well-commented code and step-by-step explanations over terse advanced patterns. The developer's strongly preferred working style across sessions: exact, copy-pasteable find-and-replace code blocks with precise, Ctrl+F-able `old_str`/`new_str` text — no unsolicited explanations or design discussions unless they ask.
- Stick to **lowercase_with_underscores** for file/package names per Dart conventions.
- No authentication/login system yet — all data is local-only by design (for now).
- When adding new features, follow the existing `screens/ widgets/ models/ services/ theme/` folder convention.
- The dark purple theme (`AppTheme.lightTheme` — name is legacy, the theme itself is now dark) should be reused, not redefined, in new screens/widgets. Avoid hardcoded colors like `Colors.black87` or `Colors.grey.shadeXXX` in new code — they don't adapt to the dark palette. Prefer `Theme.of(context).colorScheme.*` or `Colors.white` / `Colors.white70` / `Colors.white38` for text on dark surfaces. **Exception:** note/folder cards and the themed editor intentionally use literal `Colors.black87`/`Colors.white`/etc. for text drawn directly on top of a colored card or background image.
- `DatabaseService.instance` is the single source of truth for all Hive reads/writes — never open Hive boxes directly in screens.
- `NotesScreenState` (public) exposes `showAddOptions()`, `goBack()`, `isAtRoot`, `currentFolderName`, `currentFolderBackgroundPath`, `isGridView`/`toggleGridView()`, `isEditMode`/`toggleEditMode()`, and `openArchived()` — all driven by `HomeScreen` via `GlobalKey<NotesScreenState>`. `CalendarScreenState` (public) exposes `addReminderForSelectedDay()` the same GlobalKey-driven way — this method's *implementation* changed (now opens `NoteEditorScreen` instead of a dialog) but its signature/call site from `HomeScreen`'s FAB did not.
- A note's `categoryId` is set **once**, either from the existing note (editing) or from `initialCategoryId` (the folder it was created inside) — there's no category dropdown in the editor; folder placement is implicit from where "New Note" was tapped. Calendar-created notes don't get a `categoryId` at all (always null) since they're not meant to live inside the Notes folder structure.
- **Checklist items are now a proper Hive model — NOT text encoded inside `content` anymore.** This was a deliberate upgrade (the old README noted it as "a known possible upgrade, not yet done" — it's now done). `ChecklistItem` (`typeId: 4`) has a stable string `id`, `text`, `done`. `Note.checklistItems` (`@HiveField(14)`) is the source of truth; `note_editor_screen.dart`'s `_buildChecklistItems()` builds the persisted list on save, `_ChecklistItem.fromModel()` rebuilds the editor's UI-wrapper list on load. `content` is plain free-text only now — there is no parsing step left for checklist lines inside it. `notes_screen.dart`'s card-preview functions were updated to match (`_parseChecklistPreview(Note note)` / `_freeTextPreview(Note note)`, both now take the whole `Note` rather than a content string). **⚠️ There is a currently-unresolved bug where checklist item text comes back wrong (e.g. `"asd"` becomes `"[ ] asd"`) after closing and reopening the app — confirmed to happen on BOTH calendar-created and regular Notes-tab notes, so it's not Calendar-specific.** The next debugging step in progress was inspecting the generated `checklist_item.g.dart` for a field-order or adapter-registration mismatch. If picking this up: check (1) `checklist_item.g.dart`'s `read()`/`write()` field order matches `checklist_item.dart`'s `@HiveField` numbers exactly, (2) `ChecklistItemAdapter` is registered in `database_service.dart` before the `notes` box is opened, (3) there isn't a second/stale copy of either generated file lingering from before a `build_runner` regen, (4) whether the bug is present immediately after creation (before any restart) or only after a restart — this hasn't been isolated yet.
- The `id` field on the editor's UI-only `_ChecklistItem` class changed from an auto-incrementing `int` to a stable `String` (format: `"<microsecondsSinceEpoch>_<counter>"`) specifically so the planned home screen widget can address one specific checklist item from outside the app (a widget tap only has noteId+itemId to go on, no concept of "current list position"). Any code still assuming `item.id` is an `int` (e.g. old modulo-based placeholder-text lookups) needs updating to hash the string instead — `_taskPlaceholderFor` was already fixed to use `id.hashCode.abs() % length`.
- **Undo/Redo (editor) is text-only and intentionally separate from auto-save's own state.** `_undoStack`/`_redoStack` hold `_EditSnapshot(title, content)` pairs, pushed via a 500ms debounce distinct from auto-save's 1.2s debounce. Checklist and reminder state are NOT part of this history; only title/content text.
- **Pin/Color picker and the slash command menu were both removed from the editor UI.** `Note.isPinned` and `Note.colorValue` remain real Hive fields and `_saveNote()` preserves whatever value an existing note already had. Re-adding pin/color UI is a known possible follow-up — confirm with the developer before doing so.
- Swipe actions in `notes_screen.dart` (archive on right swipe, delete on left swipe, for both notes and folders) are **instant, not timer-deferred**. `calendar_screen.dart` now has its own swipe-left-to-delete (`_swipeDeleteNote`), reusing `notes_screen.dart`'s `showUndoToast` via `import 'notes_screen.dart' show showUndoToast;` rather than duplicating the styling — but does NOT offer archive (swipe-right), since that wasn't requested for the Calendar tab.
- **The shared `showUndoToast()` auto-dismiss window is 3 seconds.** **Note:** the note/folder background-image cleanup delays in `notes_screen.dart` still use their own separate 5-second `Future.delayed` timers, gated independently of the toast — known mismatch, not yet resolved, unrelated to the Calendar/checklist work in this stage.
- **Background theming is single-select, not multi-select.** Don't reintroduce Set-based multi-selection without confirming with the developer first.
- `NoteEditorScreen` has a `readOnly` constructor flag (unchanged from before) AND now also `isCalendarReminder`/`initialCalendarDate` (new, for the Calendar tab's "New" flow only — both default to `false`/`null` so existing call sites from `notes_screen.dart` are unaffected).
- **Bold/Italic and Text Color were both built, then fully removed.** Treat resurrecting either as a fresh scoping conversation.
- Image attachments (camera capture / inline photos) and voice-to-text dictation remain **explicitly deferred**.
- `AiSuggestionService` is fully offline/local — no API key, no network call.
- `NoteEditorScreen` has **two auto-save layers** (1.2s debounce + 10s periodic `Timer.periodic`), unchanged in this stage.
- **Back navigation also auto-saves**, via `PopScope(canPop: false, ...)`, unchanged in this stage.
- **Editor layout** (background image stack, transparent Scaffold/AppBar/toolbar when themed, keyboard toolbar contents) is unchanged from before this stage's checklist-model refactor — only the checklist data plumbing changed, not the visual layout.
- `notes_screen.dart`'s top-of-screen header lives in `HomeScreen`'s shared AppBar, not in `NotesScreen`'s own body — unchanged.
- `AnimeLikeService.instance` remains the single source of truth for liked/watchlisted anime and remarks — entirely untouched by this stage's Calendar/checklist work.
- **Calendar tab's in-row "Add reminder" header button and the empty-state "Add one" button were both removed at the developer's request** — the shared bottom FAB (already wired via `CalendarScreenState.addReminderForSelectedDay()`) is now the sole entry point for adding a calendar todo. Don't reintroduce either button without checking first.
- **Home screen widget is mid-build, not finished.** The static "show today's todos as one text block, tap opens app" version works. The interactive-per-item-checkbox version (Stages 3–4 above) has NOT been started — don't assume `RemoteViewsService`/`BroadcastReceiver` files exist yet; they need to be created from scratch when that work resumes. The architecture decision (signal-via-SharedPreferences + Dart background callback, never native-writes-Hive-directly) was explicitly confirmed with the developer and should be treated as settled unless they say otherwise.
- Jikan (`https://api.jikan.moe/v4`) is a free, unofficial, rate-limited public API — batch/throttle requests, don't hammer it.