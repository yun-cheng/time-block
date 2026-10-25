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
- **Views:** switch between Activity and Body (lying, sitting, standing, walking, exercising). Each view is its
  own track of logs, so a block can be *Meeting* and *Standing* at once.

See [PLAN.md](PLAN.md) for the full design, decisions and milestones.

## Status

Built: Mac app window with settings in a side panel (gear button or ⌘,), menu bar extra, and a WidgetKit widget
in three sizes. Logs are saved one file per day. Next up is a nudge for unlogged time; see the milestones in
PLAN.md.

### Logging

- **Hover** a block to see its time and what it holds. A logged stretch (or an unlogged gap) is outlined as a whole,
  with its range: `18:20–19:25 · Social · 1h 5m`.
- **Select, then pick:** click a block to select its whole stretch, double‑click to select just that block, or
  drag to select exactly what you cover. Click an activity under the grid to log the selection, or Clear to empty
  it. The selection stays, and its activity stays lit, until you click off the blocks.
- **Drag the ends:** select a run of one activity and a round handle shows at each end. Drag one to make it
  longer or shorter: the blocks it takes in are logged as it, and the ones it lets go are cleared.
- **Drag to move:** drag a selection that holds something logged to move it somewhere else, gaps and notes
  included. What it lands on is replaced, and the blocks it leaves are cleared.
- **See the result as you drag:** whether you drag an end, a selection or an activity, the blocks show what
  they'll end up as until you let go.
- **Right-click to clear:** right-click a logged block and pick Clear Blocks to empty its whole stretch, or the
  selection when the block is in it. Delete empties a selection too.
- **Undo and redo:** ⌘Z, or the Undo button in the toolbar, takes back the last change to your blocks, whatever
  made it, and ⇧⌘Z or Redo puts it back.
- **Pick, then paint:** with nothing selected, click an activity and drag across blocks. It is put down after one
  drag, so a stray click never logs anything.
- **Find any activity:** the chips are your starred activities, by group. Type in the search field above them to
  find any of the ~170 built in (`meal` finds Breakfast, Lunch, Dinner…); Return picks the top match. Click a group
  tab under it to see all of that group's activities; Starred (or the group again) goes back. Right‑click a chip to
  star or unstar it.
- **Notes:** with logged blocks selected, type a note under the activities (`Dinner with Ana`). It shows when you
  hover them, and a noted stretch is selected and outlined on its own.
- **Any day, like a calendar:** every day is kept. In the toolbar, as in Calendar, ‹ › go back and forth a day
  (⌘[ ⌘]) and Today (⌘T) comes back; click the date beside them to pick one from a calendar. Every day can be edited like today: fill in one you
  forgot to log, or pre‑log one ahead, with your routine already on it. Past days keep the wake and bedtime they had.
- **Menu bar:** one click logs the block in progress, optionally filling the unlogged gap before it.
- **Routine:** in Settings, add what comes back on given days (Lunch 12:00–12:30, weekdays). Each of those days
  it's pre‑logged in whatever blocks are free: hollow until the time comes, then logged, unless you paint over it.
  Change or pause one, and only the blocks still to come move.
- **Settings:** browse the whole library by group, one open at a time, to star more. Edit any activity (name,
  group, and an icon from a searchable picker: `meal` finds the fork and knife) or group (name, color), built-in
  ones too (Reset puts them back, and a name left empty goes back by itself), and add your own groups and
  activities. New ones start unstarred. Remove any activity you don't use: blocks already logged keep it, and
  Removed, at the end of the library, puts it back (still starred, if it was).
- **Times** (wake up, bedtime, a shift's target, a routine's start): type one, step it with ↑↓ (5 minutes on the
  minutes, an hour on the hours), or pick one from the ⌄ list, every 15 minutes. A typed time rounds to the nearest
  5 minutes once you're done with it.

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
