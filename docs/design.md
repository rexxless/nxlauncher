# nxnative Launcher: design

## Context

nxnative builds each Switch game into a self-contained Mac app: `scripts/build_ipa_from_nsp.py <NSP folder> -k <prod.keys> --platform mac-app`. Today you build from a terminal and open the resulting `.app` files from Finder. The goal is a separate, good-looking launcher in the style of GameHub (gamemac.com) and mapc.games, with Liquid Glass, big colorful art and a modern macOS look. It should:
1. Show all your games.
2. Add a game: run the nxnative engine in the background and show a progress bar.
3. Track playtime.
4. Show each game's artwork and title.

Decisions (from the user):
- Native **SwiftUI for macOS 26**, using the real Liquid Glass APIs.
- **Mac apps only**: no IPA builds in the launcher.
- **Game icon only** for artwork: no network access.
- A **new local repo plus a private GitHub repo** (`gh repo create --private`).
- The repo will be made public later, so it must hold **no secrets or personal data**: no key paths, no user names or emails, no home-folder paths, and no game files or game art in the repo or its tests.

What nxnative already provides (no engine changes are needed):
- **Machine-readable build progress.** `--progress json` writes one JSON object per stdout line (`scripts/build_ipa_from_nsp.py:91-183`):
  - `{"ev":"stage","k","n","name","step","t"}`
  - `{"ev":"step","k","name","step"}`
  - `{"ev":"progress","k","name","step","done","total","unit","est","note","frac","eta","elapsed"}`
  - `{"ev":"stage_end","k","name","ok","summary","elapsed"}`
  - `{"ev":"say","msg"}`

  JSON mode never prompts. Exit codes are 0 (success), 1 (error) and 130 (interrupted, which is how Cancel works: send SIGINT).
- **A fixed Mac app layout** (`docs/development.md` "A Mac app", `dm/mac/pack_app.py`):
  - `Contents/Info.plist` has `CFBundleName`, `CFBundleShortVersionString`, the bundle ID `org.nxnative.<title id lowercase>`, `DMTitleID` and `DMLanguage`.
  - The icon is `Contents/Resources/AppIcon.icns`.
  - By default the app is written as `<NSP folder>/<game name>.app`. `-o` sets another path.
  - Saves are in `~/Library/Application Support/nxnative/<id>/`. Logs are in `~/Library/Logs/nxnative/<id>.log`.
- **Game metadata.** `dm/games/README.md#games` has a row per game with its title ID, build, SDK, engine and graphics API. `python3 dm/games/game.py list` lists the profiles.

## Repository

The new repo goes in a sibling folder, `~/projects/nxlauncher` (outside the nxnative checkout):

```
Package.swift               LauncherCore library, the NxLauncher app target and tests; builds with the Command Line Tools alone
scripts/make_app.sh         swift build -c release → build/NxLauncher.app (Info.plist, icon from scripts/make_icon.swift, ad-hoc signature)
Sources/LauncherCore/       pure logic, no SwiftUI
  BuildEvent.swift          Decodable enum for the 5 event types; tolerant of unknown keys/events
  BuildRunner.swift         Process wrapper: python3 build_ipa_from_nsp.py <nsp> -k <keys> --platform mac-app --progress json [-o]; line-buffered stdout → AsyncStream<BuildEvent>; stderr+say lines kept as a log; cancel = SIGINT, then SIGTERM after 10 s
  BuildProgress.swift       folds events into overall fraction ((k-1 + frac)/n, indeterminate when frac is nil), current stage/step, ETA, stage history
  GameBundle.swift          reads a .app's Info.plist: name, version, titleID, language, bundle ID; rejects bundles without DMTitleID
  Library.swift             library = user-chosen folders scanned (depth 2) for nxnative .apps + apps produced by builds; persisted as bookmarks/paths in Application Support/NxLauncher/library.json
  Catalog.swift             parses the nxnative checkout's dm/games/README.md games table → titleID → {engine, graphics, build, SDK, note path}; "supported" check for an NSP folder's title
  Playtime.swift            sessions [{titleID, start, end}] in Application Support/NxLauncher/playtime.json; totals, last played, per-week chart data; open-session heartbeat so a launcher crash loses ≤60 s
  Palette.swift             dominant/accent colors from the icon (downsample to 32×32, k-means k=4, sort by saturation) → used for gradients
  Preflight.swift           checks: nxnative checkout path valid, python3 found (/opt/homebrew/bin, /usr/local/bin, /usr/bin), imports lz4/capstone/fontTools, Apple silicon, keys file readable (path never logged)
Sources/NxLauncher/         SwiftUI app target
  NxLauncherApp.swift       WindowGroup + Settings scene; .windowStyle(.hiddenTitleBar), full-size content
  Views/Sidebar.swift       glass sidebar: Home, All Games, Recently Played, Favorites, Building (badge), Settings
  Views/HomeView.swift      hero banner of last-played game (enlarged blurred icon over MeshGradient from Palette, title, playtime, big Play button), "Continue playing" carousel, stats strip (total hours, games, this week)
  Views/LibraryGrid.swift   LazyVGrid of cover cards: icon on palette gradient, title, playtime; hover lift + glass overlay; search (.searchable), sort (name / last played / playtime), favorites
  Views/GameDetailView.swift hero header, Play, playtime + last 8 weeks bar chart (Swift Charts), engine/graphics/build chips from Catalog, Show in Finder, Open save folder, Open log, Remove from library (not delete)
  Views/AddGameSheet.swift  pick NSP folder (NSOpenPanel), detect title via Catalog (supported / provisional warning), optional language, output folder; Start
  Views/BuildsView.swift    active + finished builds: glass card with overall progress bar, stage "k/n · name · step", ETA, expandable stage list with ✓/✗ and durations, collapsible live log, Cancel; on success the new app is added and a notification posted
  Views/SettingsView.swift  nxnative checkout folder, prod.keys file, python3 path, library folders; preflight results with fix hints
  Glass.swift               shared styles: .glassEffect(.regular.interactive()), GlassEffectContainer for card groups, .buttonStyle(.glass/.glassProminent)
  GameLauncher.swift        NSWorkspace.openApplication(at:) → NSRunningApplication; observes didLaunch/didTerminate for bundle IDs "org.nxnative.*" so games opened from Finder are timed too
Tests/LauncherCoreTests/    fixtures are synthetic only (hand-written JSON event streams, a fake .app with a made-up title ID, a trimmed made-up games table)
README.md, LICENSE (MIT, as nxnative's), .gitignore (build/, .build/, .DS_Store, *.keys, *.nsp, *.nsz, *.xci, *.xcz)
```

