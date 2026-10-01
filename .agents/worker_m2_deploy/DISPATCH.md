# Task Assignment: Milestone 2 — Release Deployment (GitLab & GitHub) & Validation

## Objective
Run test/analysis validation, deploy the v0.3.1 release across GitLab Generic Package Registry, GitLab Releases, GitHub Releases, and push git tags to all remotes.

## Working Directory
- Project Root: F:\Projects\aperture-grafik
- Agent Directory: F:\Projects\aperture-grafik\.agents\worker_m2_deploy

## Mandatory Instructions
1. Run `flutter analyze` and record output (must be 0 issues).
2. Run `flutter test` with `$env:JAVA_HOME = "F:\Development\jdk-17"` and record output (100% pass).
3. Copy `build\app\outputs\flutter-apk\app-release.apk` to `aperture-grafik-release.apk` at root of project and verify `C:\Users\kotpe\OneDrive\Desktop\aperture-grafik.apk`.
4. Upload `build\app\outputs\flutter-apk\app-release.apk` to GitLab Generic Package Registry:
   - Endpoint: `https://gitlab.com/api/v4/projects/santiyastudio%2Faperture-grafik/packages/generic/aperture-grafik/0.3.1/aperture-grafik.apk`
   - Header: `PRIVATE-TOKEN: glpat-dt78DIIIIfmrarGxYWJRbmM6MQpvOjEKdTpwYmd0eg8.01.170b6enh9`
   - Method: PUT
   - Verify upload response status (201 Created or equivalent).
5. Create GitLab Release `v0.3.1`:
   - Endpoint: `https://gitlab.com/api/v4/projects/santiyastudio%2Faperture-grafik/releases`
   - Tag: `v0.3.1`
   - Assets link pointing to the generic package APK URL.
6. Push git commit and tags `v0.3.1` to both `origin` and `gitlab` remotes:
   - `git push origin main --tags`
   - `git push gitlab main --tags` (or appropriate remote name).
7. Create GitHub Release `v0.3.1` on `santiyastudio-lgtm/aperture-grafik` with APK attached using `gh release create`.
8. Verify download endpoints return HTTP 200 / successful asset retrieval.

Write full results, commands executed, HTTP response codes, and URLs to `F:\Projects\aperture-grafik\.agents\worker_m2_deploy\handoff.md`.

## 2026-09-23T17:38:11Z
From: 61430de7-5711-42ab-8573-59f8a6a28527
**Context**: Milestone 2 Release Deployment
**Content**: Safety timer triggered. What is the current status of task-157 and Milestone 2 steps (flutter analyze, flutter test, uploads)?
**Action**: Please report current progress and any blocked operations.
