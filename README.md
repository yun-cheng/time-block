# Time Block

A Mac app and desktop widget that shows your waking day as 5‑minute blocks, so you can *see* time passing,
log what each block went to, and get pushed to bed on time. After bedtime the counter goes negative and the
whole UI slowly turns into a horror show.

![Afternoon: 92 of 192 blocks left](docs/images/afternoon.jpg)
![Three and a half hours past bedtime](docs/images/nightmare.jpg)
![The Body view: sitting, standing, walking, exercising](docs/images/body-view.jpg)

- **1 block = 5 minutes.** Rows are clock hours of 12 blocks; only your waking hours are shown.
- **Counter:** blocks left over the day's usable total (`92/192`). It goes negative after bedtime.
- **Colors tell the story:** Activity groups (focus, fuel, people…) each own a hue; bright means intentional,
  muted means drift. Grey is unlogged, red is taken from sleep.
- **Views:** switch between Activity and Body (lying, sitting, standing, walking, exercising). Each view is its
  own track of logs, so a block can be *Meeting* and *Standing* at once.

See [PLAN.md](PLAN.md) for the full design, decisions and milestones.

## Status

Built: Mac app window with settings in a side panel (gear button or ⌘,), menu bar extra, and a WidgetKit widget
in three sizes. Logs are saved one file per day. Custom categories and notes come next; see the milestones in
PLAN.md.

### Logging

- **Hover** a block to see its time and what it holds. A logged stretch (or an unlogged gap) is outlined as a whole,
  with its range: `18:20–19:25 · Social · 1h 5m`.
- **Select, then pick:** click a block to select its whole stretch, double‑click to select just that block, or
  drag to select exactly what you cover. Click a category under the grid to log the selection, or Clear to empty
  it. The selection stays, and its category stays lit, until you click off the blocks.
- **Pick, then paint:** with nothing selected, click a category and drag across blocks. The category is put down
  after one drag, so a stray click never logs anything.
- **Menu bar:** one click logs the block in progress, optionally filling the unlogged gap before it.

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
xcodebuild -project TimeBlock.xcodeproj -scheme TimeBlock -derivedDataPath .build/xcode build && open .build/xcode/Build/Products/Debug/TimeBlock.app
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

The project signs ad‑hoc ("Sign to Run Locally"), which needs no Apple account. Sharing settings between the
app and the widget needs an App Group, and App Groups need an Apple Developer team. Until one is set up, the
widget always shows the default 07:00–23:00 schedule and no logs. To enable it, pick your team for both targets under
Signing & Capabilities and add the App Group `group.dev.timeblock` to both.
