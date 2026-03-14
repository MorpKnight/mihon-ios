# Mihon iOS

Native iOS migration of Mihon, built with SwiftUI and guided by Mihon Android as the behavioral reference.

## Status

This repository is an active migration project. The current iOS build already includes:

- native tab shell for `Library`, `Browse`, `History`, `Updates`, and `More`
- local import pipeline for folders and image-based content
- production-oriented reader baseline with multiple reading modes
- runtime source integration for `Kiryuu`
- source catalog, tracking surface, backup surface, and settings hierarchy

The project is not yet feature-complete with Mihon Android. Some areas remain in progress, especially:

- full backup restore
- full tracker auth integrations
- broader source engine coverage
- richer download/background behavior

## Goals

- preserve Mihon behavior where it matters
- adapt UI and navigation to native iOS conventions
- keep source runtimes and reader behavior modular
- make the codebase easy to contribute to incrementally

## Project Structure

```text
Mihon IOS/
  App/        App shell, boot flow, top-level state orchestration
  Core/       Shared helpers and extensions
  Data/       Persistence, import pipeline, source repositories
  Features/   User-facing screens grouped by feature
```

## Source Strategy

This repository does not support Android APK extensions directly.

Instead, iOS source support is implemented as native runtime engines. At the moment:

- `Kiryuu` is implemented through a reusable `NatsuId`-style runtime
- `extensions-source` is treated as a local research/reference repository and is intentionally excluded from version control here

## Getting Started

1. Open [`Mihon IOS.xcodeproj`](/Users/giovan/Programming/Mihon%20IOS/Mihon%20IOS.xcodeproj) in Xcode.
2. Use a unique bundle identifier and your own signing team for device builds.
3. Build and run on Simulator or iPhone.

### Requirements

- Xcode 26.3 or newer
- iOS 26.2 deployment target or newer

## Contributing

Please read [CONTRIBUTING.md](./CONTRIBUTING.md) before opening a pull request.

For behavior questions, Mihon Android should be treated as the reference unless iOS platform conventions require a native adaptation.

## Development Notes

- Prefer small, focused pull requests.
- Keep reader and source-runtime changes isolated and testable.
- Avoid checking in local reference repos or machine-specific files.

## License

This project is licensed under the Apache License 2.0. See [LICENSE](./LICENSE).
