# Time Block

A Mac app and desktop widget that shows your waking day as 5‑minute blocks, so you can *see* time passing,
log what each block went to, and get pushed to bed on time. After bedtime the counter goes negative and the
whole UI slowly turns into a horror show.

![Afternoon: 92 of 192 blocks left](docs/images/afternoon.jpg)
![Three and a half hours past bedtime](docs/images/nightmare.jpg)
![The Body view: sitting, standing, walking, exercising](docs/images/body-view.jpg)

- **1 block = 5 minutes.** Rows are clock hours of 12 blocks; only your waking hours are shown.
- **Read the time off the grid:** in Settings ▸ Grid, wider gaps split each hour row every 10, 15, 20 or 30 minutes
  (30 to start), and can split the rows too: every 3, 6 or 12 hours on the clock, or your waking day in 2 to 6 equal
  parts. Minute numbers can go above the grid as well, every 10 to 30 minutes. The widget follows the same settings.
- **Counter:** blocks left over the day's usable total (`92/192`). It goes negative after bedtime.
- **Sleep shift:** in Settings, move bedtime or wake time to a new time a step a night (bedtime 01:00 to 23:00, 30
  minutes a night). Bedtime moves first and the next morning's wake time follows, so you sleep as long. Set the day
  it starts or the day to be there by; each day's grid and counter use that day's times. Slept in? Change today's
  times under Schedule and the shift carries on from them, Hold Tonight puts each step a night later, and Edit
  changes the rest of the shift.
- **Wind down:** in Settings, set how long before bedtime you need to get ready for sleep (15 minutes to 2 hours, 30 to
  start). Those last blocks are tinted amber, and when they start the whole day turns warm.
- **Colors tell the story:** log detailed activities (Breakfast, Email, Gym…); each belongs to a group (Work,
  Learn, Health, People, Life, Transit, Leisure, Drift) and takes its color. Grey is unlogged, amber is time to
  wind down, red is taken from sleep.
- **Several at once:** a block can hold more than one activity, such as *Commute* and *Podcast*. They stack as
  cards: what breaks into the rest is in front at the bottom-right (the shortest stretch, such as a trip to the
  toilet in a morning of work), the ones under it peek out at the top-left, and each counts its full time in the
  totals.
- **Views:** switch between Activity and Body (lying, sitting, standing, walking, exercising). Each view is its
  own track of logs, so a block can be *Meeting* and *Standing* at once.

See [PLAN.md](PLAN.md) for the full design, decisions and milestones.

## Status

Built: Mac app window with settings in a side panel (gear button or ⌘,), menu bar extra, and a WidgetKit widget
in three sizes. Logs are saved one file per day. Next up is a nudge for unlogged time; see the milestones in
PLAN.md.

### Logging

- **Hover** a block to see its time and what it holds. A logged stretch (or an unlogged gap) is outlined as a whole,
  with a label above it that follows the pointer along: `18:20–19:25 · Social · 1h 5m`.
- **Select, then pick:** click a block to select its whole stretch, double‑click to select just that block, or
  drag to select exactly what you cover. Its label stays put, with a **+** beside it (an edit symbol once
  something in it is logged): click that, or press Return, to open the activities, then click one to log the
  selection, or Clear to empty it. The selection stays, and its activity stays lit, until you click off the
  blocks. The rest of the time the window is just your day.
- **Drag the ends:** select a run of one activity and a round handle shows at each end. Drag one to make it
  longer or shorter: the blocks it takes in are logged as it, and the ones it lets go are cleared.
- **Drag to move:** drag a selection that holds something logged to move it somewhere else, gaps and notes
  included. What it lands on is replaced, and the blocks it leaves are cleared.
- **See the result as you drag:** whether you drag an end, a selection or an activity, the blocks show what
  they'll end up as until you let go.
- **Right-click to clear:** right-click a logged block and pick Clear Blocks to empty its whole stretch, or the
  selection when the block is in it. Delete empties a selection too.
- **Pick one of a stack:** point at a block holding several activities and its cards spread apart; click one to
  select that activity's own stretch. Logging, Clear, Delete, notes, moving and the end handles then change that
  activity alone, leaving whatever else the blocks hold. Pointing at or clicking a block with one activity takes
  in its whole stretch the same way, under anything stacked on part of it. Drag or double‑click to select everything
  the blocks hold.
- **Add one more:** pick **Add** in the two tools at the top of the activities (or hold ⌘), and the pointer gets a
  green plus. Clicking an activity then adds it to what the selected blocks hold, or takes a lit one off and leaves
  the rest. Once it has added, the tool goes back to **Normal**, which replaces.
- **Undo and redo:** ⌘Z, or the Undo button in the toolbar, takes back the last change to your blocks, whatever
  made it, and ⇧⌘Z or Redo puts it back.
