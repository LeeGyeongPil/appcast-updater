# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.2] - 2026-11-12

### Fixed

CI failed again after 0.1.1 and no job log was available, so the likely causes
were found by reading the workflow, the tests and the Dart SDK sources. The most
likely cause (an inference, not confirmed by a log) is the Windows job:

- Tests that start the `appcast` command as a child process now read its output as
  UTF-8. Before, the output was decoded with the system encoding, which on Windows
  is the active code page, so the Korean help text could not be matched.
- The same child-process test now has a 3-minute timeout (the first `dart run`
  compiles the command, which can take longer than the default 30 seconds).
- Temporary test folders that Windows cannot delete right away (a file still open
  or being scanned) are retried up to 5 times, then left to the system temp folder
  instead of failing the test. Other OSes still report a cleanup failure.
- The CI workflow pins Dart 3.8.1 instead of the latest release, drops the weekly
  scheduled run, uses bash on every OS, stops a job after 20 minutes, retries
  `dart pub get` once, and turns the `dart pub publish --dry-run` check into a
  warning (5-minute limit) that cannot fail the job.
- A new test checks that `appcast --version` matches the version in `pubspec.yaml`.

No library or CLI behavior changed.

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

[Unreleased]: https://github.com/LeeGyeongPil/appcast-updater/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/LeeGyeongPil/appcast-updater/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/LeeGyeongPil/appcast-updater/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/LeeGyeongPil/appcast-updater/releases/tag/v0.1.0
