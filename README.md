# nxnative Launcher

A game library for [nxnative](https://github.com/seedds/nxnative) on the Mac. nxnative builds each Switch game into a native Mac app, and it ships inside the launcher. The launcher keeps those apps in one place:

- **All your games** in a library tinted with each game's colors: a hero for the game you played last, rows of covers, and a page per game.
- **Add Game**: choose a game's NSP folder. nxnative builds it in the background with a progress bar, the current stage, its ETA and the live log. The finished app joins the library.
- **Playtime**: every session is timed, including games opened from Finder while the launcher runs. Each game shows its total, when it was last played and the last eight weeks as a chart.
- **Artwork and titles** come from the game's own app: its icon, its name and the colors taken from the icon. nxnative's games table adds the engine, SDK, build and graphics API.

The look follows macOS 26's Liquid Glass: glass controls and cards over a backdrop drawn from the selected game's icon. Settings can switch the buttons to solid colors and change the window's color.

What changed in each version: [CHANGELOG.md](CHANGELOG.md).

## Requirements

- An Apple silicon Mac with macOS 26 or later.
- nxnative's build tools: Xcode, the .NET SDK 10, and Homebrew's `zstd` and `spirv-cross`. nxnative itself is inside the launcher, and its Python modules go into a private environment with one click.
- Your own `prod.keys`. The launcher stores only the file's location, passes it to nxnative, and never opens or shows the file.

## Install

Choose either way. Both give the same app.

### Download a release

1. Download `NxLauncher-<version>.dmg` from the [latest release](https://github.com/rexxless/nxlauncher/releases/latest).
2. Open it and drag **NxLauncher** onto **Applications**. Eject the disk image.
3. Open NxLauncher from Applications or Launchpad.

**The first launch needs one extra step.** The app is not notarized by Apple, so the first time macOS stops it, saying Apple could not verify it is free of malware. Either:

- Click **Done**, open **System Settings → Privacy & Security**, scroll down to the message that NxLauncher was blocked and click **Open Anyway**, then confirm. macOS asks only once.
- Or remove the download mark in Terminal:

  ```sh
  xattr -dr com.apple.quarantine /Applications/NxLauncher.app
  ```

### Build it yourself

Building needs Swift 6.2 or later, from Xcode or the Command Line Tools. Apps you build on your own Mac open without the step above.

```sh
git clone --recurse-submodules https://github.com/rexxless/nxlauncher.git
cd nxlauncher
scripts/make_app.sh                # → build/NxLauncher.app
cp -R build/NxLauncher.app /Applications/
```

Already cloned without `--recurse-submodules`? Run `git submodule update --init` first: nxnative is the submodule `vendor/nxnative`.

The other scripts:

```sh
scripts/make_dmg.sh                # → build/NxLauncher-<version>.dmg, the app beside an Applications link
scripts/make_app.sh --sign "Developer ID Application: <name> (<team>)"   # make_dmg.sh takes --sign too
scripts/test.sh                    # the tests (swift test, with the SDK settings below)
```

The version comes from the git tag (`v1.0.0` → 1.0.0). The Command Line Tools' newest SDK declares SwiftUI's `@State` as a macro, but its plugin ships only with Xcode. Without Xcode, `make_app.sh` builds against a macOS 26 SDK from the Command Line Tools. For a plain `swift build` without Xcode, set `SDKROOT` the same way:

```sh
SDKROOT=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.*.sdk | sort -V | tail -1) swift build
# swift test also needs -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing: scripts/test.sh adds it
```

## Use

### First run

1. On first launch the launcher unpacks the nxnative it ships (about 150 MB) into `~/Library/Application Support/NxLauncher/nxnative`. Home's **Ready to Build** list shows anything still missing, each with a button that fixes it:
   - **Python modules**: **Install** makes a private Python environment (`~/Library/Application Support/NxLauncher/python`) with lz4, capstone and fontTools (and backports.zstd before Python 3.14). The system's and Homebrew's Python are left alone.
   - **Keys file**: opens Settings at the keys row, to choose your `prod.keys`.
   - **Build tools**: installs `zstd` and `spirv-cross` with Homebrew, or links to Xcode and .NET.
   - To build with your own clone of nxnative instead, choose it in Settings (**Choose Clone…**). **Use Bundled** goes back.
2. Press **Add Game** (⌘N) and choose a game's NSP folder. The sheet names the game when nxnative has a profile for it. Otherwise it warns that the build will use a provisional profile and may not boot.
3. Follow the build in **Builds**. When it finishes, press **Play**.

Games you built before the launcher can be added in Settings. Add the folder that holds them (the launcher searches it two levels deep), or add the apps themselves.

### Every day

- **Library**: Home, All Games, Recently Played, Favorites (right-click a game to add it) and a list per graphics API, in the sidebar. Search with ⌘F.
- **A game's page** shows its playtime chart, its details and **Play**.
- **Builds** run one at a time: each one uses every core and a lot of memory. Cancelling a build interrupts nxnative as Ctrl-C would, so it stops cleanly.
- **Settings** (⌘,): library folders, the keys file, the Python and nxnative in use with its version and updates (below), and **Appearance**: Liquid Glass or solid buttons, the button color and opacity, the window color when no game is chosen, and how strongly the window is tinted.

| Shortcut | Does |
|---|---|
| ⌘N | Add Game |
| ⌘1 / ⌘2 / ⌘3 / ⌘4 | Home / All Games / Builds / Playtime |
| ⌘F | Search |
| ⌘[ | Back from a game's page |
| ⌘R | Rescan the library |
| ⌘, | Settings |

### Update

Install the new version the same way, over the old one: drag it onto Applications and choose **Replace**, or rebuild with `git pull --recurse-submodules && scripts/make_app.sh`. The library, playtime and settings live outside the app and carry over. A new launcher brings its own nxnative and unpacks it on its first launch, unless the engine was already updated past it.

#### nxnative updates

nxnative gains games and fixes far more often than the launcher is released, so the launcher can update it on its own. Settings → **Engine** shows:

- **Version**: the nxnative commit in use and its date, marked *bundled* (the app's own copy) or *updated* (downloaded since).
- **Updates**: **Check Now** asks GitHub whether nxnative's `main` branch has newer commits. If so, the row shows how many, the latest commit's message and a **What's New** link, and **Update** downloads and installs it. **Use Bundled** goes back to the app's own copy.
- **Auto-update** (on by default): checks at launch and every six hours, and installs what it finds. A notification says when nxnative was updated.

An update never replaces the engine under a running build: it waits until the builds are finished. After an update, **Ready to Build** checks again, in case the new nxnative needs another Python module. Your own clone (**Choose Clone…**) is never touched: update it with git. This is the only time the launcher goes online, to `api.github.com` and `codeload.github.com`.

### Uninstall

Delete `/Applications/NxLauncher.app`, then, to remove everything else, `~/Library/Application Support/NxLauncher` and the settings (`defaults delete org.nxnative-launcher.app`). The games you built stay in their NSP folders.

## Where things are

| What | Where |
|---|---|
| Library and playtime | `~/Library/Application Support/NxLauncher/` (`library.json`, `playtime.json`) |
| The shipped nxnative, unpacked | `~/Library/Application Support/NxLauncher/nxnative` (replaced by an update, or when the launcher brings a newer version; its commit is in `.nxl-version`) |
| The private Python | `~/Library/Application Support/NxLauncher/python` |
| Settings (paths and appearance) | the app's user defaults (`org.nxnative-launcher.app`) |
| Built games | the NSP folder, as nxnative writes them (`<game name>.app`) |
| A game's save and log | nxnative's: `~/Library/Application Support/nxnative/<title ID>/`, `~/Library/Logs/nxnative/<title ID>.log` |

## Layout

- `Sources/LauncherCore`: the logic, without UI, all tested.
  - `BuildEvent` / `BuildProgress`: nxnative's `--progress json` events, folded into progress.
  - `BuildRunner`: the build process, cancelling it, and its outcome.
  - `GameBundle` / `LibraryState`: nxnative apps and the library.
  - `Catalog`: nxnative's games table.
  - `PlaytimeLog`: sessions and totals.
  - `Palette`: the colors taken from an icon. `Appearance`: the user's buttons and window color.
  - `Preflight`: the checks before a build, and what fixes each one.
  - `Engine`: unpacking the shipped nxnative. `EngineUpdate`: newer nxnative from GitHub. `PythonSetup`: the private Python.
- `Sources/NxLauncher`: the SwiftUI app.
- `vendor/nxnative`: nxnative, as a submodule. `make_app.sh` packs it into the app as `nxnative.tar.gz`.
- `scripts/make_app.sh`: builds the app bundle. `scripts/make_dmg.sh`: packs it into a disk image. `scripts/make_icon.swift` draws the launcher's icon.
- `docs/design.md`: the design.

For layout work without a screen recorder, `NXL_SNAPSHOT=<folder> build/NxLauncher.app/Contents/MacOS/NxLauncher` renders each screen to `<folder>/<screen>.png` and quits. The renderer draws neither glass nor text fields as the window does.

## Releasing

1. Add the version to `CHANGELOG.md`, commit, and tag it: `git tag -a v1.1.0 -m "nxnative Launcher 1.1.0"`.
2. `scripts/make_dmg.sh` → `build/NxLauncher-1.1.0.dmg`.
3. `git push --follow-tags`, then `gh release create v1.1.0 build/NxLauncher-1.1.0.dmg --title "nxnative Launcher 1.1.0" --notes "…"`.

## Credits

The engine is [nxnative](https://github.com/seedds/nxnative) by seedds, MIT License: the NSO rewriter, the Horizon host and NVN, Vulkan and OpenGL on Metal that turn a Switch game into a Mac app. The launcher ships it unchanged (`vendor/nxnative`) and only runs its `scripts/build_ipa_from_nsp.py --platform mac-app`.

## License

MIT, as nxnative.
