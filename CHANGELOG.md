# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.1] - 2026-11-12

### Fixed

- CI on Windows: the Sparkle test vectors were checked out with CRLF line endings
  (Windows runners default to `core.autocrlf=true`), so the byte-for-byte signature
  tests failed. A `.gitattributes` file now keeps LF everywhere and never converts
  `test/vectors/` and `test/fixtures/`. No library or CLI behavior changed.

## [0.1.0] - 2026-11-12

### Added

- Appcast parser that finds Sparkle elements by namespace URI (any prefix works),
  reads the `au:sha256` extension attribute and reports malformed items instead of failing the feed.
- `compareVersions` with the rules of Sparkle's `SUStandardVersionComparator`.
- `UpdateSelector`: os, channels, minimum and maximum system version, phased rollout
  (7 groups), critical updates and downgrade blocking, with a reason for every rejected item.
  `RolloutGroupStore` keeps the group of an install.
- Ed25519 signing and verification that matches Sparkle 2.10.1 `sign_update` byte for byte.
- `UpdateVerifier`: size, signature, `au:sha256` and downgrade checks, in that order.
- `SignedFeed`: Sparkle 2.9+ `sparkle-signatures` feed signatures (sign, verify, strip).
- `AppcastWriter` to create feeds and add items.
- `Fetcher` for `file://` and `https://` with a size cap; plain `http://` only on request.
- `Updater` facade: `check()` and `downloadAndVerify()`.
- `appcast` command line: `keygen`, `pubkey`, `sign`, `verify`, `add`, `sign-feed`, `verify-feed`,
  `check --explain`; English and Korean (`--lang`, `APPCAST_UPDATER_LANG`, locale variables).
- Legacy 96-byte private keys are recognized: public key and verification work, signing exits with code 3.
- Offline practice example (`dart run example/main.dart`).

[Unreleased]: https://github.com/LeeGyeongPil/appcast-updater/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/LeeGyeongPil/appcast-updater/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/LeeGyeongPil/appcast-updater/releases/tag/v0.1.0
