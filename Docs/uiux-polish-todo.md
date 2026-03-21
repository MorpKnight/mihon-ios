# UI/UX Polish To-Do (iOS-Native Alignment)

Generated: 2026-03-20

Purpose

- Capture UI/UX improvements needed to better align Mihon iOS with modern iOS design conventions.
- Keep this as an implementation roadmap for future polish-focused iterations.

## P0 - Fix UX inconsistencies / broken expectations

- [x] Implement real action for Library "Quick Read" context menu item (currently behaves like placeholder/haptic-only flow).
  - Files: `Mihon IOS/Features/Library/LibraryView.swift`
  - Goal: action should actually open reader at the correct chapter.

- [x] Audit and reduce non-essential haptics on routine interactions.
  - Files: `Mihon IOS/Features/RootTabView.swift`, `Mihon IOS/Features/Library/LibraryView.swift`, `Mihon IOS/Features/Browse/BrowseView.swift`, `Mihon IOS/Features/History/HistoryView.swift`
  - Goal: keep haptics for meaningful confirmations only.

## P1 - Improve iOS-native interaction patterns

- [x] Refine biometric lock UX for clearer system-like flow.
  - Files: `Mihon IOS/App/AppChrome.swift`, `Mihon IOS/App/AppModel+Security.swift`
  - Goals:
    - Keep retry obvious and primary.
    - Ensure message hierarchy is clear (no persistent noisy error text after recovery).
    - Validate lock/unlock transitions on app background/foreground.

- [ ] Stabilize Reader resume + page index sync (known regressions still reproducible).
  - Files: `Mihon IOS/Features/Reader/ReaderView.swift`, `Mihon IOS/App/AppModel+ReaderProgress.swift`, `Mihon IOS/Features/Library/LibraryView.swift`, `Mihon IOS/Features/Manga/MangaDetailView.swift`
  - Remaining issues to fix:
    - App relaunch sometimes opens resumed chapter at page 1 instead of last saved page.
    - Vertical/Webtoon bottom page indicator can drift from actual visible page.
    - Continue Reading + Library subtitle consistency should remain correct after cold launch and delayed chapter hydration.
  - Acceptance checks:
    - Relaunch app: same manga/chapter opens on exact saved page.
    - Page indicator and slider always match visible page in Pager/LTR/RTL/Vertical/Webtoon.
    - Library and Manga Detail always show accurate last-read chapter/page metadata.

- [ ] Improve chapter navigation ergonomics in paged mode.
  - Files: `Mihon IOS/Features/Reader/ReaderView.swift`
  - Goal:
    - Keep chapter-boundary swipe gesture reliable and direction-correct in LTR/RTL pager modes.

- [ ] Improve Downloads screen structure and state feedback.
  - Files: `Mihon IOS/Features/Downloads/DownloadsView.swift`, `Mihon IOS/Features/Downloads/DownloadQueueView.swift`
  - Goals:
    - Better empty/loading/error states per segment.
    - Clarify active queue vs completed items.
    - Ensure segmented control placement feels consistent with iOS navigation bars.

- [ ] Tune Settings information architecture to reduce density.
  - Files: `Mihon IOS/Features/More/SettingsViews.swift`, `Mihon IOS/Features/More/MoreView.swift`
  - Goals:
    - Reduce visual overload in long forms.
    - Group advanced options more progressively.
    - Keep destructive actions clearly separated.

## P2 - Accessibility and content clarity

- [ ] Run an accessibility pass on custom UI components and critical flows.
  - Files: `Mihon IOS/Features/**/*` (focus: Reader, Library, Downloads, Browse, Settings)
  - Goals:
    - Add missing `accessibilityLabel`/`accessibilityHint` where needed.
    - Verify dynamic type behavior.
    - Verify VoiceOver order and actionable element clarity.

- [ ] Improve copywriting consistency and microcopy quality.
  - Files: `Mihon IOS/App/AppChrome.swift`, `Mihon IOS/Features/**/*.swift`
  - Goals:
    - Use concise iOS-style phrasing.
    - Standardize labels/titles for similar actions.
    - Reduce Android-centric wording where possible.

## P3 - Nice-to-have visual polish

- [ ] Review spacing, typography, and icon consistency across tabs.
  - Files: `Mihon IOS/Features/**/*`
  - Goal: achieve consistent rhythm and hierarchy between list-heavy screens.

- [ ] Evaluate contextual surfaces (sheet detents, dialogs, menus) for consistency.
  - Files: `Mihon IOS/App/AppChrome.swift`, `Mihon IOS/Features/**/*`
  - Goal: unify modal/dialog behavior with iOS expectations.

## Suggested implementation order

1. Fix broken UX expectations (Quick Read + haptics audit).
2. Polish lock and downloads interaction quality.
3. Refactor settings IA and destructive-action ergonomics.
4. Complete accessibility pass.
5. Apply visual consistency polish.

## Notes

- Scope for this plan is UX polish only; no major product feature additions.
- Re-validate each phase on iPhone compact and iPad regular layouts before closing tasks.
