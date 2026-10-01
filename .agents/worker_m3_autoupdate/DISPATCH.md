# Task Assignment: Milestone 3 — Desktop Distribution & In-App Auto-Update Verification

## Objective
Verify desktop distribution of the release APK and execute comprehensive end-to-end verification of the In-App Auto-Update flow from previous versions (v0.2.0, v0.3.0) to v0.3.1.

## Working Directory
- Project Root: F:\Projects\aperture-grafik
- Agent Directory: F:\Projects\aperture-grafik\.agents\worker_m3_autoupdate

## Mandatory Requirements & Verification Steps
1. Verify `C:\Users\kotpe\OneDrive\Desktop\aperture-grafik.apk`:
   - Exact size: 59,919,418 bytes
   - SHA-1: EFC6CFBF1FAF4A50A4B06A6CEB70832347188F47
   - File is readable and not locked.
2. In-App Auto-Update Mechanism Audit:
   - Examine `lib/domain/update_service.dart`.
   - Verify GitLab releases endpoint: `https://gitlab.com/api/v4/projects/santiyastudio%2Faperture-grafik/releases/permalink/latest`.
   - Verify SemVer comparison logic for both v0.2.0 and v0.3.0 detecting v0.3.1 as an available update.
   - Verify asset URL extraction from GitLab release payload (`assets.links` pointing to generic package registry APK).
3. Live Download & Streaming Verification:
   - Perform a live stream download test from the public GitLab package URL.
   - Verify HTTP status (200 OK), presence of `Content-Length: 59919418`, stream chunking, and calculate progress/ETA.
   - Ensure zero 404 errors on download URL or redirects.
4. Auto-Update Tests:
   - Run `flutter test` (including any update service tests) using `$env:JAVA_HOME = "F:\Development\jdk-17"`.
   - Document any automated tests that cover update checking, progress calculation, and installer intent invocation.
5. Produce Report:
   - Write full findings, network logs, and verification evidence to `F:\Projects\aperture-grafik\.agents\worker_m3_autoupdate\handoff.md`.

## 2026-09-23T17:39:29Z
You are worker_m3_autoupdate, responsible for Milestone 3: Desktop Distribution & In-App Auto-Update Verification.
Your working directory is F:\Projects\aperture-grafik\.agents\worker_m3_autoupdate.
Project root is F:\Projects\aperture-grafik.

Read your task description in F:\Projects\aperture-grafik\.agents\worker_m3_autoupdate\DISPATCH.md and ORIGINAL_REQUEST.md at F:\Projects\aperture-grafik\.agents\ORIGINAL_REQUEST.md.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All tests and verification must be genuine. DO NOT fabricate outputs or circumvent real verification. A teamwork_preview_auditor will independently inspect your evidence.

Execute the following steps:
1. Check `C:\Users\kotpe\OneDrive\Desktop\aperture-grafik.apk` (size, hash, readability).
2. Audit `lib/domain/update_service.dart` and `test/` for auto-update logic.
3. Verify that from versions `v0.2.0` and `v0.3.0`, the updater queries the latest release (`v0.3.1`) and correctly identifies it as a newer version (`hasUpdate == true`).
4. Perform live network validation against the live GitLab endpoint:
   - Query `https://gitlab.com/api/v4/projects/santiyastudio%2Faperture-grafik/releases/permalink/latest`
   - Verify that the asset link leads to `https://gitlab.com/api/v4/projects/santiyastudio%2Faperture-grafik/packages/generic/aperture-grafik/0.3.1/aperture-grafik.apk`
   - Test streaming download of the APK (verifying HTTP 200, Content-Length header, progress/ETA calculation, and zero 404 errors).
5. Run `flutter test` with `$env:JAVA_HOME = "F:\Development\jdk-17"`.
6. Write full report in `F:\Projects\aperture-grafik\.agents\worker_m3_autoupdate\handoff.md` and message the orchestrator when finished.
