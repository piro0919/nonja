# Changelog

Notable changes to Nonja. `release.sh` publishes the section for the version being released as
its release notes, and stops if that section is missing or empty — so before releasing, rename
`Unreleased` to `[x.y.z] - YYYY-MM-DD` and commit.

Versions up to v0.2.4 predate this file; their history is in `git log`.

## [Unreleased]

### Changed

- Nonja is now shown in English unless the system language is Japanese.

### Fixed

- Clicking a notification now jumps to it on macOS in any language, not only Japanese. Mark All
  as Read also clears the app in Notification Center on English macOS; in other languages it
  still marks it as read in Nonja only.
- The permission prompt for controlling System Events is now in English.
- Clicking a notification or clearing an app no longer freezes Nonja while Notification Center
  opens.
- When the notification database is missing, Nonja now names the path it checked, the verified
  macOS version, and where to report it.

### Internal

- The build verifies the SHA-256 of the Sparkle archive it downloads.
- The release script runs the self test, and refuses a dirty working tree, a commit that is not
  on origin/main, an existing tag, a version the built app does not carry, or a missing
  changelog section.
- Releases stop instead of falling back to an ad-hoc signature when the signing certificate is
  missing.
