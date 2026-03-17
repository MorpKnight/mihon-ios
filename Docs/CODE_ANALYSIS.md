# Mihon iOS — Code Quality Analysis

> Generated: 2026-03-17

---

## Critical: Architecture

### 1. God Object — `AppModel` (~1,248 lines)

**File:** `App/AppModel.swift`

`AppModel` is responsible for library management, reading progress, history, tracking, backup, settings (~40 setter methods), source orchestration, caching, diagnostics, biometric unlock, import management, migration, and more. It conforms to **7 protocols** simultaneously.

Every feature change touches this one file. This violates the Single Responsibility Principle.

**Recommendation:** Decompose into focused services — `LibraryService`, `ReaderService`, `SettingsStore`, `SourceManager`, etc. — each injected via `@EnvironmentObject` or a dependency container.

### 2. No View Model Layer

All SwiftUI views access `AppModel` directly via `@EnvironmentObject`. There are no per-feature view models, creating tight coupling between every view and the god object.

**Recommendation:** Introduce per-feature view models (e.g., `LibraryViewModel`, `ReaderViewModel`) that mediate between the view and the services.

### 3. Dead Code — Unused `asura` Source

**File:** `Data/InternalSourceRepository.swift` (lines 51–62)

The `asura` variable (id: `"asura-en"`) is created but never added to `sourcesData`. Only `asuraScans` is used. This is dead code that should be removed.

---

## High: Memory & Persistence

### 4. Unbounded In-Memory Caches

**File:** `App/AppModel.swift` (lines 27–29)

```swift
@Published private(set) var sourceMangaCache: [String: [Manga]]
@Published private(set) var chapterCache: [String: [Chapter]]
@Published private(set) var pageCache: [String: [ReaderPage]]
```

These dictionaries grow without any eviction. No LRU, no size limit, no memory-pressure response.

**Recommendation:** Use `NSCache` or a custom LRU cache with a configurable size limit.

### 5. Full Snapshot Persisted on Every Mutation

**File:** `App/AppModel.swift` (lines 1096–1110)

`persist()` serializes the **entire** `DatabaseSnapshot` (including all caches) to JSON on disk after every single state change — including every page turn.

**Recommendation:** Throttle/debounce persistence (e.g., coalesce writes within a 1–2 second window). Exclude caches from the snapshot.

### 6. Dual Persistence System

**File:** `App/AppModel.swift` (lines 1108–1109)

```swift
databaseCoordinator.saveSnapshot(snapshot)
legacyStore.save(state)
```

Every persist writes to both `FileDatabaseCoordinator` (JSON file) **and** `AppStateStore` (UserDefaults). This doubles I/O and risks inconsistency. The `legacyStore` name suggests this was meant to be temporary.

**Recommendation:** Remove the legacy store and consolidate on a single persistence mechanism.

### 7. 17 `@Published` Properties on One Object

Since every view observes `AppModel`, any change to **any** `@Published` property triggers body re-evaluation in **all** views — `LibraryView`, `BrowseView`, `HistoryView`, etc. Changing `pageCache` during reading redraws the entire UI tree.

**Recommendation:** Split into multiple observable objects, or use `@Observable` (iOS 17+) which provides per-property observation.

---

## High: Concurrency Safety

### 8. Data Races in `NatsuIdSourceEngine`

**File:** `Data/Sources/NatsuIdSourceEngine.swift` (lines 15–16)

```swift
private var nonceCache: String?
private var genreCache: [GenreTag] = []
```

These are `var` properties on a plain `class`, mutated from `async` methods with no synchronization. This is a data race.

**Recommendation:** Convert `NatsuIdSourceEngine` to an `actor`, or protect mutable state with a lock.

### 9. Rate Limiter Suspension Bug

**File:** `Data/Sources/SourceEngineUtilities.swift` (lines 44–61)

In `SourceRateLimiter.waitTurn()`, after `Task.sleep` (a suspension point), another caller can enter and also sleep. Both wake at the same time, defeating rate limiting.

**Recommendation:** Set `lastFireTime` **before** sleeping and recheck after waking.

### 10. Sequential Repo Refresh

**File:** `App/AppModel.swift` (lines 784–791)

```swift
func refreshAllSourceRepos() async {
    for url in urls {
        await refreshSourceRepo(url)
    }
}
```

These are independent network calls that should use `TaskGroup` for concurrent execution.

---

## High: Error Handling & Crash Safety

### 11. Force-Unwraps That Can Crash

| Location | Code |
|---|---|
| `AsuraAPISourceEngine.swift:45,51,57` | `URL(string: ...)!` |
| `AppModel.swift:205` | `.first!` on possibly empty array |
| `BrowseView.swift:447` | `.first(where: ...)!` |
| `MangaDetailView.swift:116` | `model.sources[0]` when sources may be empty |

**Recommendation:** Replace with `guard let` / `if let` and handle the nil case gracefully (show error, use fallback, or return early).

### 12. Silently Swallowed Errors

| Location | Code |
|---|---|
| `AppStateStore.swift:43` | `try? encoder.encode(state)` |
| `FileDatabaseCoordinator.swift:117` | `try? data.write(...)` |

If the disk is full, user data is lost with no indication.

**Recommendation:** Log the error at minimum. Consider surfacing critical failures to the user.

---

## Medium: Performance

### 13. O(n) Lookups Called From View Bodies

