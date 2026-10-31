# Changelog

Format based on [Keep a Changelog](https://keepachangelog.com/). Versions follow [SemVer](https://semver.org/).
Pre-releases (`-dev.N`) are built automatically from the `dev` branch; stable releases are made by hand.

## [0.3.0] - unreleased

### Added
- Ban system: `/ban`, `/unban`, `/bans`, `/kick` with persistent bans (`ay_bans`, migration `002_bans`),
  timed or permanent, matched on several identifiers, rank-checked, offline bans by license.
- `AY.Bans` API (`Ban`, `Unban`, `Check`, `List`, `ParseDuration`, `CleanReason`).
- `AY.Notify` (server and client) for satellite resources.
- `/tp`, `/goto`, `/bring` admin teleport commands (`ServerConfig.Admin`).
- `tests/bans_spec.lua`: offline logic tests that run against stubbed FiveM natives.
- GitHub Actions: syntax check + tests, then an automatic pre-release for every push to `dev`.

### Fixed
- `AY.HasPermission` failed **open** when a required group did not exist (for example a typo such as
  `SpawnGroup = 'adimn'` let every player use `/car`). It now denies and logs a warning.

### Removed
- `server/callbacks.lua` and `client/callbacks.lua`: dead code, not loaded by the manifest and
  referencing an undefined `Config.CallbackTimeout`. Callbacks live in `import.lua`.

### Changed
- All text files normalized to LF line endings (`.gitattributes`).

## [0.2.0]
- Baseline imported into this repository.
