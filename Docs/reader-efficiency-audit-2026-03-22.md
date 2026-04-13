# Reader Efficiency and Risk Audit (2026-03-22)

## Scope
- Reader pipeline: page rendering, image fetch/decode/cache, zoom/tile flow, chapter transitions.
- Supporting app layers: persistence, download pipeline, cache policy, UI state update behavior.
- Method: static code review of current implementation in iOS workspace.

## Severity-ranked findings

### Critical
1. Tile cache key cardinality is too high
- File: Mihon IOS/Data/AppCacheController.swift
- Why: tile cache keys include fine-grained crop rect and exact pixel size, which creates many near-duplicate entries during pan/zoom.
- Risk: cache churn, lower hit rate, repeated decode cost, memory pressure spikes.

2. Prefetch cleanup uses nested unstructured task
- File: Mihon IOS/Features/Reader/ReaderImagePipeline.swift
- Why: deferred cleanup uses nested task in a cancellation-sensitive path.
- Risk: inconsistent prefetch bookkeeping under rapid chapter/page switching.

3. Main-thread synchronous snapshot writes
- File: Mihon IOS/Data/FileDatabaseCoordinator.swift
- Why: snapshot encoding + atomic disk write are synchronous and called from state persistence flow.
- Risk: UI hitching during frequent progress/state saves.

### High
4. Color transform work is not reused aggressively
- File: Mihon IOS/Features/Reader/ReaderImagePipeline.swift
- Why: filter application can repeat across tile/preview paths without a dedicated transformed-image cache tier.
- Risk: avoidable CPU/GPU cost during filtered reading.

5. Download flow has no backoff retry policy
- File: Mihon IOS/App/DownloadsService.swift
- Why: transient network failures immediately fail page/chapter operations.
- Risk: poor resilience on unstable networks and repeated manual retries.

6. Reader error/load state transitions can carry stale user perception
- File: Mihon IOS/Features/Reader/ReaderView.swift
- Why: complex async chapter transitions, retries, and snapshot deferrals increase chance of stale UI state perception.
- Risk: edge-case mismatch between true and displayed loading/failure state.

7. URLSession.shared used across multiple high-volume paths
- Files: ReaderImagePipeline.swift, DownloadsService.swift, MangaCoverView.swift
- Why: no app-specific per-host/session tuning.
- Risk: avoidable queuing contention under parallel loads.

### Medium
8. Cache limits are static and not device-adaptive
- Files: Mihon IOS/Data/LRUMemoryCache.swift, Mihon IOS/App/AppModel+Preferences.swift
- Why: fixed limits may under-utilize capable devices and over-stress lower-memory ones.
- Risk: either unnecessary eviction or memory pressure depending on device.

9. Decode fallback strategy is limited
- File: Mihon IOS/Data/AppCacheController.swift
- Why: limited degradation strategy when decode/downsample fails.
- Risk: user-visible missing pages in edge-case corrupted payloads.

10. Reader singleton dependency pattern reduces testability
- Files: ReaderView.swift, ReaderImagePipeline.swift
- Why: direct singleton usage in view paths.
- Risk: harder isolation testing and future multi-instance reader complexity.

## Prioritized roadmap

### Quick wins (low risk, high impact)
1. Quantize tile key dimensions/crops for cache bucketing
- Expected impact: improved tile cache hit rate, less churn.

2. Move snapshot save off main actor path
- Expected impact: fewer UI stutters during frequent persists.

3. Add bounded exponential retry in DownloadsService
- Expected impact: better reliability on unstable networks.

4. Replace nested cleanup task in prefetch with structured cleanup path
- Expected impact: safer cancellation semantics.

### Medium-term improvements
1. Add transformed-image cache tier keyed by base image + filter signature
- Expected impact: reduced repeated filter cost.

2. Introduce dedicated URLSession configurations for reader/download workloads
- Expected impact: better throughput and less contention.

3. Harden reader transition/load state machine with explicit event-state matrix
- Expected impact: fewer edge-case visual inconsistencies.

### Longer-term architecture
1. Dependency inject image pipeline/cache into reader features
- Expected impact: testability and modularity improvements.

2. Device-class adaptive cache profiles
- Expected impact: better memory/performance balance across devices.

## Validation suggestions
- Collect tile cache hit/miss counters before and after key quantization.
- Measure chapter transition frame pacing while persisting progress.
- Track retry success rate for page/chapter downloads under simulated packet loss.
- Run memory profile after 10+ chapter transitions with zoom-heavy usage.

## Notes
- This document is analysis-only and intentionally avoids behavior changes.
- Reader UX fixes requested for this session were implemented separately in code changes.

## Implementation status

### 2026-03-22 update

1. Medium item #8: Cache limits are static and not device-adaptive
- Status: Completed
- Files: Mihon IOS/Domain/Preferences/PreferencesDomain.swift, Mihon IOS/Domain/Persistence/PersistedState.swift, Mihon IOS/Data/LRUMemoryCache.swift
- Change summary: Added device-memory-class adaptive defaults for advanced cache preferences and cache configuration defaults.
- Validation: No diagnostics errors on edited files.
- Residual risk: Existing users with manually persisted cache limits keep their explicit values.

2. Medium item #9: Decode fallback strategy is limited
- Status: Completed
- Files: Mihon IOS/Data/AppCacheController.swift
- Change summary: Added multi-pass decode fallback paths for thumbnail, preview, full-quality, and cropped tile decode flows before hard failure.
- Validation: No diagnostics errors on edited files.
- Residual risk: Fallback decode may return lower fidelity for corrupted payloads, but improves recoverability.

3. Medium item #10: Reader singleton dependency pattern reduces testability
- Status: Partial
- Files: Mihon IOS/Features/Reader/ReaderImagePipeline.swift, Mihon IOS/Features/Reader/ReaderTiledPageView.swift, Mihon IOS/Features/Reader/ReaderPageSurface.swift, Mihon IOS/Features/Reader/ReaderView.swift
- Change summary: Introduced ReaderImagePipelining protocol and injected pipeline entrypoints through ReaderView and tiled/page surfaces, replacing direct singleton calls in those paths.
- Validation: No diagnostics errors on edited files.
- Residual risk: Remaining code paths still reference shared singleton outside this injection boundary.