These linear scans run on the main thread during rendering:

- `allManga` — iterates all sources and all manga, deduplicates, sorts (called repeatedly)
- `libraryItems()` calls `allManga.first(where:)` per library entry → **O(library × total_manga)**
- `source(for:)` — `sources.first { $0.id == id }` every time
- `progress(for:)` — linear scan of progress array
- `isInLibrary(_:)` — linear scan of library array

**Recommendation:** Use `Dictionary` lookups indexed by ID. Precompute derived collections and cache them.

### 14. Badge Causes Full Recomputation

**File:** `Features/RootTabView.swift` (line 52)

```swift
.badge(model.updateFeed.count)
```

This triggers `libraryItems()` → `allManga` on every render of the tab bar.

**Recommendation:** Cache the badge count and only recompute when the underlying data changes.

---

## Medium: Type Safety

### 15. Stringly-Typed IDs Everywhere

Source IDs, manga IDs, chapter IDs, and category IDs are all `String`. Nothing prevents mixing up a manga ID with a chapter ID at compile time.

**Recommendation:** Use typed wrappers:

```swift
struct MangaID: Hashable {
    let rawValue: String
}

struct ChapterID: Hashable {
    let rawValue: String
}
```

### 16. `SourceFilterSchema.kind` is a Raw String

**File:** `MihonDomain.swift` (line 116)

```swift
let kind: String  // "select", "multi-select", etc.
```

**Recommendation:** Replace with an enum.

### 17. JSON Parsing via `JSONSerialization`

**File:** `Data/SourceRepoImporter.swift` (lines 429–502)

`decodePackages()` uses `[String: Any]` casts instead of `Codable`.

**Recommendation:** Define `Codable` structs for the expected JSON shape.

---

## Medium: SwiftUI Anti-Patterns

### 18. `@State` Initialized From Parameters

**File:** `Features/Manga/MangaDetailView.swift` (lines 21–24)

```swift
_displayManga = State(initialValue: manga)
```

If SwiftUI reuses the view identity with a different `manga`, `@State` won't re-initialize — the view shows stale data.

**Recommendation:** Use `.onChange(of: manga)` to sync state, or restructure to avoid this pattern.

### 19. `AsyncImage` Without Caching

**File:** `Features/Shared/MangaCoverView.swift` (line 27)

Cover images use `AsyncImage` which has no persistent cache. Scrolling back and forth re-downloads images. (The reader correctly uses `ReaderImagePipeline`, but covers don't.)

**Recommendation:** Use `ReaderImagePipeline` (or a similar cache) for cover images too.

---

## Low-Medium: Code Smells

### 20. Korean Mapped to Japanese

**File:** `Data/SourceRepoImporter.swift` (line 534)

```swift
case "ja", "jp", "ko": return .japanese
```

Korean ("ko") is incorrectly mapped to `.japanese`.

### 21. `hashValue` Used for Color Generation

**File:** `Data/Sources/SourceEngineUtilities.swift` (line 132)

```swift
let value = abs(seed.hashValue) % palette.count
```

`hashValue` is randomized per app launch in Swift, so cover colors change on every restart.

**Recommendation:** Use a deterministic hash (e.g., a simple DJB2 or FNV hash on the UTF-8 bytes).

### 22. Incomplete HTML Entity Decoding

**File:** `Data/Sources/SourceEngineUtilities.swift` (lines 76–84)

Only 6 entities are handled. Numeric entities like `&#8217;` or `&#x2014;` produce garbled text in manga descriptions.

**Recommendation:** Add numeric entity decoding (`&#NNNN;` and `&#xHHHH;`).

### 23. Duplicated `biometricLockFeatureEnabled`

Defined separately in both `App/AppModel.swift` (line 17) and `App/AppChrome.swift` (line 11). If one changes, behavior diverges.

**Recommendation:** Define once in a shared constants file or configuration.

### 24. Duplicated URLSession Configuration

Three source engines (`AsuraAPISourceEngine`, `AsuraHTMLSourceEngine`, `NatsuIdSourceEngine`) have near-identical session setup code.

**Recommendation:** Extract to a factory method in `SourceEngineUtilities`.

### 25. `releaseNotesPresented` Defaults to `true`

**File:** `App/AppModel.swift` (line 37)

Every app launch shows the release notes sheet. There is no mechanism to track which version's notes the user has already dismissed.

**Recommendation:** Track the last-seen version and only present notes for new versions.

---

## Prioritized Action Plan

| Priority | Issue | Effort | Impact |
|---|---|---|---|
| 1 | Fix crash-causing force-unwraps (#11) | Low | Immediate stability |
| 2 | Fix data races in `NatsuIdSourceEngine` (#8) | Low | Undefined behavior prevention |
| 3 | Add Dictionary lookups for IDs (#13) | Low | Quick performance win |
| 4 | Remove dead `asura` source (#3) | Trivial | Code cleanliness |
| 5 | Fix Korean language mapping (#20) | Trivial | Correctness |
| 6 | Fix `hashValue` color instability (#21) | Low | UX consistency |
| 7 | Throttle/debounce `persist()` (#5) | Medium | Reduce I/O overhead |
| 8 | Remove dual persistence (#6) | Medium | Simplify data flow |
| 9 | Add numeric HTML entity decoding (#22) | Low | Text rendering quality |
| 10 | Begin decomposing `AppModel` (#1) | High | Most impactful long-term |
