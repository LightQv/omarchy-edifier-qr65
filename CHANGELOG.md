# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

## [0.1.2] - 2026-09-21

### Fixed

- Keep daemon command cleanup reliable when Quickshell destroys the service.
- Reject empty successful responses instead of reusing previous collector data.

## [0.1.1] - 2026-09-21

### Added

- Marketplace preview and submission-readiness checks.
- Applied-color, brightness, color-matching, and daemon handoff controls.
- Explicit Consumer API and status validation with stale-status detection.

### Changed

- Bound daemon calls to a minimal environment and external deadline.
- Capped helper output before parsing and clean up active calls on destruction.
- Documented the complete marketplace tree, daemon trust boundary, and manual setup.

### Fixed

- Surface invalid theme accents and daemon failures instead of silently ignoring them.

[Unreleased]: https://github.com/LightQv/omarchy-edifier-qr65/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/LightQv/omarchy-edifier-qr65/releases/tag/v0.1.2
[0.1.1]: https://github.com/LightQv/omarchy-edifier-qr65/releases/tag/v0.1.1
