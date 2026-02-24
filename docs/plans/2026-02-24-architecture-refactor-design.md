# TokenEater Architecture Refactor — Design Document

**Date:** 2026-02-24
**Branch:** `refactor/architecture-mv-repository`
**Scope:** Rename ClaudeUsage → TokenEater + MV/Repository pattern + @Observable

---

## Problem

The current `Shared/` module mixes concerns: singletons (`ClaudeAPIClient.shared`, `ThemeManager.shared`), static enums for I/O (`SharedContainer`, `KeychainOAuthReader`), and a large `MenuBarViewModel` (~300 lines) that handles state, refresh, rendering, and proxy config. No protocols exist, making testing impossible without hitting real Keychain/API/filesystem.

## Goals

- **Separation of concerns** via layered architecture (Models → Services → Repository → Stores)
- **Testability** via protocol-based services
- **Modern Swift** — `@Observable` replaces `ObservableObject`/`@Published`
- **Unified branding** — rename all "ClaudeUsage" references to "TokenEater"
- **Non-breaking** — same features, same behavior, same JSON format

## Architecture

### Layers

```
Models (pure data, Codable structs)
  ↓
Services (single-responsibility I/O, protocol-based)
  ↓
Repository (orchestrates services: Keychain → API → SharedFile)
  ↓
Stores (@Observable, injected via @Environment)
  ↓
Views (read from stores, call store methods)
```

### File Structure

```
Shared/
  ├── Models/
  │   ├── UsageModels.swift           # UsageResponse, UsageBucket, CachedUsage
  │   ├── PacingModels.swift          # PacingZone, PacingResult
  │   ├── ThemeModels.swift           # ThemeColors, UsageThresholds, ThemePreset
  │   └── ProxyConfig.swift           # ProxyConfig
  │
  ├── Services/
  │   ├── Protocols/
  │   │   ├── APIClientProtocol.swift
  │   │   ├── KeychainServiceProtocol.swift
  │   │   ├── SharedFileServiceProtocol.swift
  │   │   └── NotificationServiceProtocol.swift
  │   ├── APIClient.swift
  │   ├── KeychainService.swift
  │   ├── SharedFileService.swift      # Includes migration from old path
  │   └── NotificationService.swift
  │
  ├── Repositories/
  │   ├── UsageRepositoryProtocol.swift
  │   └── UsageRepository.swift
  │
  ├── Stores/
  │   ├── UsageStore.swift             # @Observable — usage state + auto-refresh
  │   ├── ThemeStore.swift             # @Observable — replaces ThemeManager
  │   └── SettingsStore.swift          # @Observable — proxy, menu bar, thresholds
  │
  ├── Helpers/
  │   ├── PacingCalculator.swift
  │   └── MenuBarRenderer.swift        # NSImage rendering (pure functions)
  │
  ├── Extensions/
  │   └── Extensions.swift
  │
  ├── en.lproj/
  └── fr.lproj/
```

### Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| DI mechanism | `@Environment` | Native SwiftUI, no third-party container |
| State management | `@Observable` macro | Replaces ObservableObject, simpler API |
| Menu bar rendering | `MenuBarRenderer` helper | Pure functions, no state, takes data in/image out |
| Theme system | Strategy pattern via `ThemeProviding` protocol | Clean preset switching + custom theme support |
| Migration code | Keep forever | ~10 lines, zero perf cost, protects late updaters on Homebrew |
| Singleton removal | All singletons → injected instances | Testability, explicit dependencies |

### Renaming Scope

- Folders: `ClaudeUsageApp/` → `TokenEaterApp/`, `ClaudeUsageWidget/` → `TokenEaterWidget/`
- Bundle IDs: `com.claudeusagewidget.app` → `com.tokeneater.app`
- Shared path: `com.claudeusagewidget.shared/` → `com.tokeneater.shared/` (with migration)
- Entitlements: update temporary-exception paths
- `project.yml`: target names, schemes, product names
- Types, comments, localization strings

### Widget Impact

Minimal. The widget only reads from `SharedFileService` (formerly `SharedContainer`). Updates needed:
- Import paths if types moved
- Entitlements path for new bundle ID
- `Provider.swift` uses `SharedFileService` instead of `SharedContainer`

### What Does NOT Change

- JSON format of `shared.json`
- All existing features (proxy, themes, notifications, pacing, localization)
- Onboarding UX flow
- Widget layouts (medium, large, small pacing)
