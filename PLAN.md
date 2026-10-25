# Time Block — Project Plan

> A clock that shows your waking day as 5‑minute blocks, so you can *see* time passing,
> log what each block went to, and get gently (then not so gently) pushed to bed on time.

---

## 1. Core concept

- **1 block = 5 minutes.** 1 hour = 12 blocks, a full 24 h day = 288 blocks.
- The grid only shows your **awake window** (wake time → bedtime). Example: 07:00 → 23:00 = 16 h = **192 blocks**.
- Each block is in one of these states:
  | State | Look |
  |---|---|
  | Future, empty | faint outline |
  | Future, pre‑logged (meal, meeting…) | hollow / dimmed category color |
  | Past, logged | solid category color |
  | Past, unlogged | grey |
  | Current | pulsing / highlighted |
- **Counter:** big number = blocks left until bedtime over the day's usable total (e.g. `47/192`), small line = blocks used / logged today.
- **After bedtime the counter goes negative** (`−6`, `−14`…) and the UI degrades into "horror mode" (see §3.5).

### The "day" is wake‑to‑sleep, not midnight‑to‑midnight
If you're still up at 01:30, that is still *today*, 2.5 h past bedtime → `−30`. The day rolls over at a cutoff two hours before wake time (05:00 for a 07:00 wake).

---

## 2. Platforms & architecture

**Stack:** Swift 6, SwiftUI, WidgetKit, App Intents, EventKit; logs saved as one JSON file per day. (Xcode 26.5 / macOS 26 on this machine.)

```
TimeBlockPackage/          shared Swift package
├── TimeBlockKit           models, block math, schedule logic, settings, sample data (pure Foundation)
├── TimeBlockUI            SwiftUI views shared by app, widget and (later) watch: grid, ring, counter, themes
└── TimeBlockPrototype     M0 playground: time slider + widget previews; `--render` writes PNGs

TimeBlock.xcodeproj        depends on TimeBlockPackage; source folders sync automatically
├── TimeBlockApp/          Mac app: day window with a settings inspector (⌘,), menu bar extra
├── TimeBlockWidget/       WidgetKit extension (small / medium / large), view picked per widget
└── Config/                entitlements, widget Info.plist

Later: iOS app (the Watch's companion + iPhone widgets), watchOS app + complications + Smart Stack widget
```

- App + widget share data through an **App Group** container (settings and day logs live there).
  - App Groups need a provisioning profile, i.e. an Apple Developer team selected in Xcode. Until then the project
    builds ad‑hoc ("Sign to Run Locally") without the App Group: logs stay in the app's own container, and the widget
    shows the default 07:00–23:00 schedule with no logs.
  - To enable: Xcode → target → Signing & Capabilities → pick the team for both targets, switch to Automatic signing,
    add App Groups capability `group.dev.timeblock` to both.
- Cross‑device sync (Mac ↔ iPhone ↔ Watch) via **CloudKit** — requires a paid Apple Developer account.
- Widget refresh: precompute a **timeline entry every 5 minutes** for the rest of the day (entries don't count against WidgetKit's reload budget). App calls `WidgetCenter.reloadAllTimelines()` whenever a log changes.

### Platform constraints to design around
1. **Widgets can't take text input.** They support buttons/toggles via App Intents only. So:
   - Widget = glanceable view + 1‑tap buttons ("log now as last category", "same as before").
   - Real logging = menu bar popover + main app.
2. **Apple doesn't allow third‑party watch faces.** "Become an Apple Watch screen" will be: complications on any face, a Smart Stack widget, and a full‑screen watch app. Not a replacement clock face.

---

## 3. Features

### 3.1 Day grid & counter (MVP)
- Rows = clock hours (12 blocks per row), columns = 5‑min slots. Large widget shows the full awake day (~16 rows).
- Rows always line up with the clock: waking at 08:30 starts halfway along the "08" row; a 23:30 bedtime ends halfway along "23".
- Counter shows blocks left over the day's usable total, e.g. `92/192`.
- Medium widget: current hour ± a few hours. Small widget: counter + a ring/mini‑bar.

