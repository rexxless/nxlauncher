# nxnative Launcher

A game library for [nxnative](https://github.com/seedds/nxnative) on the Mac. nxnative builds each Switch game into a native Mac app, and it ships inside the launcher. The launcher keeps those apps in one place:

- **All your games** in a library tinted with each game's colors: a hero for the game you played last, rows of covers, and a page per game.
- **Add Game**: choose a game's NSP folder. nxnative builds it in the background with a progress bar, the current stage, its ETA and the live log. The finished app joins the library.
- **Playtime**: every session is timed, including games opened from Finder while the launcher runs. Each game shows its total, when it was last played and the last eight weeks as a chart.
- **Artwork and titles** come from the game's own app: its icon, its name and the colors taken from the icon. nxnative's games table adds the engine, SDK, build and graphics API.

The look follows macOS 26's Liquid Glass: glass controls and cards over a backdrop drawn from the selected game's icon.

## Requirements

- An Apple silicon Mac with macOS 26 or later.
- nxnative's build tools: Xcode, the .NET SDK 10, and Homebrew's `zstd` and `spirv-cross`. nxnative itself is inside the launcher, and its Python modules go into a private environment with one click.
- Your own `prod.keys`. The launcher stores only the file's location, passes it to nxnative, and never opens or shows the file.

## Build

Building needs Swift 6.2 or later: Xcode or the Command Line Tools. nxnative is the submodule `vendor/nxnative`:

```sh
git submodule update --init    # once, after cloning
scripts/make_app.sh            # → build/NxLauncher.app (ad-hoc signed)
scripts/make_app.sh --sign "Developer ID Application: <name> (<team>)"
scripts/test.sh                # the tests (swift test, with the SDK settings below)
```

The Command Line Tools' newest SDK declares SwiftUI's `@State` as a macro, but its plugin ships only with Xcode. Without Xcode, `make_app.sh` builds against a macOS 26 SDK from the Command Line Tools. For a plain `swift build` without Xcode, set `SDKROOT` the same way:

```sh
SDKROOT=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.*.sdk | sort -V | tail -1) swift build
# swift test also needs -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing: scripts/test.sh adds it
```

## First run

1. On first launch the launcher unpacks the nxnative it ships (about 150 MB) into `~/Library/Application Support/NxLauncher/nxnative`. Home's **Ready to Build** list shows anything still missing, each with a button that fixes it:
   - **Python modules**: **Install** makes a private Python environment (`~/Library/Application Support/NxLauncher/python`) with lz4, capstone and fontTools (and backports.zstd before Python 3.14). The system's and Homebrew's Python are left alone.
   - **Keys file**: opens Settings at the keys row, to choose your `prod.keys`.
   - **Build tools**: installs `zstd` and `spirv-cross` with Homebrew, or links to Xcode and .NET.
   - To build with your own clone of nxnative instead, choose it in Settings (**Choose Clone…**). **Use Bundled** goes back.
2. Press **Add Game** (⌘N) and choose a game's NSP folder. The sheet names the game when nxnative has a profile for it. Otherwise it warns that the build will use a provisional profile and may not boot.
3. Follow the build in **Builds**. When it finishes, press **Play**.

Games you built before the launcher can be added in Settings. Add the folder that holds them (the launcher searches it two levels deep), or add the apps themselves.

## Where things are

| What | Where |
|---|---|
| Library and playtime | `~/Library/Application Support/NxLauncher/` (`library.json`, `playtime.json`) |
| The shipped nxnative, unpacked | `~/Library/Application Support/NxLauncher/nxnative` (replaced when the launcher brings a new version) |
| The private Python | `~/Library/Application Support/NxLauncher/python` |
| Settings (paths only) | the app's user defaults (`org.nxnative-launcher.app`) |
| Built games | the NSP folder, as nxnative writes them (`<game name>.app`) |
| A game's save and log | nxnative's: `~/Library/Application Support/nxnative/<title ID>/`, `~/Library/Logs/nxnative/<title ID>.log` |

Builds run one at a time: each one uses every core and a lot of memory. Cancelling a build interrupts nxnative as Ctrl-C would, so it stops cleanly.

## Layout

- `Sources/LauncherCore`: the logic, without UI, all tested.
  - `BuildEvent` / `BuildProgress`: nxnative's `--progress json` events, folded into progress.
  - `BuildRunner`: the build process, cancelling it, and its outcome.
  - `GameBundle` / `LibraryState`: nxnative apps and the library.
  - `Catalog`: nxnative's games table.
  - `PlaytimeLog`: sessions and totals.
  - `Palette`: the colors taken from an icon.
  - `Preflight`: the checks before a build, and what fixes each one.
  - `Engine`: unpacking the shipped nxnative. `PythonSetup`: the private Python.
- `Sources/NxLauncher`: the SwiftUI app.
- `vendor/nxnative`: nxnative, as a submodule. `make_app.sh` packs it into the app as `nxnative.tar.gz`.
- `scripts/make_app.sh`: builds the app bundle. `scripts/make_icon.swift` draws the launcher's icon.
- `docs/design.md`: the design.

For layout work without a screen recorder, `NXL_SNAPSHOT=<folder> build/NxLauncher.app/Contents/MacOS/NxLauncher` renders each screen to `<folder>/<screen>.png` and quits. The renderer draws neither glass nor text fields as the window does.

## Credits

The engine is [nxnative](https://github.com/seedds/nxnative) by seedds, MIT License: the NSO rewriter, the Horizon host and NVN, Vulkan and OpenGL on Metal that turn a Switch game into a Mac app. The launcher ships it unchanged (`vendor/nxnative`) and only runs its `scripts/build_ipa_from_nsp.py --platform mac-app`.

## License

MIT, as nxnative.
