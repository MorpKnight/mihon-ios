# Mihon iOS Modular Architecture

This document describes the modular architecture of Mihon iOS, explaining the design decisions, layer separation, and best practices that make the codebase maintainable, testable, and scalable.

## 📐 Table of Contents

- [Overview](#overview)
- [Architectural Principles](#architectural-principles)
- [Module Structure](#module-structure)
- [Layer Architecture](#layer-architecture)
- [Dependency Management](#dependency-management)
- [Data Flow](#data-flow)
- [Design Patterns](#design-patterns)
- [Testing Strategy](#testing-strategy)
- [Migration Path](#migration-path)

## 🎯 Overview

Mihon iOS uses a **feature-based modular architecture** inspired by Clean Architecture and MVVM patterns. The application is divided into independent feature modules, each with clear boundaries and responsibilities.

### Why Modularization?

- **Maintainability**: Smaller, focused modules are easier to understand and modify
- **Testability**: Isolated components can be tested independently
- **Scalability**: New features can be added without affecting existing code
- **Team Productivity**: Multiple developers can work on different features simultaneously
- **Code Reusability**: Common functionality can be shared across features

## 🏛️ Architectural Principles

### 1. Separation of Concerns

Each module is organized into three distinct layers:

```
Feature/
├── Data/           # Data sources, repositories, persistence
├── Domain/         # Business logic, use cases, entities
└── UI/             # SwiftUI views and view models
```

### 2. Dependency Rule

Dependencies flow **inward**:

```
UI → Domain → Data
```

- **UI layer** depends on **Domain** (use cases, models)
- **Domain layer** depends on **Data** (repository protocols)
- **Data layer** has no dependencies on outer layers

This ensures that business logic is independent of UI and data implementation details.

### 3. Protocol-Oriented Design

We use protocols (interfaces) to define contracts between layers:

```swift
// Domain layer defines repository protocol
protocol MangaRepository {
    func getManga(id: String) async throws -> Manga
    func searchManga(query: String) async throws -> [Manga]
}

// Data layer implements the protocol
class MangaRepositoryImpl: MangaRepository {
    // Implementation with network and database
}

// UI layer depends on the protocol, not implementation
class MangaViewModel {
    private let repository: MangaRepository
    init(repository: MangaRepository) { ... }
}
```

### 4. Single Responsibility

Each class, struct, or function has one reason to change:

- **Use Cases**: One specific business operation
- **Repositories**: One data source abstraction
- **View Models**: One view's presentation logic
- **Views**: One UI component

## 📦 Module Structure

### Root Structure

```
Mihon IOS/
├── App/                    # App configuration and entry points
├── Core/                   # Shared utilities and extensions
├── Data/                   # Global data components (shared repositories)
├── Domain/                 # Global domain models and services
├── Features/               # Feature modules
│   ├── Browse/            # Manga discovery and search
│   ├── Library/           # Personal collection management
│   ├── Reader/            # Chapter reading interface
│   ├── Updates/           # Update checking and notifications
│   ├── Migration/         # Data migration and import/export
│   ├── More/              # Settings and additional features
│   └── Shared/            # Feature-specific shared code
└── Mihon_IOSApp.swift     # App entry point
```

### Feature Module Structure

Each feature follows the same pattern:

```
FeatureName/
├── Data/
│   ├── Models/            # Feature-specific data models (DTOs)
│   ├── Sources/           # Data sources (network, database, etc.)
│   ├── Repositories/      # Repository implementations
│   └── Mappers/           # Data transformation (DTO → Domain)
├── Domain/
│   ├── Models/            # Domain entities and value objects
│   ├── UseCases/          # Business logic operations
│   └── Repositories/      # Repository protocols
└── UI/
    ├── Views/             # SwiftUI views
    ├── ViewModels/        # View models (ObservableObject)
    ├── Components/        # Reusable UI components
    └── Navigation/        # Navigation logic and routing
```

## 🏗️ Layer Architecture

### 1. UI Layer

**Purpose**: Presentation logic and user interaction

**Components**:
- **Views**: SwiftUI views, stateless and reusable
- **ViewModels**: `ObservableObject` with `@Published` properties
- **Components**: Reusable UI elements (buttons, lists, etc.)
- **Navigation**: Route definitions and navigation helpers

**Responsibilities**:
- Display data from view model
- Handle user interactions
- Forward events to view model
- No business logic

**Example**:
```swift
struct MangaListView: View {
    @StateObject private var viewModel: MangaListViewModel

    var body: some View {
        List(viewModel.mangas) { manga in
            MangaRow(manga: manga)
                .onTapGesture {
                    viewModel.selectManga(manga)
                }
        }
        .task {
            await viewModel.loadMangas()
        }
    }
}

final class MangaListViewModel: ObservableObject {
    @Published var mangas: [Manga] = []
    @Published var isLoading = false

    private let getMangasUseCase: GetMangasUseCase

    func loadMangas() async {
        isLoading = true
        do {
            mangas = try await getMangasUseCase.execute()
        } catch {
            // Handle error
        }
        isLoading = false
    }
}
```

### 2. Domain Layer

**Purpose**: Business logic and application rules

**Components**:
- **Entities**: Core business objects with identity
- **Value Objects**: Immutable objects without identity
- **Use Cases** (Interactors): Specific operations or workflows
- **Repository Protocols**: Abstract data access contracts

**Responsibilities**:
- Encapsulate business rules
- Define data contracts
- Coordinate data flow between UI and Data layers
- Pure Swift (no iOS/SwiftUI dependencies)

**Example**:
```swift
// Entity
struct Manga: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let author: String?
    let description: String?
    let coverImage: URL?
    let status: MangaStatus
}

// Use Case
protocol GetMangaDetailsUseCase {
    func execute(mangaId: String) async throws -> MangaDetails
}

final class GetMangaDetailsUseCaseImpl: GetMangaDetailsUseCase {
    private let mangaRepository: MangaRepository
    private let chapterRepository: ChapterRepository

    func execute(mangaId: String) async throws -> MangaDetails {
        let manga = try await mangaRepository.getManga(id: mangaId)
        let chapters = try await chapterRepository.getChapters(mangaId: mangaId)
        return MangaDetails(manga: manga, chapters: chapters)
    }
}

// Repository Protocol
protocol MangaRepository {
    func getManga(id: String) async throws -> Manga
    func searchManga(query: String, sources: [Source]) async throws -> [Manga]
    func getFavoriteMangas() async throws -> [Manga]
    func addFavorite(manga: Manga) async throws
    func removeFavorite(mangaId: String) async throws
}
```

### 3. Data Layer

**Purpose**: Data access and external communication

**Components**:
- **Data Sources**: Network clients, database access, file system
- **Repository Implementations**: Concrete implementations of repository protocols
- **Mappers/Transformers**: Convert between Data DTOs and Domain models
- **Persistence**: Local storage (Core Data, Realm, SQLite, UserDefaults)

**Responsibilities**:
- Fetch data from external sources (APIs, databases)
- Cache and persistence management
- Data transformation and validation
- Error handling for network/database failures

**Example**:
```swift
// Data Source
protocol MangaNetworkDataSource {
    func fetchMangaDetails(id: String) async throws -> MangaDTO
    func searchManga(query: String) async throws -> [MangaDTO]
}

final class MangaNetworkDataSourceImpl: MangaNetworkDataSource {
    private let urlSession: URLSession
    private let baseURL: URL

    func fetchMangaDetails(id: String) async throws -> MangaDTO {
        let url = baseURL.appendingPathComponent("manga/\(id)")
        let (data, response) = try await urlSession.data(from: url)
        // Validate response, decode JSON
        return try JSONDecoder().decode(MangaDTO.self, from: data)
    }
}

// Repository Implementation
final class MangaRepositoryImpl: MangaRepository {
    private let networkDataSource: MangaNetworkDataSource
    private let localDataSource: MangaLocalDataSource
    private let mapper: MangaMapper

    func getManga(id: String) async throws -> Manga {
        // Try cache first
        if let cached = try await localDataSource.getCachedManga(id: id) {
            return mapper.mapToDomain(cached)
        }

        // Fetch from network
        let dto = try await networkDataSource.fetchMangaDetails(id: id)
        try await localDataSource.cacheManga(dto)
        return mapper.mapToDomain(dto)
    }
}
```

## 🔗 Dependency Management

### Swift Package Manager (SPM)

We use SPM for dependency management. Dependencies are declared in `Package.swift` or Xcode project settings.

### Dependency Injection

We use **initializer injection** as the primary DI method:

```swift
// ViewModel receives dependencies via init
class MangaViewModel {
    private let repository: MangaRepository
    init(repository: MangaRepository) {
        self.repository = repository
    }
}

// Composition root in App layer
@main
struct MihonApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(
                    ViewModelFactory(
                        repository: MangaRepositoryImpl(
                            networkDataSource: MangaNetworkDataSourceImpl(),
                            localDataSource: MangaLocalDataSourceImpl(),
                            mapper: MangaMapper()
                        )
                    )
                )
    }
}
```

### Shared Dependencies

Common dependencies are defined in the `Core/` module:

- **Extensions**: Swift extensions for standard types
- **Utilities**: Logging, networking helpers, date formatting
- **Constants**: App-wide constants and strings
- **Dependencies**: Factory and DI helpers

## 🔄 Data Flow

### Typical Flow: User Action → Network Request → UI Update

```
User taps button
    ↓
View calls ViewModel method
    ↓
ViewModel executes Use Case
    ↓
Use Case calls Repository (Domain protocol)
    ↓
Repository Implementation (Data layer)
    ↓
Network/Data Source fetches data
    ↓
Data transformed via Mapper (DTO → Domain)
    ↓
Use Case returns Domain model
    ↓
ViewModel updates @Published property
    ↓
SwiftUI automatically updates View
```

### Example: Loading Manga Details

```swift
// 1. User interaction
MangaRow(manga: manga)
    .onTapGesture { viewModel.selectManga(manga) }

// 2. ViewModel triggers use case
func selectManga(_ manga: Manga) {
    Task {
        do {
            let details = try await getMangaDetailsUseCase.execute(mangaId: manga.id)
            await MainActor.run {
                self.selectedManga = details
                self.isShowingDetails = true
            }
        } catch {
            self.error = error
        }
    }
}

// 3. Use Case coordinates
func execute(mangaId: String) async throws -> MangaDetails {
    let manga = try await mangaRepository.getManga(id: mangaId)
    let chapters = try await chapterRepository.getChapters(mangaId: mangaId)
    return MangaDetails(manga: manga, chapters: chapters)
}

// 4. Repository fetches and transforms data
func getManga(id: String) async throws -> Manga {
    let dto = try await networkDataSource.fetchManga(id: id)
    return mapper.toDomain(dto)
}

// 5. UI updates automatically via @Published
```

## 🎨 Design Patterns

### MVVM (Model-View-ViewModel)

- **Model**: Domain entities and use cases
- **View**: SwiftUI view (declarative UI)
- **ViewModel**: `ObservableObject` that prepares data for the view

### Repository Pattern

Abstracts data sources, providing a clean API for the domain layer.

### Use Case (Interactor) Pattern

Encapsulates a single business operation. Each use case does one thing.

### Dependency Injection

All dependencies are injected, enabling testing and loose coupling.

### Factory Pattern

Used to create complex object graphs, especially in the App layer.

### Mapper/Transformer Pattern

Converts between different data representations (DTO ↔ Domain ↔ UI).

## 🧪 Testing Strategy

### Unit Tests

- **Domain Layer**: Test use cases with mocked repositories
- **Data Layer**: Test repository implementations with mocked data sources
- **UI Layer**: Test view models with mocked use cases

### Test Structure

```swift
// Example: Testing a use case
class GetMangaDetailsUseCaseTests: XCTestCase {
    func test_execute_returnsMangaDetails_whenMangaExists() async throws {
        // Arrange
        let mockRepo = MockMangaRepository()
        mock.mangaToReturn = Manga.testManga
        let useCase = GetMangaDetailsUseCaseImpl(
            mangaRepository: mockRepo,
            chapterRepository: MockChapterRepository()
        )

        // Act
        let result = try await useCase.execute(mangaId: "123")

        // Assert
        XCTAssertEqual(result.manga.id, "123")
        XCTAssertFalse(result.chapters.isEmpty)
    }
}
```

### UI Tests

- Test view rendering and user interactions
- Use `XCUITest` for end-to-end flows

### Integration Tests

- Test feature modules together
- Verify data flow across layers

## 🔄 Migration Path

### From Monolith to Modules

If starting from a monolithic codebase:

1. **Identify Features**: Group related functionality into features
2. **Extract Domain**: Move business logic to Domain layer
3. **Extract Data**: Move data access to Data layer
4. **Create UI**: Build SwiftUI views with view models
5. **Refactor Incrementally**: Do one feature at a time

### Adding New Features

1. Create new feature directory in `Features/`
2. Implement Data, Domain, and UI layers
3. Register dependencies in the composition root
4. Add navigation to feature
5. Write tests

## 📊 Module Dependencies Graph

```
App
├── Core (shared utilities)
├── Features/*
│   ├── Domain (depends on Core)
│   ├── Data (depends on Domain, Core)
│   └── UI (depends on Domain, Core)
└── Domain (global services)
    └── Data (global repositories)
```

**Rules**:
- Features should not depend on each other
- Shared code goes in `Core/` or `Domain/`
- If two features need to share code, extract it to `Core/` or a new shared module

## 🎯 Best Practices

1. **Keep ViewModels Simple**: Move complex logic to use cases
2. **Use Value Types**: Prefer `struct` over `class` for models
3. **Immutable Data**: Use `let` wherever possible
4. **Error Handling**: Use `throws` and propagate errors appropriately
5. **Async/Await**: Prefer over Combine for async operations
6. **Main Actor**: Annotate UI updates with `@MainActor`
7. **Protocols**: Define protocols in the layer that uses them
8. **Testing**: Write tests alongside implementation
9. **Documentation**: Document public APIs and complex logic
10. **Code Reviews**: All changes require review

## 📚 Further Reading

- [Clean Architecture](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html) by Robert C. Martin
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
- [Apple's MVC and MVVM](https://developer.apple.com/library/archive/documentation/General/Conceptual/DevPedia-CocoaCore/MVC.html)
- [Combine Framework](https://developer.apple.com/documentation/combine)

---

**Last Updated**: March 19, 2026

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

