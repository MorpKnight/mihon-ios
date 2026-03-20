# Contributing to Mihon iOS

Thank you for your interest in contributing to Mihon iOS! This is a **solo developer project** (just me!), and I appreciate any help from the community. This document provides guidelines and information for contributors.

## 📋 Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How to Contribute](#how-to-contribute)
- [Development Setup](#development-setup)
- [Coding Standards](#coding-standards)
- [Pull Request Process](#pull-request-process)
- [Extension Development](#extension-development)
- [Reporting Issues](#reporting-issues)
- [Community](#community)

## 📖 Code of Conduct

By participating in this project, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md). Please read it before contributing.

## 🤝 How to Contribute

There are many ways to contribute to this **unofficial port**:

### 🐛 Reporting Bugs

- Check existing issues before creating a new one
- Use the bug report template
- Include detailed steps to reproduce
- Add relevant logs or screenshots
- Specify your iOS version and device model

### 💡 Suggesting Features

- Search existing feature requests first
- Use the feature request template
- Describe the problem your feature solves
- Consider if it aligns with the project's goals
- Provide examples from other apps if applicable

### 🔧 Contributing Code

- Fix bugs assigned to you or unassigned
- Implement approved feature requests
- Improve code quality and performance
- Add tests for new functionality
- Update documentation

### 📚 Improving Documentation

- Fix typos and clarify confusing sections
- Add missing documentation
- Improve code comments
- Create tutorials or guides

### 🌐 Developing Extensions

- Create new source extensions
- Fix broken existing sources
- Improve extension performance
- See [Extension Development](#extension-development) below

## 💻 Development Setup

### Prerequisites

- macOS 14.0+ (Sonoma or later)
- Xcode 15.0+ (or latest stable)
- iOS 15.0+ deployment target
- Swift 5.9+
- Command Line Tools: `xcode-select --install`

### Initial Setup

1. **Fork and clone the repository**
   ```bash
   git clone https://github.com/YOUR_USERNAME/mihon-ios.git
   cd mihon-ios
   ```

2. **Add upstream remote**
   ```bash
   git remote add upstream https://github.com/keiyoushi/mihon-ios.git
   ```

3. **Install Swift dependencies**
   - Open `Mihon IOS.xcodeproj` in Xcode
   - Xcode will automatically resolve Swift Package Manager dependencies
   - Or run: `xcodebuild -resolvePackageDependencies`

4. **Create a branch**
   ```bash
   git checkout -b feature/your-feature-name
   # or for bug fixes
   git checkout -b fix/issue-description
   ```

5. **Build the project**
   - Open in Xcode and build (`Cmd+B`)
   - Ensure no build errors
   - Run on simulator/device to test

### Extensions Setup (Optional)

If you're working on extensions:

1. Clone the extensions repository:
   ```bash
   git clone https://github.com/keiyoushi/extensions-source.git
   ```

2. Build extensions following their README
3. Import built extensions into Mihon iOS for testing

## 📐 Coding Standards

### Swift Style Guide

We follow the [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/) and these additional rules:

#### Formatting

- Use **2 spaces** for indentation (no tabs)
- Maximum line length: **100 characters**
- Use trailing closures when appropriate
- Prefer `let` over `var` (immutability)
- Use type inference when the type is obvious

#### Naming Conventions

- **camelCase** for variables, functions, properties
- **PascalCase** for types, protocols, classes, structs, enums
- Prefix private properties with `_` only when necessary for @State
- Use descriptive names; avoid abbreviations

#### Example:
```swift
// Good
let mangaTitle = "One Piece"
var currentChapter: Chapter?
func loadMangaDetails() async throws -> MangaDetails

// Avoid
let title = "One Piece"
var chap: Chapter?
func loadDetails() async throws -> Details
```

#### Access Control

- Use the most restrictive access level possible
- Prefer `private` over `fileprivate`
- Use `internal` (default) for module-level
- Use `public` only when needed for cross-module access
- Use `open` sparingly (for subclassing/overriding)

#### Error Handling

- Use `throws` for recoverable errors
- Use `Result` type for async operations when appropriate
- Provide descriptive error messages
- Create custom error types for domain-specific errors

#### Async/Await

- Prefer `async/await` over Combine for simple async operations
- Use `@MainActor` for UI updates
- Use `Task` for fire-and-forget operations
- Cancel tasks appropriately to avoid leaks

#### SwiftUI Best Practices

- Keep view bodies simple; extract complex logic to view models
- Use `@State`, `@StateObject`, `@ObservedObject`, `@EnvironmentObject` appropriately
- Prefer `NavigationStack` over `NavigationView`
- Use `List` with `ForEach` for dynamic content
- Extract reusable views into separate components

#### Documentation

- Document public APIs with SwiftDoc comments
- Explain "why" not "what" in comments
- Keep comments up-to-date with code changes
- Use markdown in documentation comments

Example:
```swift
/// Loads manga details from the network or cache.
///
/// This method first checks the local cache for existing data. If not found
/// or if the cache is stale, it fetches fresh data from the network.
///
/// - Parameter mangaId: The unique identifier of the manga
/// - Returns: A manga details object with comprehensive information
/// - Throws: `NetworkError` if network request fails, `PersistenceError` if cache operations fail
func loadMangaDetails(mangaId: String) async throws -> MangaDetails
```

### Architecture Guidelines

- Follow the **feature-based modularization** structure
- Each feature should have its own `Data`, `Domain`, and UI layers
- Use protocols for dependency injection
- Keep view models focused on presentation logic
- Place business logic in use cases (interactors)
- Repositories should abstract data sources

### Git Workflow

1. **Keep branches focused**: One feature/fix per branch
2. **Rebase onto main**: Keep your branch up-to-date
   ```bash
   git fetch upstream
   git rebase upstream/main
   ```
3. **Write clear commit messages**:
   ```
   feat(reader): add vertical scrolling mode
   fix(library): prevent crash when manga has no cover
   chore(deps): update SwiftUIX to 1.0.0
   ```
   - Use imperative mood ("add", "fix", "update")
   - First line ≤ 50 characters
   - Optional detailed explanation after blank line

4. **Squash commits** before merging if needed:
   ```bash
   git rebase -i HEAD~3  # Interactive rebase to squash
   ```

## 🔀 Pull Request Process

### Before Submitting

- [ ] Ensure all tests pass
- [ ] Add tests for new functionality
- [ ] Update documentation if needed
- [ ] Verify no merge conflicts with `main`
- [ ] Squash related commits
- [ ] Ensure code follows style guidelines

### PR Template

When creating a pull request, please include:

```markdown
## Description
Brief description of changes

## Related Issues
Closes #123
Related to #456

## Type of Change
- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update

## Testing
Describe how you tested these changes

## Screenshots (if applicable)
Add screenshots for UI changes

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Tests added/updated
- [ ] Documentation updated
- [ ] No merge conflicts with main
```

### Review Process

1. **Automated Checks**: CI will run tests and linting
2. **Code Review**: Maintainers will review your code
3. **Address Feedback**: Make requested changes
4. **Approval**: At least one maintainer approval required
5. **Squash and Merge**: PR will be squashed and merged

### After Merging

- Delete your feature branch
- Pull latest changes to your local `main`
- Your changes will be included in the next release

## 🔌 Extension Development

### Creating New Sources

Extensions are maintained in the [extensions-source](extensions-source/) repository. To create a new source:

1. Follow the [extensions-source README](extensions-source/README.md)
2. Use the source template in `extensions-source/lib-multisrc/`
3. Implement required methods: `chapterList`, `pageList`, `search`, etc.
4. Test thoroughly with various manga URLs
5. Submit PR to extensions-source repository

### Source Guidelines

- Respect website terms of service
- Implement proper error handling
- Add appropriate user-agent headers
- Handle rate limiting gracefully
- Support both English and other languages when applicable
- Test with multiple manga titles

### Testing Extensions

- Use the extension debug mode in Mihon iOS
- Test chapter list parsing
- Test page URL generation
- Test search functionality
- Verify image loading

## 🐛 Reporting Issues

### Bug Reports

Use the bug report template and include:

1. **Environment**
   - iOS version
   - Device model
   - Mihon iOS version (build number)

2. **Steps to Reproduce**
   - Detailed, numbered steps
   - Expected vs actual behavior

3. **Additional Context**
   - Screenshots or screen recordings
   - Console logs (from Xcode)
   - Crash logs if applicable

### Feature Requests

1. Describe the problem you're solving
2. Explain the proposed solution
3. Consider alternatives
4. Provide examples from other apps if relevant

## 👥 Community

- **Discord**: [Join our server](https://discord.gg/3FbCpdKbdY) for real-time discussion
- **GitHub Discussions**: Use for questions and ideas
- **Issues**: For bugs and feature requests only

## 📚 Additional Resources

- [Architecture Documentation](Docs/architecture/modularization.md)
- [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
- [Xcode Help](https://help.apple.com/xcode/)

## ❓ Questions?

Feel free to ask in Discord or create a GitHub Discussion. We're happy to help new contributors!

---

**Thank you for contributing to Mihon iOS!** 🎉

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
