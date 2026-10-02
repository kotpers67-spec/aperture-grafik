# Aperture Grafik — code review

**Review date:** 2026-10-02
**Release candidate:** `v0.3.9`
**Repository:** `F:\Projects\aperture-grafik`

## Scope

Reviewed schedule and payout calculations, adaptive salary restoration, app-state persistence and backup import/export, SQLite storage, update discovery/download/install, theme composition, animations, accessibility behavior, and the relevant automated tests.

## Review findings and fixes

- Fixed an incorrect save-failure warning: a failed older write is now silent when a newer complete state snapshot is already current; a failed current write rolls back to the last persisted state and reports the error. Added a regression assertion for this race.
- Payout reconciliation retains the configured daily rate, scopes changes to the payout accrual period, and is repeatable. Existing tests cover the 1,300 ₽ daily rate, 30% advance, late advance recording, repeated recalculation, adaptive salary being switched off, and manual earnings.
- Calendar-day ordinal arithmetic is used for shift rotation, overnight end dates, next-workday search, and payout countdowns to avoid daylight-saving/timezone day drift.
- Update downloads reject malformed versions, non-HTTPS URLs and redirects, failed HTTP responses, empty files, and content-length mismatches. Incomplete files are removed. The app writes an automatic JSON backup before opening Android's installer and blocks installation if backup creation fails.
- Theme palettes and visual styles are separate; existing enum values remain stable for saved settings. Navigation, shift completion, and page changes honor both the app motion toggle and the system reduced-motion setting.
- SQLite replaces the single state payload transactionally. Invalid stored JSON is quarantined and startup fails visibly rather than silently replacing user data with defaults.

No blocking correctness or analyzer findings remain in the reviewed changeset.

## Remaining risks

| Priority | Finding | Impact |
|---|---|---|
| P2 | Automatic backups are unencrypted and kept in app-specific documents storage. | They are not a copy outside the phone/app data; uninstalling app data removes them. Use manual export for an off-device copy. |
| P2 | Notification timezone is fixed to `Europe/Moscow`. | Reminders may use an unexpected local time outside Moscow's timezone. |
| P2 | The full application state is stored in one JSON payload with schema version 1. | Future data-model changes need an explicit migration strategy. Corrupt data currently requires recovery instead of normal startup. |
| P2 | Most presentation code remains in `lib/presentation/app_shell.dart`. | Screen changes have a broad regression surface and are harder to test independently. |
| P2 | The Android release APK is signed with the local debug keystore. | The `v0.3.8` release uses the same certificate as this candidate, so this update remains compatible. Losing that key or building from a different machine would break in-place updates; establish a protected persistent release key before changing build infrastructure. |
| P2 | Device-level flows are not covered by automated tests. | Android installer hand-off, notification delivery, backup recovery after an update, and accessibility across physical devices still need manual device validation. |

The build also reports a forward-compatibility warning for `file_picker`, `package_info_plus`, and `share_plus` using the Kotlin Gradle Plugin. It does not currently block the release build.

## Verification

| Check | Result |
|---|---|
| `flutter analyze --no-pub` | Passed: no issues found |
| `flutter test --no-pub` | Passed: 48 tests |
| `git diff --check` | Passed; Windows reports expected LF-to-CRLF working-copy notices |
| `flutter build apk --release --no-pub` | Passed: APK built, version `0.3.9` / code `15` |
| APK signature compared with `v0.3.8` | Passed: same SHA-256 signer certificate |

Review does not include a physical Android device run or a validation of every device manufacturer's installer and notification behavior.
