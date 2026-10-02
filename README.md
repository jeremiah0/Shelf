# Shelf

Shelf is a macOS game library manager for organizing and launching games from Steam, Epic Games, GOG, CrossOver, emulators, and local Mac apps in one clean library.

It helps you keep your collection in one place, discover metadata and artwork, and launch games without bouncing between multiple launchers.

## Features

- Import installed games from supported launchers and local apps
- View your library in a polished SwiftUI interface
- Organize by favorites, recent play history, categories, and tags
- Search across titles, genres, developers, and collections
- Refresh metadata and cover art using supported game-data sources
- Launch games directly from Shelf, including launcher-specific flows
- Track play counts, favorites, and last-played dates
- Configure optional API keys for richer metadata enrichment

## Supported sources

Shelf can work with:

- Steam
- Epic Games Launcher
- GOG
- CrossOver bottles
- Emulators and local executables
- Mac applications

## Metadata and artwork

Shelf can enrich entries with details from:

- IGDB
- Steam Store
- SteamGridDB

These services are optional and can be configured during setup or later in the app.

## Requirements

- macOS 14 or later
- Swift toolchain

## Building the project

```bash
cd Shelf
swift build
```

To build a packaged app bundle:

```bash
./build-app.sh
```

This will produce a macOS app bundle in `build/Shelf.app`.

## Running

After building, open the generated app bundle or run the executable from the Swift build output.

## Notes

This project is a personal app and is not affiliated with or endorsed by Steam, Epic Games, GOG, or CrossOver. The app uses external game metadata and artwork where available, with attribution to the respective services.

## Repository status

This project is intended to be public-facing and is ready for upload to a GitHub repository as-is, with the app bundle and local build artifacts ignored via the project `.gitignore`.
