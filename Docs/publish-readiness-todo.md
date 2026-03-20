# Publish Readiness To-Do

## Blockers

- [ ] Fix the Xcode project and README deployment-target mismatch so the documented minimum iOS version matches the actual build settings.
- [ ] Add a real unit-test target to the Xcode project so core logic can be validated automatically.
- [ ] Add smoke-level UI or integration coverage for launch, browse, reader, and downloads so the highest-risk user flows have baseline regression protection.
- [ ] Add a GitHub Actions build/test workflow so pull requests and main-branch changes are verified automatically.
- [ ] Clean and de-duplicate the README so setup steps, project status, testing claims, and supported features reflect current repo truth.

## Reliability

- [ ] Audit async task lifecycle, cancellation, and memory behavior so reader/download/background operations do not leak work or leave stale state behind.
- [ ] Standardize network access and caching strategy so image loading, source fetches, and downloads follow consistent reliability rules.
- [ ] Review download and reader failure handling so retries, cancellations, offline behavior, and partial-download cleanup are predictable.
- [ ] Validate persistence and migration resilience so snapshot loading, schema migration, and downloaded-chapter state survive upgrades and corruption scenarios safely.

## Product Completeness

- [ ] Define the minimum public-release scope for sources, backup restore, tracking, and downloads so the shipped app has a clear and supportable feature contract.
- [ ] Remove, relabel, or clearly mark features that are still partial so users are not promised behavior that is not fully ready yet.

## Store Readiness

- [ ] Review app metadata, versioning, icons, screenshots, and privacy-facing copy so App Store presentation is internally consistent and accurate.
- [ ] Review App Store-sensitive flows and disclosures so source access, downloads, account/tracker features, and privacy/security messaging are safe to submit publicly.

## Nice to Have

- [ ] Continue modularization follow-up so `AppModel` and other cross-cutting orchestration points are easier to maintain and test.
- [ ] Run performance profiling on reader, download, image-cache, and large-library scenarios so memory and responsiveness issues are found before release.
- [ ] Perform an accessibility and device-matrix pass so VoiceOver, dynamic type, orientation behavior, and common iPhone/iPad layouts are checked before launch.