### 3.2 Logging
- The window's grid starts in a look‑only state: hovering a block shows its time and contents, and outlines the
  whole run it belongs to (one activity, or one unlogged gap) with its range and length.
- **Select, then pick:** click selects a run, double‑click a single block, drag an exact range. Clicking an activity
  chip logs the selection (Clear empties it) and keeps it selected; the chip of the selection's activity is lit.
  Clicking off the blocks deselects.
- **Pick, then paint:** with nothing selected, a chip becomes a one‑shot brush: drag across blocks to log them, and
  the brush is put down afterwards.
- Painting splits the runs it covers and joins neighbours of the same activity; each view (track) is edited apart.
- Menu bar: shows the counter; click → "Now: [starred activities, search]" logs the current block (and optionally back‑fills unlogged blocks since the last log).
- Optional note per block range ("Wrote PLAN.md"): written on the selected logged blocks, shown on hover. A noted
  stretch is its own run; giving a whole run another activity keeps its note.
- Optional nudge notification: "3 blocks unlogged — what were you doing?"

### 3.2a Smart suggestions for unlogged blocks
Past blocks you didn't log stay **grey**, but carry a *hint* so back‑filling is one tap ("Confirm: 08:10–08:40 Commute?").
Signals, all processed on‑device:
| Signal | Where | Hints |
|---|---|---|
| Location visits / movement (Core Location `CLVisit`, significant changes) | iPhone / Watch (M8) | Home, Work, Commute/Traffic, Outdoor, Gym, named places |
| Mac activity: idle vs active, frontmost app | Mac (from M2) | Away from Mac, Coding, Browsing, Video call, Screen time |
| Calendar event at that time | all | Meeting / event name |
| Your own history (same time, same weekday) | all | "Usually Lunch at this time" |
- User can name places ("Home", "Office", "Gym") and map each place → category.
- Suggestions are never auto‑committed; grey + hint until confirmed.
- Note: Macs have no GPS, so location‑based hints really arrive with the iPhone/Watch app; the Mac uses activity signals instead.

### 3.3 Activities, groups & colors
Log as finely as you like; read the day by group. A built-in library of ~170 detailed **activities** (Breakfast,
Lunch, Email, Gym, Metro…) each belongs to a **group**, and every activity in a group shares the group's color, so
a day still reads as a story at a glance. Groups follow how time-use research (the American Time Use Survey) and
time-logging coaches split a day, with plain names:
| Group | Hue | Examples |
|---|---|---|
| Work | blue | Work, Deep work, Meeting, Email, Coding, Paperwork |
| Learn | purple | Study, Reading, Class, Language, Journaling |
| Health | green | Exercise, Gym, Walk, Outdoors, Yoga, Doctor |
| People | pink | Friends, Family, Partner, Kids, Call, Party |
| Life | orange | Breakfast, Lunch, Dinner, Coffee, Cooking, Chores, Shower, Errands |
| Transit | teal | Commute, Driving, Bus, Metro, Flight |
| Leisure | yellow | Rest, Nap, TV and shows, Gaming, Hobby, Café |
| Drift | muted plum | Doomscroll, Social media, Videos, Procrastinating |
- Grey = unlogged, red = taken from sleep. Leisure is rest you chose; Drift is time that slipped away.
- **Starred** activities make up the palette, listed by group (no manual order); common ones are starred out
  of the box. A search field above it finds any other by name, by other words ("meal" finds Lunch, "slack" finds
  Work chat) or by group; Return logs the best match. Right-click a chip, or star it in Settings' library, to star
  or unstar.
- Summaries (legend, story bar) report time per **group** ("Life 2h 10m"), not per activity.
- Your own activities pick a name, group and SF Symbol, and your own groups a name and color; they follow the
  built-in groups. Built-in activities and groups can be edited the same way, saved as edits over the originals
  so Reset brings them back. The Body view keeps its five postures, each its own color.
- Settings' library opens one group at a time. An activity moved to another group takes its open editor along,
  opening that group. A name left empty goes back to the built-in one (or, for your own, to what it was), so
  nothing ends up nameless.
- Built-in activities are **retired** rather than removed (so far Meal, replaced by Breakfast/Lunch/Dinner/Snack,
  and the vague Screen time): blocks already logged keep their name and color, but they leave search, the
  library and the palette. Ids of built-ins never change, since logs refer to them.