- **Find any activity:** the activities shown are your starred ones, by group. Type in the search field above them
  to find any of the ~170 built in, whatever group is shown (`meal` finds Breakfast, Lunch, Dinner…); Return picks
  the top match. Click a group in the list beside them to see all of its activities; Starred goes back. Right‑click a
  chip to star or unstar it.
- **Notes:** with logged blocks selected, type a note under the activities (`Dinner with Ana`). It shows when you
  hover them, and a noted stretch is selected and outlined on its own.
- **Any day, like a calendar:** every day is kept. In the toolbar, as in Calendar, ‹ › go back and forth a day
  (⌘[ ⌘]) and Today (⌘T) comes back; click the date beside them to pick one from a calendar. Every day can be edited like today: fill in one you
  forgot to log, or pre‑log one ahead, with your routine already on it. Past days keep the wake and bedtime they had.
- **Timers:** log as you go. In the menu bar, pick how a timer counts (up from zero, or down from 5 to 90 minutes,
  25 for a Pomodoro) and click an activity to start one; in the window, the stopwatch in the toolbar does the same,
  and the timers going are listed under the grid. A timer's blocks fill in as it runs, every block it touches,
  alongside whatever they hold, so several can run at once (one per activity). Stop it to keep what it ran, or
  delete it (after you confirm) to drop it unlogged. A countdown notifies you at zero and keeps counting past it
  (`−2:13`) until you stop it. Hover the blocks a timer ran in to see exactly when (`⏱ 10:03–10:31`). Timers keep
  going when the app quits, and the widget fills in their blocks too.
- **Routine:** in Settings, add what comes back on given days (Lunch 12:00–12:30, weekdays). Each of those days
  it's pre‑logged in whatever blocks are free: hollow until the time comes, then logged, unless you log over it.
  Change or pause one, and only the blocks still to come move.
- **Settings:** browse the whole library by group, one open at a time, to star more. Edit any activity (name,
  group, and an icon from a searchable picker: `meal` finds the fork and knife) or group (name, color), built-in
  ones too (Reset puts them back, and a name left empty goes back by itself), and add your own groups and
  activities. New ones start unstarred. Remove any activity you don't use: blocks already logged keep it, and
  Removed, at the end of the library, puts it back (still starred, if it was).
- **Times** (wake up, bedtime, a shift's target, a routine's start): type one, step it with ↑↓ (5 minutes on the
  minutes, an hour on the hours), or pick one from the ⌄ list, every 15 minutes. A typed time rounds to the nearest
  5 minutes once you're done with it.
- **Done typing:** click anywhere outside a field (a time, a search, a note) to finish typing in it.

## Layout

```
TimeBlockPackage/          Swift package, shared by everything
  TimeBlockKit/            model and block math (pure Foundation, unit-tested)
  TimeBlockUI/             SwiftUI views: grid, ring, counter, mood themes, widget content
  TimeBlockPrototype/      design playground with a time slider; also renders PNGs
TimeBlock.xcodeproj        Mac app + widget extension, depends on the package
TimeBlockApp/              app target sources
TimeBlockWidget/           widget extension sources
Config/                    entitlements, widget Info.plist
```

## Build and run

Requires Xcode 26 and macOS 14 or later.

Run the tests:

```bash
swift test --package-path TimeBlockPackage
```

Build and launch the Mac app (or open `TimeBlock.xcodeproj` and press Run):

```bash
xcodebuild -project TimeBlock.xcodeproj -scheme TimeBlock -derivedDataPath .build/xcode -allowProvisioningUpdates build && open .build/xcode/Build/Products/Debug/TimeBlock.app
```

Then add the widget: right‑click the desktop ▸ Edit Widgets ▸ search "Time Block". Edit a placed widget to
choose its view.

Open the design playground, or render every scenario to `renders/`:

```bash
swift run --package-path TimeBlockPackage TimeBlockPrototype
```

```bash
swift run --package-path TimeBlockPackage TimeBlockPrototype --render renders
```

## Signing

The app and its widget share settings and logs through the App Group `<team ID>.dev.timeblock`, which needs an Apple
Developer team; a free Apple ID works. Both targets sign automatically with team `PS6X9X4H2H`: to build with yours,
add your Apple ID in Xcode ▸ Settings ▸ Accounts and pick its team for both targets under Signing & Capabilities. The
group's name follows the team, so nothing else changes. A build with no team still runs, but its widget shows the
default 07:00–23:00 schedule and no logs.

macOS runs the widget from one copy of the app, not always the newest: if it shows stale data, delete old builds
(such as Xcode's DerivedData) and reopen the app. It also keeps the widget running after a rebuild, so a new setting
the widget should follow can be missing from it: stop the old one, and macOS starts the new build's in its place.

```bash
pkill -f TimeBlockWidgetExtension
```
