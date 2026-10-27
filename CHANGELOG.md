# Changelog

All notable changes to nxnative Launcher. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- **Launcher updates**: Settings → Launcher shows the launcher's version and checks its GitHub releases, at launch and every six hours or with **Check Now**. A new version is offered with its changelog. **Update and Relaunch** downloads it, checks the app inside (the same app, the release's version, its signature intact), swaps it in and reopens. It waits while a build runs.
- **Built by rexxless** in Settings, linking to GitHub, beside the credit for nxnative.

### Changed

- **nxnative updates ask first.** A scheduled check that finds a newer nxnative opens a window with the new commits and a link to all the changes, and installs only when you press **Update nxnative**. **Later** skips that version until a newer one appears.

## [1.1.0] - 2026-10-27

### Added

- **nxnative updates**: Settings → Engine shows the nxnative commit in use and its date, and checks GitHub for newer commits on nxnative's main branch: how many, the latest one's message and a link to what changed. **Update** downloads and installs it, and **Use Bundled** goes back to the copy inside the launcher.
- **Auto-update engine** (on by default): checks at launch and every six hours and installs a newer nxnative on its own, then posts a notification. An update waits for running builds to finish, and Ready to Build checks again afterwards.

### Changed

- An updated nxnative is kept across launches. A newer launcher replaces it only when its own copy is newer.
- The launcher now goes online, only to GitHub and only for nxnative updates. Turn **Auto-update** off to keep it offline until you press **Check Now**.

## [1.0.0] - 2026-10-27

The first release.

### Added

- **Library**: Home with a hero for the game you played last and rows of covers, All Games, Recent, Favorites and a list per graphics API. Each game has its own page. The window takes its colors from the selected game's icon.
- **Search** across the library (⌘F).
- **Add Game** (⌘N): choose a game's NSP folder and nxnative builds it in the background. The sheet names the game when nxnative has a profile for it, and warns when the build will use a provisional profile.
- **Builds**: a progress bar, the current stage, the ETA and the live log. Builds run one at a time, and cancelling one stops nxnative cleanly, as Ctrl-C would. The finished app joins the library.
- **Playtime**: every session is timed, including games opened from Finder while the launcher runs. Each game shows its total, when it was last played and its last eight weeks as a chart.
- **Artwork and titles** from each game's own app, plus the engine, SDK, build and graphics API from nxnative's games table.
- **nxnative ships inside the launcher** (seedds/nxnative at `be5b197`) and is unpacked on first launch. Settings can switch to your own clone and back.
- **Ready to Build** checks, each with a fix: one click installs nxnative's Python modules into a private environment, opens Settings to choose `prod.keys`, installs `zstd` and `spirv-cross` with Homebrew, or links to Xcode and .NET.
- **Existing games**: add a folder of games built before the launcher (searched two levels deep) or the apps themselves.
- **Appearance** in Settings: Liquid Glass or solid buttons, the button color (the game's or your own) and opacity, the window color when no game is chosen (deep indigo by default), and how strongly surfaces are tinted.
- **Keyboard shortcuts**: ⌘1 Home, ⌘2 All Games, ⌘3 Builds, ⌘4 Playtime, ⌘R Rescan Library, ⌘[ Back, ⌘, Settings.
- **A disk image** for installing: drag the app onto Applications.

### Known limitations

- Apple silicon and macOS 26 or later only.
- The app is not notarized by Apple. The first launch needs **Open Anyway** in System Settings → Privacy & Security (see the README).

[1.1.0]: https://github.com/rexxless/nxlauncher/releases/tag/v1.1.0
[1.0.0]: https://github.com/rexxless/nxlauncher/releases/tag/v1.0.0
