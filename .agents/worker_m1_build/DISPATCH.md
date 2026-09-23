# Task Assignment: Milestone 1 — Production Release Build & Version Bump (v0.3.1+4)

## Objective
Bump version to v0.3.1+4 in pubspec.yaml, run static analysis and unit tests with 100% pass rate, and build the standalone production release APK using JDK 17.

## Working Directory
- Project Root: F:\Projects\aperture-grafik
- Agent Directory: F:\Projects\aperture-grafik\.agents\worker_m1_build

## Mandatory Inputs & Constraints
- Read ORIGINAL_REQUEST.md at F:\Projects\aperture-grafik\.agents\ORIGINAL_REQUEST.md.
- DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.
- JDK 17 is strictly required: set `$env:JAVA_HOME = "F:\Development\jdk-17"` before running Flutter commands.
- Verify zero compiler warnings.
- Run `flutter analyze` and ensure 0 issues.
- Run `flutter test` and ensure 100% pass rate.
- Run `flutter build apk --release` with JDK 17.
- Confirm the output APK exists at `build/app/outputs/flutter-apk/app-release.apk` (and note its file size and sha256 checksum).
- Also check whether `aperture-grafik-release.apk` in project root should be updated/copied from the new release build.

## Expected Deliverables
Write `handoff.md` in `F:\Projects\aperture-grafik\.agents\worker_m1_build\handoff.md` containing:
1. Version bump details in `pubspec.yaml`.
2. Output of `flutter analyze` (must be 0 issues).
3. Output of `flutter test` (all tests passing).
4. Build command output and status for `flutter build apk --release`.
5. Exact path, file size, and SHA256 checksum of the compiled release APK.
Send a message to orchestrator upon completion.
