# Contributing

Thanks for contributing to Mihon iOS.

## Ground Rules

- Keep changes focused. Avoid mixing refactors and behavior changes without a clear reason.
- Preserve Mihon Android behavior where possible, but prefer native iOS UX when platform expectations differ.
- Do not commit local build artifacts, personal signing changes, or nested reference repositories.

## Before You Start

- Check existing issues and pull requests first.
- For large changes, open an issue or discussion before implementation.
- If you are adding a source runtime, document the target site family and parser assumptions.

## Development Workflow

1. Create a branch for your change.
2. Make the smallest coherent change you can.
3. Run a local build or at minimum a Swift parse/type check.
4. Include screenshots for UI-affecting changes.
5. Explain user-visible behavior changes in the pull request.

## Pull Request Expectations

- describe what changed
- explain why the change is needed
- call out tradeoffs or known follow-up work
- mention testing performed

## Architecture Guidance

- `App/` owns app boot and high-level orchestration
- `Data/` owns persistence, import, and source runtime integration
- `Features/` owns screen-level UI
- prefer extending existing runtime engines over duplicating source logic

## Reader Changes

Reader changes are easy to regress. If you touch the reader, verify at least:

- paged modes
- vertical and webtoon scroll behavior
- chapter boundary transitions
- image failure and retry handling

## Source Runtime Changes

If you add or update a source:

- keep parser logic isolated to the runtime layer
- avoid leaking source-specific assumptions into generic UI
- document filters, host assumptions, and fallback parsing behavior

## Code Style

- Swift style should remain straightforward and readable
- prefer small helper functions over deeply nested view bodies
- add comments only when they explain non-obvious behavior
