# Scope: Aperture Grafik v0.3.1 Release Deployment & Verification

## Architecture & Release Target
- App: Aperture Grafik (Flutter Android offline-first application)
- Release Version: v0.3.1+4 (SemVer 0.3.1, Build 4)
- Target Artifact: aperture-grafik.apk (standalone release APK)
- Build Toolchain: Flutter, Dart, JDK 17 ($env:JAVA_HOME = "F:\Development\jdk-17")
- Package Registries:
  - GitLab Generic Package Registry: `santiyastudio/aperture-grafik/packages/generic/aperture-grafik/0.3.1/aperture-grafik.apk`
  - GitLab Release: v0.3.1
  - GitHub Release: santiyastudio-lgtm/aperture-grafik (v0.3.1)
  - Desktop Distribution: `C:\Users\kotpe\OneDrive\Desktop\aperture-grafik.apk`

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | Production Release Build & Version Bump | Bump pubspec.yaml to v0.3.1+4, flutter analyze (0 errors), flutter test (100%), flutter build apk --release with JDK 17 | none | PLANNED |
| 2 | GitLab & GitHub Release Deployment | Upload APK to GitLab Generic Package Registry with token, create GitLab Release v0.3.1, push git tags to origin and gitlab, create GitHub Release v0.3.1 via gh | M1 | PLANNED |
| 3 | Desktop Distribution & In-App Auto-Update Verification | Copy APK to Desktop, verify UpdateService endpoints and in-app update flow for v0.2.0/v0.3.0 → v0.3.1 | M1, M2 | PLANNED |
| 4 | QA Reality Check & Final Certification | Verify all release URLs, asset accessibility, test reports, checksums, zero-mock certification | M1, M2, M3 | PLANNED |
