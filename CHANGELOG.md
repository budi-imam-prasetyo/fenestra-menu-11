# Changelog

## 1.5.0 — 2026-10-28

### Added

- A shared KDE theme-based design system for colors, type, spacing, radii, control sizes and interaction states.
- A consistent three-mode view selector and a separate keyboard-accessible category dropdown.
- A compact pinned empty state, application-icon fallbacks, and matched list/tile layouts.
- Isolated visual/input scenarios, large-collection benchmarks, median/p95 latency reporting and resource observations.

### Changed

- Retain bounded List/Grid viewports after their first use; view changes reuse models and preserve per-view scroll state and selected applications.
- Share one application delegate with folder-only affordances created on demand.
- Cache category rows and coalesce category-tile updates; inactive filtered views no longer rebuild delegates.
- Use content width for columns, native-theme interface icons, stable search-page switching and common control feedback.
- Suspend the launcher app-scan timer while closed. Keep the existing Rust API and QML-only fallback.

### Fixed

- A self-shadowed `core` reference that prevented the optional native facade from reaching the launcher popup.
- Duplicate activation paths, a drag-source reference, context-menu keyboard coordinates, and a KDE Connect device-selector implicit-size binding loop.

KDE Connect layout, account/power actions, settings storage and public native APIs remain compatible. Widget metadata moves from 1.4.2 to 1.5.0 for compatible public UI features; Rust crate versions remain unchanged because their API did not change. No tag or release publication is implied.
