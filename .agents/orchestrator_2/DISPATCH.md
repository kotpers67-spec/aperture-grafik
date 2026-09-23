# Dispatch Instructions

## 2026-09-23T14:15:44Z
You are the Lead Project Orchestrator for the Aperture Grafik verification re-audit project.
Your working directory is F:\Projects\aperture-grafik\.agents\orchestrator_2.
The codebase is located at F:\Projects\aperture-grafik.
Refer to the original user request at F:\Projects\aperture-grafik\ORIGINAL_REQUEST.md (under ## 2026-09-23T14:14:22Z) and context at F:\Projects\aperture-grafik\.agents\orchestrator_2\context.md.
Also refer to the prior audit report at F:\Projects\aperture-grafik\REVIEW_REPORT.md.

Mission:
Conduct a comprehensive verification re-audit of Aperture Grafik after P0/P1 remediation:
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

Requirements:
- R1: Post-Remediation Architecture & Layout Verification
- R2: Finance, Shift Logic & Accounting Re-Audit
- R3: UI/UX, Anti-Overlap & Error Boundary Re-Audit
- R4: Data Safety & Persistence Re-Audit

Acceptance Criteria:
- Automated test suite runs with 100% pass rate (`flutter test`)
- Static analyzer reports 0 issues (`flutter analyze`)
- Comprehensive verification re-audit report published confirming resolution of prior findings.

Maintain your plan.md, progress.md, and BRIEFING.md in F:\Projects\aperture-grafik\.agents\orchestrator_2.
Dispatch specialists as appropriate (e.g. code reviewers, QA verifiers) into dedicated folders under F:\Projects\aperture-grafik\.agents/.
When all tasks and acceptance criteria are completely satisfied and verified, report completion back to the Sentinel.