- Removing an activity (built-in or your own, or a posture) retires it the same way, so logs never lose a name.
  Settings lists the removed ones under Removed to put back; they keep their star meanwhile.

### 3.4 Pre‑logging
- **Recurring templates** (Settings ▸ Routine): "Breakfast 08:00, 6 blocks, every day", "Coffee 15:00, 2 blocks,
  weekdays". Each picks an activity, a start, a length and its days, and can be paused.
- Pre‑logged blocks render hollow in the future, auto‑turn solid when time passes (user can override after the fact).
- A day's templates are laid out once, the first time the app sees that day (the whole day, so a lunch you didn't
  change counts even when the app opens after it), as `.template` logs in blocks still free in their track. Logging
  over them replaces them. Changing, pausing or removing a template lays them out again over the blocks still to
  come only; what has happened stays.
- **Calendar import:** events become pre‑logged blocks (rounded to 5‑min boundaries), mapped to a category (default "Meeting"; per‑calendar mapping).

### 3.5 Late‑night "horror mode"
Escalates the further past bedtime you are:
| Blocks left | Effect |
|---|---|
| 6 to 1 (last 30 min) | "wind‑down": warm amber background + amber counter |
| −1 to −6 (≤30 min) | counter turns red, grid desaturates, subtle vignette |
| −7 to −24 (≤2 h) | blood‑red palette, blocks "crack"/drip, flicker animation in app, glitchy font on the counter |
| −25 and beyond | full dread: dark red/black, distorted blocks, ominous copy ("You are borrowing from tomorrow."), optional notifications |
- Widget gets the static version (widgets can't run continuous animations); the app/menu bar gets animated effects.
- Tomorrow's grid can show the debt: "You start 30 blocks in the red."

### 3.6 Sleep‑shift plan ("adjust timezone")
Gradually move your schedule earlier (or later) instead of all at once (Settings ▸ Sleep Shift).
- Inputs: **bedtime or wake time** and the time to get it to, the **step** (10–60 min), **every N days** (default 1),
  and either the **start day** (default today) or the **day to be there by**, which starts it as many steps before
  as it takes (too soon to make at that step size says so and won't start). Switching between the two keeps the plan.
- Steps land on **nights**: a step day's bedtime moves, and wake time follows the next morning, so every night is as
  long as before and a morning that's gone never moves. Starting today moves tonight's bedtime; the shift is done the
  first day that's all on the target.
- Example: bedtime 01:00, step 30 min/day, to 23:00 → 01:00, 00:30, 00:00, 23:30, 23:00 (done in 4 days).
- The other end shifts with it (keeps sleep duration) or stays fixed (user choice).
- Starting a shift makes the target the schedule in Settings and keeps where you started; each day's schedule is
  that many steps along. Wake time and bedtime each stop at their target, and the shift ends by itself once it's
  done. Stop keeps today's times as the schedule.
- The grid/counter always use *today's* planned bedtime, so horror mode tracks the plan. Routine templates keep
  their clock times as the day moves.
- A day's rollover comes from the schedule of the date a moment falls on, so 05:30 is still "tonight" while that
  date's wake time is 08:30.
- Later: **jet lag**: pick a destination timezone + travel date, and the plan pre‑shifts you.

### 3.6a Views (tracks)
The same day can be looked at through different **views**. Each view is its own **track** of logs, so one block can hold
one log per track: 10:30 is *Meeting* in Activity and *Standing* in Body. Switch with the toolbar control, View ▸ (⌘1/⌘2),
or the menu bar panel; each widget picks its own view in its Edit sheet, so an Activity and a Body widget can sit side by side.

| View | Statuses | Colors | Headline |
|---|---|---|---|
| Activity | activities in groups (§3.3) | hue per group | time per group |
| Body | Lying, Sitting, Standing, Walking, Exercising | cool → warm: the more you move, the warmer | longest unbroken sit |

- Horror mode, the counter and the bedtime line are the same in every view; only block colors and the summary change.
- Body logging sources: manual on Mac (M2); iPhone/Watch fill it automatically from Core Motion activity
  (stationary / walking / running / cycling / automotive) and HealthKit workouts and stand minutes (M8).
  Macs have no HealthKit or motion data.
- Later views to consider: Energy (1–5), Location (from §3.2a), Focus quality.

### 3.7 Stats (later)
- Blocks per category per day/week, logged %, average blocks past bedtime, streaks of on‑time sleep.

---

## 4. Data model (TimeBlockKit)

```swift
Category      id, name, track(.activity|.body), group? (activity only; sets the color), color, symbol, keywords
              (built-ins live in code; AppSettings keeps favorites, customCategories, customGroups,
              editedCategories/editedGroups over the built-ins, removedCategories ids, templates and sleepShift; a category
              saves its group by id)
DayLog        day ("2026-10-24", the wake date), wakeMinute, logs, isPlanned (templates laid out): one JSON file
              per day
BlockLog      id, startIndex, length, categoryID, note, source(.manual|.template|.calendar)
              (indexes count from DayLog.wakeMinute and move with wake time; track comes from the category;
              at most one log per block per track; painting joins runs and splits the ones it covers)
Template      id, categoryID, startMinute (clock), length (blocks), weekdays (Calendar weekdays, 1 = Sunday), isEnabled
Schedule      wakeMinute, bedMinute, dayRolloverMinute
SleepShift    from (Schedule), startDay (the first step's night), stepMinutes, everyDays (the target is
              AppSettings.schedule)
CalendarLink  calendarIdentifier, categoryID, isEnabled
```
Block math (pure functions, fully unit‑tested): `blockIndex(for: Date)`, `awakeBlocks(on:)`, `remaining(at:)` (can be negative), `AppSettings.schedule(on:)` (applies SleepShift), DST‑safe.

---

## 5. Milestones

| # | Milestone | Done when | Status |
|---|---|---|---|
| M0 | **Visual prototype** | SwiftUI preview of the grid in normal + horror states; we agree on the look | ✅ done |
| M1 | **Mac app + read‑only widget** | widget shows live grid & counter, updates every 5 min; schedule set in app | 🟡 built; widget uses the default schedule until signed with a team (§2) |
| — | **Views: Activity / Body** (§3.6a) | switch views in window, menu bar and per widget | ✅ done |
| M2 | **Logging + activities** | paint blocks in app, log from menu bar, colors in widget; logs per view | 🟡 select/paint logging, notes, activity library with search and stars, own activities, menu bar "Now" logging and saving done; the unlogged nudge left; widget sees logs once signed with a team |
| M3 | **Pre‑log templates** | recurring meals/coffee appear as hollow future blocks | ✅ done (Settings ▸ Routine) |
| M4 | **Horror mode** | negative counter + escalation levels in widget and app | 🟡 visuals done in M0; notifications and "tomorrow's debt" left |
| M5 | **Sleep‑shift plan** | stepped bedtime schedule drives the grid | ✅ done (Settings ▸ Sleep Shift); jet lag later |
| M6 | **Calendar import** | events show as pre‑logged blocks | |
| M7 | **Interactive widget buttons + Mac activity hints** | 1‑tap log from the widget; grey blocks show "Away / Coding / Call" suggestions | |
| M8 | **iPhone + Apple Watch** | CloudKit sync, watch app, complications, Smart Stack, location and motion data | |

---

## 6. Decisions
| Topic | Decision |
|---|---|
| Distribution | Personal use first, kept sandbox‑friendly so the App Store is easy later |
| Sleep shift | Wake time shifts with bedtime (sleep length stays the same) |
| Unlogged blocks | Stay grey, with location/activity‑based suggestions for one‑tap logging (§3.2a) |
| Google Calendar | Read through macOS Calendar with EventKit (add Google in System Settings → Internet Accounts) |
| Platforms | Mac first; iPhone and Watch in M8 |
| Views | Separate log tracks (Activity, Body), not filters over one track |
| Storage | One JSON file per day (`DayLog`) rather than SwiftData: small, testable, readable; revisit for CloudKit in M8 |
| Signing | Ad‑hoc ("Sign to Run Locally") until an Apple Developer team is set up; App Group added then |
