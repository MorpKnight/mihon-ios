# Architecture To-Do and Prioritized Next Steps

Generated: 2026-03-20

Executive summary

- This document captures prioritized architecture gaps, incomplete/broken features, and must-have additions for the Mihon iOS project so future development is focused and trackable.

Key missing / high-priority items

1. Add unit and UI tests (Blocker)
   - Create Xcode test targets and a /Tests/ directory.
   - Start with tests for: AppModel, ReaderViewModel, DownloadManager, and critical Domain use-cases.
   - Rationale: regression safety and release confidence.
   - Estimated effort: large

2. Add CI (GitHub Actions) (Medium)
   - Add .github/workflows/ci.yml to run build and tests on PRs and pushes.
   - Rationale: automate verification and enforce build stability.
   - Estimated effort: medium

3. Clarify and document incomplete features (Small)
   - Mark UI flows or Settings with "Work in Progress" where features are incomplete (backup/restore, tracker auth, partial imports).
   - Update README and Docs/publish-readiness-todo.md accordingly.
   - Estimated effort: small

4. Align project settings and documentation (Small)
   - Sync iOS deployment target and Xcode version with README.
   - Ensure Info.plist entries are correct and documented.
   - Estimated effort: small

5. Integrate crash reporting & analytics (Medium)
   - Add Sentry or Firebase Crashlytics and an analytics provider (Mixpanel, Amplitude, or Firebase Analytics).
   - Add hooks in AppModel and error handlers to report crashes and key events.
   - Rationale: observability in production.
   - Estimated effort: medium

6. Strengthen background & download reliability (Medium)
   - Add BackgroundTaskManager and ensure downloads use URLSession background tasks with resume support and retry/backoff.
   - Rationale: core UX for offline reading and downloads.
   - Estimated effort: medium

7. Add dependency injection improvement (Small to Medium)
   - Introduce a lightweight DI container or initializer-based DI for repositories and services to improve testability.
   - Replace some ad-hoc environment-object wiring where appropriate.
   - Estimated effort: small to medium

8. Accessibility & Localization checks (Medium)
   - Audit UI for VoiceOver, Dynamic Type, color contrast; add Localizable.strings for app strings.
   - Rationale: App Store compliance and inclusive UX.
   - Estimated effort: medium

9. Privacy consent & onboarding (Medium)
   - Add onboarding flow describing privacy, telemetry options, and permissions (notifications, background fetch if used).
   - Estimated effort: medium

10. Deep links, push notifications, and backup/restore (Medium)
   - Add universal links, URL handling, and push notification scaffolding if needed for user engagement and syncing.
   - Define backup/restore strategy (iCloud, local export/import) and implement minimal MVP.
   - Estimated effort: medium

Notes and next actions

- Owners: assign each item an owner and target milestone.
- Tests-first: start writing unit tests for the AppModel and download flows before major refactors.
- CI: add GitHub Actions that run lint, build, and tests on every PR.
- Docs: keep this file updated as items are completed.

References

- See Docs/publish-readiness-review.md and Docs/publish-readiness-todo.md for existing release checklists and notes.

