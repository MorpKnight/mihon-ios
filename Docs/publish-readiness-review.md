# Publish Readiness Review

## Executive Summary

Mihon iOS is a promising native iOS port with meaningful progress across core surfaces such as Library, Browse, Reader, Downloads, Settings, and local persistence. The project already feels like a serious prototype or early beta.

It is not yet ready for a public release. The main reasons are release-process gaps rather than a lack of ambition: project metadata is inconsistent, automated verification is missing, the README overstates some current capabilities, and several important product areas are still partial. Before public publishing, the project needs a focused hardening phase aimed at reliability, truth-in-documentation, and minimum release scope discipline.

## Release Blockers

### 1. README and project reality are out of sync

- The README says the project includes unit and UI tests and shows `xcodebuild test` commands.
- The Xcode project currently contains only one native target, `Mihon IOS`, and no test target.
- This creates a trust problem for contributors and future users because the repository claims validation that is not actually present yet.

### 2. Deployment target and release metadata are inconsistent

- The README says `iOS 15.0+`.
- The Xcode project currently declares `IPHONEOS_DEPLOYMENT_TARGET = 26.2`.
- This mismatch is severe because it affects build expectations, supported-device expectations, and basic release credibility.

### 3. Automated testing is missing

- There is no unit-test target and no UI-test target in the project.
- Core flows such as launch, browse, reader, downloads, and persistence do not have visible automated safety nets in the repo.
- For a content-heavy app with async loading and caching, this is a public-release blocker.

### 4. CI validation is missing

- `.github/` currently contains issue templates and a pull request template, but no GitHub Actions build or test workflow.
- That means every change depends on manual verification, which raises regression risk and makes release quality hard to trust.

### 5. Important feature areas are still incomplete

- The README itself already acknowledges that full backup restore, full tracker auth integrations, broader source engine coverage, and richer download/background behavior are still in progress.
- These are not minor details. They directly affect what users will expect from a public manga-reader release.
- Public publishing should wait until the team defines a minimum supported scope and aligns the app, README, and release messaging around that scope.

### 6. Build verification is blocked in the current shell environment

- `xcodebuild -list -project "Mihon IOS.xcodeproj"` currently fails because the active developer directory is `/Library/Developer/CommandLineTools`, not a full Xcode installation.
- That means this audit could not verify a real local build or test run from the terminal.
- This is not necessarily a repo bug, but it is still a release-readiness gap for the current development setup.

## Stability and Performance Risks

### Oversized app orchestration surface

- [`AppModel`](/Users/giovan/Programming/Mihon%20IOS/Mihon%20IOS/App/AppModel.swift) is the center of a very large amount of app state and cross-feature behavior.
- The type already owns persistence, repositories, downloads, tracking, backup, preferences, caching, diagnostics, lock state, and release-note state, with additional behavior split across many `AppModel+...` extensions.
- This is workable in a prototype, but it raises regression risk as the app moves toward public release because feature interactions become harder to reason about and test safely.

### Async and networking patterns need a consistency pass

- Some flows still use `URLSession.shared` directly, while others use cache-aware repository/controller abstractions.
- Downloads use `Task.detached`, which deserves a careful audit for cancellation, actor isolation, lifecycle ownership, and failure recovery.
- Some source-engine code still includes debug-print patterns and force-unwrapped URL construction, which is acceptable during rapid iteration but should be reduced before release hardening.

### Reader, download, and cache behavior should be stress-tested

- The reader and downloader are central user flows and already contain nontrivial async, caching, prefetching, and persistence behavior.
- That makes them likely hotspots for memory spikes, inconsistent cancellation, stale state, or partial-download edge cases.
- A publish-ready build should be profiled and smoke-tested specifically around long reading sessions, repeated chapter transitions, interrupted downloads, offline reopen, and cache clearing.

## Product and UX Gaps

### Public-facing polish is not fully aligned with public expectations

- The app already has onboarding, release notes, settings, privacy toggles, and multiple core tabs, which is a strong baseline.
- However, public launch quality needs more than surface coverage. It also needs clarity around which features are complete, which are experimental, and which are intentionally limited.
- Areas such as source setup, tracker behavior, restore expectations, download behavior, and failure messaging should feel explicit and predictable before the app is exposed to broad public usage.

### Trust signals need tightening

- Public users judge the app not only by whether it runs, but by whether claims, labels, and behavior match.
- If README language, release notes, settings, and actual project capabilities drift apart, users will experience that as instability even when the code mostly works.
- The current repo would benefit from clearer release messaging that frames the app as an in-progress beta until the hardening work is complete.

## Documentation and Repo Hygiene

### README drift and duplication

- The README contains duplicated and partially conflicting sections.
- It mixes aspirational architecture/testing language with a more realistic project-status section later in the file.
- That makes it harder to tell what is actually true today versus what is planned.

### Architecture documentation is more mature than the verified implementation surface

- [`Docs/architecture/modularization.md`](/Users/giovan/Programming/Mihon%20IOS/Docs/architecture/modularization.md) describes a modular, testable architecture and includes testing-oriented examples.
- The current project layout and target setup do not yet fully prove that level of modularity or test coverage in practice.
- This does not mean the architecture direction is wrong. It means the implementation and docs are not yet fully aligned.

## Recommendation

Do not publish the app publicly yet.

Instead, move into a staged hardening phase before TestFlight or any broader public release:

1. Align project metadata, README, and actual supported scope.
2. Add basic automated verification through test targets and CI.
3. Harden the async-heavy reader, download, cache, and persistence flows.
4. Decide the minimum public-release feature set and remove or relabel anything still partial.

Once those steps are complete, the project should be reassessed for TestFlight readiness first, then for broader public publishing.
