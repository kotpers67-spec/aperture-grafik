# Original User Request

## 2026-09-23T13:41:49Z

Comprehensive full-scope code and architecture review of the Aperture Grafik offline-first Android Flutter application.

Working directory: F:\Projects\aperture-grafik
Integrity mode: development

## Requirements

### R1. Architecture & Layering Integrity
Audit cross-layer boundaries (presentation → application → domain ← data) to ensure strict separation of concerns, no leaky database or UI abstractions, and clean Riverpod state lifecycle management without memory leaks.

### R2. Finance, Shift Logic & Calculation Edge Cases
Audit shift calculations, overnight time math, coefficient & rate overrides, manual earnings precedence, advance/salary cycle countdowns, and potential edge-case rounding or timezone issues.

### R3. UI/UX, Anti-Overlap & Material 3 Compliance
Inspect screens, bottom sheets, and dialogs for text wrapping, overflow immunity on compact viewports and high DPI scaling, and adherence to coffee-shop Material 3 styling.

### R4. Data Persistence, Backup & Privacy
Verify SQLite database transactions, schema migration safety, UTF-8 clean JSON backup import/export schema validation, and on-device privacy guarantees.

## Acceptance Criteria

### Verification
- [ ] Automated test suite runs with 100% pass rate (`flutter test`)
- [ ] Static analyzer reports 0 issues (`flutter analyze`)
- [ ] Detailed actionable review report produced with concrete code snippets, categorized findings, and priority rankings (P0 Critical, P1 High, P2 Medium, P3 Polish)

## 2026-09-23T14:14:22Z

Comprehensive Verification Re-Audit of Aperture Grafik after P0/P1 remediation:
- Button width infinite layout crash fixed (app_theme.dart: Size(64, 56))
- Calendar month selector 240px overflow fixed (app_shell.dart: Expanded with ellipsis)
- Corrupted SQLite payload quarantine & transactions implemented (sqlite_app_repository.dart)
- AsyncValue.error crash cascade fixed with state preservation (app_controller.dart)
- Statistics chart bucketing for week (chronological difference) and year (monthly) fixed (app_shell.dart)
- Overnight active shift recognition and completion date fixed (app_shell.dart)
- Safe enum deserialization (byNameOr) implemented across models (models.dart)
- FilePicker empty/null safe guard & global exception catching on backup import (app_shell.dart)
- Bottom sheet safe area enabled for Android gesture bar (app_shell.dart)
- Dead dependencies (go_router, cupertino_icons) removed (pubspec.yaml)

Working directory: F:\Projects\aperture-grafik
Integrity mode: development

## Requirements

### R1. Post-Remediation Architecture & Layout Verification
Verify all applied P0 and P1 fixes in code across core layers, checking that no new layout overflow or state errors were introduced.

### R2. Finance, Shift Logic & Accounting Re-Audit
Re-audit overnight shift resolution, statistics chart bucketing, and payout status calculations against the updated implementation.

### R3. UI/UX, Anti-Overlap & Error Boundary Re-Audit
Verify that the button theme fix, calendar month selector fix, and backup import hardening adhere strictly to Android layout guidelines and Anti-Overlap rules.

### R4. Data Safety & Persistence Re-Audit
Verify SQLite transactions, quarantine table creation, and safe enum parsing fallback behaviors.

## Acceptance Criteria

### Verification
- [ ] Automated test suite runs with 100% pass rate (`flutter test`)
- [ ] Static analyzer reports 0 issues (`flutter analyze`)
- [ ] Comprehensive verification re-audit report published confirming resolution of prior findings

## 2026-09-23T17:20:42Z

Deploy and verify the v0.3.1 release of Aperture Grafik across GitLab Generic Packages, GitLab Releases, GitHub Releases, and local desktop APK distribution.

Working directory: F:\Projects\aperture-grafik
Integrity mode: development

## Requirements

### R1. Production Release Build & Version Bump (v0.3.1+4)
Build the standalone release APK using JDK 17 ($env:JAVA_HOME = "F:\Development\jdk-17") and verify zero compiler warnings, static analysis clean (`flutter analyze`), and all unit tests passing (`flutter test`).

### R2. GitLab & GitHub Release Deployment
- Upload the built `aperture-grafik.apk` binary to GitLab Generic Package Registry (`santiyastudio/aperture-grafik/packages/generic/aperture-grafik/0.3.1/aperture-grafik.apk`) using token `glpat-dt78DIIIIfmrarGxYWJRbmM6MQpvOjEKdTpwYmd0eg8.01.170b6enh9`.
- Create the GitLab Release `v0.3.1` with the package asset link attached.
- Tag and publish GitHub Release `v0.3.1` (`santiyastudio-lgtm/aperture-grafik`) with the APK attached via `gh release create`.
- Push git commit and tags `v0.3.1` to both `gitlab` and `origin` remotes.

### R3. Desktop Distribution & In-App Auto-Update Verification
- Copy the release APK to `C:\Users\kotpe\OneDrive\Desktop\aperture-grafik.apk`.
- Verify that previous versions (v0.2.0, v0.3.0) detect the v0.3.1 release via GitLab/GitHub API, stream the APK with background progress/ETA notifications, and trigger system APK installation without 404 errors.

## Acceptance Criteria

### Build & Verification
- [ ] `flutter analyze` reports 0 issues
- [ ] `flutter test` reports 100% pass rate
- [ ] Release APK compiled and verified at `C:\Users\kotpe\OneDrive\Desktop\aperture-grafik.apk`
- [ ] GitLab Release `v0.3.1` created and downloadable via public URL
- [ ] GitHub Release `v0.3.1` published with asset
