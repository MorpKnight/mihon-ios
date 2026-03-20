# Mihon iOS (Unofficial Port)

[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![iOS](https://img.shields.io/badge/iOS-15.0+-blue.svg)](https://developer.apple.com/ios)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

**⚠️ Important: This is an unofficial, independent port.**

Mihon iOS is a personal challenge project: an attempt to port the popular Android manga reader Mihon (formerly Tachiyomi) to iOS using SwiftUI. This is **not** an official Mihon/Tachiyomi project, and I am **not affiliated** with the Mihon development team.

This is a learning exercise and independent implementation inspired by the original Android app.

## ✨ Features

- **📚 Extensive Source Support**: Access thousands of manga from various online sources through the extensions system
- **🎨 Customizable Reader**: Multiple reading modes (left-to-right, right-to-left, vertical scrolling) with extensive customization options
- **📱 Offline Reading**: Download and save manga chapters for offline enjoyment
- **🔍 Advanced Search**: Find manga across all your sources with powerful search capabilities
- **📊 Library Management**: Organize your manga collection with categories, tags, and reading status tracking
- **🔄 Automatic Updates**: Get notified when new chapters are available
- **🌙 Dark Mode**: Full support for dark and light modes
- **♿ Accessibility**: Built with accessibility in mind, supporting VoiceOver and dynamic type
- **🔐 Privacy-Focused**: All data stored locally on your device; no tracking or telemetry

## 🏗️ Architecture

Mihon iOS follows a **modular, feature-based architecture** with clean separation of concerns:

```
Mihon IOS/
├── App/              # App-level components and configuration
├── Core/             # Shared utilities, extensions, and common code
├── Data/             # Data layer (repositories, data sources, persistence)
├── Domain/           # Business logic, use cases, and domain models
├── Features/         # Feature modules (browse, library, reader, etc.)
│   ├── Browse/      # Manga discovery and search
│   ├── Library/     # Personal collection management
│   ├── Reader/      # Chapter reading interface
│   ├── Updates/     # Update checking and management
│   ├── Migration/   # Data migration and import
│   └── ...
└── Mihon_IOSApp.swift  # App entry point
```

### Modular Design Principles

- **Feature Isolation**: Each feature is self-contained with its own data, domain, and presentation layers
- **Dependency Injection**: Loose coupling through protocol-oriented design
- **SwiftUI + MVVM**: Modern declarative UI with clear separation of view and view model
- **Reactive Programming**: Uses Combine framework for asynchronous operations
- **Testability**: Architecture designed for unit and UI testing

## 🚀 Getting Started

### Prerequisites

- macOS 14.0+ (Sonoma or later)
- Xcode 15.0+ (or latest stable version)
- iOS 15.0+ deployment target
- Swift 5.9+

### Setup Instructions

1. **Clone the repository**
   ```bash
   git clone https://github.com/keiyoushi/mihon-ios.git
   cd mihon-ios
   ```

2. **Install dependencies**
   - The project uses Swift Package Manager (SPM) for dependency management
   - Open the project in Xcode and it will automatically resolve packages
   - Alternatively, run: `xcodebuild -resolvePackageDependencies`

3. **Open the project**
   ```bash
   open Mihon\ IOS.xcodeproj
   ```

4. **Configure signing**
   - Select the `Mihon IOS` scheme
   - Choose a development team in project settings
   - For physical device testing, ensure your device is registered

5. **Build and run**
   - Select a simulator or connected device
   - Press `Cmd+R` to build and run

## 🔧 Building from Command Line

```bash
# Build for simulator
xcodebuild -scheme "Mihon IOS" -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' build

# Build for device
xcodebuild -scheme "Mihon IOS" -destination 'generic/platform=iOS' build

# Run tests
xcodebuild -scheme "Mihon IOS" -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' test
```

## 🧪 Testing

The project includes unit and UI tests:

```bash
# Run all tests
xcodebuild test -scheme "Mihon IOS" -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest'

# Run specific test target
xcodebuild test -scheme "Mihon IOS" -only-testing:"MihonIOSTests" -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest'
```

## 📦 Extensions System

Mihon iOS supports a powerful extensions system that allows integration with numerous manga sources. The extensions are maintained in a separate community repository:

**[extensions-source](extensions-source/README.md)**

The extensions repository contains:
- Individual source implementations for different manga websites
- Build configuration for creating extension bundles
- Tools for extension development and testing

**Note**: The extensions repository is maintained by the broader community, not by the Mihon iOS project directly.

### Adding Extensions

1. Visit the [Keiyoushi Extensions Repository](https://github.com/keiyoushi/extensions-source)
2. Follow the setup instructions to build the extensions
3. Import the extension bundles into Mihon iOS via the app's extension manager

## 🤝 Contributing

Contributions are welcome! As a solo developer, I appreciate any help from the community. Whether you're fixing bugs, adding features, improving documentation, or developing new extensions, your contributions are valuable.

Please read the [Contributing Guide](CONTRIBUTING.md) for detailed information on:
- How to submit issues and feature requests
- Development workflow and coding standards
- Pull request process
- Extension development guidelines

## 📜 Code of Conduct

This project adheres to a strict [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to maintain a respectful and inclusive environment for everyone.

## 🔒 Security

We take security seriously. If you discover a security vulnerability, please review our [Security Policy](SECURITY.md) for responsible disclosure instructions.

## 📄 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

```
Copyright 2025 Mihon iOS Contributors

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

## 🙏 Acknowledgments

- **Mihon/Tachiyomi** - The original Android project that inspired this port
- **Keiyoushi Team** - For maintaining the extensions ecosystem
- **All Contributors** - Who have helped shape this project
- **Swift Community** - For the excellent tools and frameworks

## 📚 Documentation

Additional documentation is available in the [Docs](Docs/) directory:

- [Architecture Overview](Docs/architecture/modularization.md) - Detailed modularization design

## 📞 Support

- **GitHub Issues**: For bug reports and feature requests
- **Discord**: [Join the community](https://discord.gg/3FbCpdKbdY) for real-time help and discussion (note: this is a general Keiyoushi Discord, not specific to Mihon iOS)
- **Documentation**: Check the [Wiki](https://github.com/keiyoushi/mihon-ios/wiki) for guides and FAQs (if available)

---

**⚠️ Important**: This is an **unofficial, independent port**. I am **not affiliated** with the Mihon/Tachiyomi development teams. This is a personal challenge project to learn iOS development and create a manga reader for iOS devices.

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
- Source family classification tooling lives in `Tools/classify_extensions.py`.
- Coverage snapshots live in `Docs/source-engine-coverage.json` and `Docs/source-engine-coverage.generated.json`.

## License

This project is licensed under the Apache License 2.0. See [LICENSE](./LICENSE).
