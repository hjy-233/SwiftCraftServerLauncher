<div align="center">
  <img src="SwiftCraftServerLauncher/Assets.xcassets/AppIcon.appiconset/mac512pt2x.png" alt="SwiftCraftServerLauncher icon" width="128" height="128">

  <h1>SwiftCraftServerLauncher</h1>

  <p>A native macOS app for managing Minecraft Java Edition servers.</p>

  <p>
    <strong>English</strong> |
    <a href="doc/README_zh-CN.md">简体中文</a>
  </p>
</div>

SwiftCraftServerLauncher is a desktop app focused on the day-to-day work of running Minecraft servers on macOS. Instead of acting as a general game launcher, it is built for server owners who want one place to create servers, start and stop them, inspect logs, edit configuration, and manage server resources.

## Quick Start

1. Download the latest build from [Releases](https://github.com/hjy-233/SwiftCraftServerLauncher/releases/latest).
2. Open the downloaded DMG and move `SwiftCraftServerLauncher.app` into `Applications`.
3. Launch the app and create your first local server instance.

## What It Can Do

- Create and manage local server instances
- Support `Vanilla`, `Paper`, `Fabric`, `Forge`, and `Custom Jar` server setups
- Browse and install server resources from Modrinth
- Start and stop servers, inspect live console output, and review log files
- Edit runtime settings, `server.properties`, player lists, worlds, mods, and plugins
- Configure schedule-based automation for routine server actions

## Current Limitations

- Local server management is the primary supported workflow
- Remote node management over SSH is still experimental and currently not reliable enough to be treated as a finished feature

## Project Scope

This repository is the server-management focused branch of the Swift Craft Launcher ecosystem.

- Server management is the priority
- Local node workflows come first
- Modrinth is the current resource source
- The app is designed as a native SwiftUI macOS experience

## Status

- Active development
- Public releases are available on the [Releases](https://github.com/hjy-233/SwiftCraftServerLauncher/releases) page
- Source builds remain supported for development and testing

## Requirements

- macOS 14 or later
- Xcode 15 or later recommended for local builds

## Build From Source

1. Clone the repository:

```bash
git clone https://github.com/hjy-233/SwiftCraftServerLauncher.git
cd SwiftCraftServerLauncher
```

2. Open the project in Xcode:

```bash
open SwiftCraftServerLauncher.xcodeproj
```

3. Run the `SwiftCraftLauncher` scheme in Xcode.

## Contributing

- English guide: [doc/CONTRIBUTING_en.md](doc/CONTRIBUTING_en.md)
- Chinese guide: [CONTRIBUTING.md](CONTRIBUTING.md)
- Bug reports and requests: [GitHub Issues](https://github.com/hjy-233/SwiftCraftServerLauncher/issues)

## License And Attribution

This project is licensed under **GNU AGPL v3.0** with additional attribution terms.

- License: [LICENSE](LICENSE)
- Additional terms: [doc/ADDITIONAL_TERMS.md](doc/ADDITIONAL_TERMS.md)

This project is based on [Swift-Craft-Launcher](https://github.com/suhang12332/Swift-Craft-Launcher), with the scope narrowed toward Minecraft server management.