### Visual reference (mapc.games screenshots the user sent): the target layout

- **Tinted window.** The whole window takes on the selected game's color: the sidebar, the content and the search field are all tinted with that game's palette. The sidebar is a translucent darker shade of the same color. Switching games cross-fades the tint (0.4 s).
  - Implementation: `Palette` gives `base`, `deep` and `accent`.
  - The app-wide `@Observable ThemeModel.current` drives `.containerBackground` and the sidebar fill.
- **Sidebar** (matching the reference sections):
  - **Home**, as a selected glass pill.
  - **Library**: All Games (count) and Recently Played (count).
  - **Graphics**: NVN, Vulkan and OpenGL with counts, from `Catalog`. This takes the place of the reference's "Stores" section.
  - **Activity**: Builds (the reference's "Downloads", with a live progress ring while a build runs) and Playtime.
  - The search field sits at the top right.
- **Home**:
  - A full-bleed hero labeled "CONTINUE PLAYING" for the last-played game. The game title is set in large, heavy type, since nxnative has no logo art.
  - Below the title: a white glass **Play** capsule and a circular **ⓘ** glass button that opens the detail page.
  - The hero's art is the game icon, scaled up on the right and faded into the tint with a gradient mask. A blurred, oversized copy of the icon fills the background so the colors carry across the window.
  - Under the hero, a **"Ready to Play"** horizontal row of cover cards with "See All". Each card shows the icon on a palette gradient with rounded corners and a shadow, then the title and a meta line ("NVN · 4.2 GB").
  - Then a **"Graphics"** row of glass tiles (NVN, Vulkan, OpenGL), mirroring the reference's "Stores" row.
- **Game detail page** (screenshots 2 and 3):
  - A back chevron in a glass circle, and the game name in the toolbar.
  - A hero with the large title, then a meta line: "Engine · SDK 17.5.3 · Build 1.0.1 · NVN".
  - Buttons: **Play** (a dark capsule on light tints, white on dark tints, picked by luminance), a folder button (show the app in Finder) and a **⋯** menu (open the save folder, open the log, open the nxnative note, remove from library).
  - A thin rule, then a stats strip of uppercase small-caps labels over large values, split by vertical hairlines:
    - **ENGINE**
    - **BUILD**
    - **SDK**
    - **PLAYED**
    - **LAST PLAYED** ("2 days ago", or the date)
    - **SIZE** (the bundle size, computed in the background)
    - **GRAPHICS**
  - An **ABOUT** section with the title ID, language and version. This stands in for the reference's description text, since a Switch game's control data has none.
  - A **PLAYTIME** section: the last 8 weeks as a Swift Charts bar chart in the accent color, in the place of the reference's "SCREENSHOTS" row.
- **Glass:** the buttons, search field, sidebar selection and toolbar circles use `.glassEffect(.regular.tint(accent).interactive())` inside a `GlassEffectContainer`. The cover cards are solid art with a glass hover state.

### Key behaviors

- **Finding the built app.** First take the path the build reports in a `say` line ending in `.app`. If there is none, scan the NSP folder (or the `-o` folder) for nxnative `.app` bundles changed after the build started, and match them by `DMTitleID`.
- **Running builds.**
  - Builds run one at a time, in a queue. The engine's builds use a lot of CPU and memory, so running them in parallel would hurt.
  - The child gets `PATH` set to include `/opt/homebrew/bin:/usr/local/bin` (the script also has `TOOL_PATHS`).
  - The working directory is the nxnative checkout.
- **Privacy and safety.**
  - The keys path is stored in `UserDefaults` only and never written to the log view or to the repo.
  - The launcher never prints key values: it only passes the path through to the script.
  - The engine's own output is shown as it comes. The script already never prints keys.
- **Disk space.** Nothing large goes in the home folder. The launcher keeps only small JSON files in Application Support. Builds write to the NSP folder, as nxnative does.
- **Playtime.**
  - A session starts when a game's `NSRunningApplication` launches and ends when it terminates.
  - Sessions under 10 s are dropped (failed starts).
  - Totals are shown as "12 h 34 m".
- **Look and feel.**
  - Liquid Glass is used for the sidebar, toolbars, cards and the progress panel.
  - Behind the glass are color-rich backgrounds made from each icon's palette (`MeshGradient`) with a large blurred copy of the icon, so the glass has color to pick up.
  - Spring animations on hover and selection.
  - Light and dark mode both work, and Reduce Transparency is respected by falling back to solid fills.

## Build notes

- No Xcode project: the package builds with `swift build`, and `scripts/make_app.sh` makes the bundle.
- The Command Line Tools have no SwiftUI macro plugin. The newest SDK declares `@State` as a macro, so without Xcode the app builds against a macOS 26 SDK. The code also avoids `@Entry` and `#Preview`.
- The launcher's bundle ID is `org.nxnative-launcher.app`, not under `org.nxnative.`, so it is never mistaken for a game. Game detection also needs a 16-digit hex title ID.
- `NXL_SNAPSHOT=<folder>` renders each screen to PNG with `ImageRenderer`, and `NXL_SNAPSHOT_BUILD=<NSP folder>` also runs a build. These are for checking the layout where the screen cannot be recorded.

## Verification

- `swift test`: LauncherCore unit tests, including a recorded synthetic event stream that reaches exactly 100% and a cancelled build that maps to exit code 130.
- `scripts/make_app.sh` succeeds, and the app starts and shows the empty-state onboarding.
- **End to end on this Mac.** In Settings, point the launcher at the nxnative checkout and a prod.keys file on the game drive, then add one supported game's NSP folder (for example a small one like Balatro or Celeste).
  - The progress bar moves stage by stage and the ETA shows.
  - On success the game appears with its icon and title.
  - Play opens it.
  - After quitting, its playtime shows in the card and the detail chart.
- **Cancel** mid-build: the status shows "Cancelled" and the process is gone (`pgrep -f build_ipa_from_nsp` is empty).
- **Repo hygiene:** `git grep -nE '/Users/|gmail|\.keys'` shows only `.gitignore` patterns and docs placeholders.

## Revision 2: the shipped engine and fix buttons

- **Color.** With no game to take colors from, the window is deep indigo (`Palette.fallback`: base #3B3F8F, deep #1C1E4A, lavender accent), not red.
- **nxnative ships in the launcher.** It is the submodule `vendor/nxnative`; `make_app.sh` packs a `git archive` of it into `Contents/Resources/nxnative.tar.gz` with its commit in `nxnative.version`. A build writes into its checkout (`dm/host/gen`, the profile's shader tables), so the signed copy is not run in place: `Engine.unpack` extracts it into `~/Library/Application Support/NxLauncher/nxnative` once per version, beside the old copy, and swaps it in only when complete. Settings can still choose a clone instead (an empty `checkoutPath` means the shipped one).
- **Every failed check has a fix** (`Preflight.Fix`), shown as a button in the Ready to Build list:
  - Python modules: `PythonSetup` makes a venv in `~/Library/Application Support/NxLauncher/python` from the chosen Python and pip-installs the missing modules (`backports.zstd` too before Python 3.14), then uses its Python. Homebrew's Python refuses plain pip installs, and the system's is left alone.
  - Keys file and engine: go to Settings, scroll to the row and highlight it; in Settings the button opens the file picker.
  - Build tools (new check, the script's `check_prereqs`): `brew install zstd spirv-cross`, or links to Xcode and .NET.
- Child processes for these (tar, pip, brew, the module probe) run through `ProcessLines`, which reads output as it comes and waits on the termination handler: blocking waits starved Swift's concurrency pool when tests ran in parallel.
