# Mihon iOS Modularization (RFC)

This document is the working agreement for incrementally modularizing the Mihon iOS codebase. The goal is to improve maintainability and build performance without a risky "big bang" rewrite.

## Goals
- Reduce "god files" (target soft limit: 300–500 lines per file).
- Introduce real module boundaries using local Swift Packages (SPM).
- Make feature ownership clearer (Reader/Browse/Library/etc).
- Improve testability by separating domain models and protocols from app wiring.

## Non-Goals
- No UI redesign.
- No behavior changes as part of pure "move/split" PRs.
- No immediate rewrite of all features to a new architecture.

## Target Module Graph
- `MihonApp` (Xcode app target)
  - depends on `MihonFeature*`, `MihonData`, `MihonUI`, `MihonDomain`
- `MihonFeature*` (Swift packages)
  - depend on `MihonUI` and `MihonDomain`
  - do not import the app target
- `MihonData` (Swift package)
  - depends on `MihonDomain`
- `MihonDomain` (Swift package)
  - depends only on `Foundation`
- `MihonUI` (Swift package)
  - depends on `SwiftUI` (and may depend on `MihonDomain`)

## Hard Rules
- Domain code must not import `SwiftUI` or `UIKit`.
- Feature modules must not depend on the app target.
- Data code depends on Domain, not on feature code.

## Migration Order (to keep diffs small)
1. Split large files into topic-based files while staying in the app target.
2. Move Domain into `Modules/MihonDomain`.
3. Move Data into `Modules/MihonData`.
4. Move the Reader feature into `Modules/MihonFeatureReader`.
5. Repeat for other features and progressively shrink `AppModel` usage.

## File Splitting Conventions
- Prefer "topic files" over "mega files":
  - `X+Y.swift` extensions for protocol conformances (`AppModel+Library.swift`).
  - Feature subviews extracted into separate files when they grow past ~200–300 lines.
- Avoid renames while moving code between targets. Do renames as a follow-up.

