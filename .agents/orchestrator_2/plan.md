# Plan: Aperture Grafik Verification Re-Audit

## Objective
Conduct a comprehensive verification re-audit of the Aperture Grafik offline-first Android Flutter codebase following P0/P1 remediation across Architecture, Finance, UI/UX, and Data Persistence.

## Scope Breakdown
1. **QA Reality Check**:
   - Run `flutter test` and `flutter analyze` in `F:\Projects\aperture-grafik`.
   - Verify 100% test pass rate and 0 analyzer issues.
   - Verify removal of dead dependencies (`go_router`, `cupertino_icons`).

2. **R1 & R3: Architecture, Layout & UI/UX Re-Audit**:
   - `app_theme.dart`: `minimumSize: const Size(64, 56)` for button themes (filled & outlined).
   - `app_shell.dart`: Calendar month selector 240px overflow fixed with `Expanded` + `TextOverflow.ellipsis`.
   - `app_shell.dart`: Bottom sheet safe area enabled for Android gesture bar (`useSafeArea: true`).
   - `app_controller.dart`: `_save` state preservation using `.copyWithPrevious` on `AsyncValue.error`.

3. **R2: Finance, Shift Logic & Accounting Re-Audit**:
   - `app_shell.dart`: Statistics chart bucketing for week (chronological difference/weekday) and year (monthly).
   - `app_shell.dart`: Overnight active shift recognition (00:00–06:00) and completion date recorded under start date.
   - `finance_service.dart`: Payout calculations and shift boundary inclusions.

4. **R4: Data Safety, Persistence & Serialization Re-Audit**:
   - `sqlite_app_repository.dart`: Corrupted SQLite payload quarantine table creation and error propagation.
   - `sqlite_app_repository.dart`: Database atomic transactions on state writes.
   - `models.dart`: Safe enum deserialization (`byNameOr`) fallback implementation across all models.
   - `app_shell.dart`: `FilePicker` empty/null safe guard & global exception catching on backup import.

5. **Forensic Integrity Audit**:
   - Independent verification that implementations are genuine, zero mocks in production code, zero dummy logic.

6. **Synthesis & Publishing**:
   - Compile comprehensive verification re-audit report: `RE_AUDIT_REPORT.md` in `F:\Projects\aperture-grafik`.
   - Report final completion to Sentinel.
