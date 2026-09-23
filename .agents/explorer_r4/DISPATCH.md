# R4 Data Safety, Persistence & Serialization Re-Audit Dispatch

Target Codebase: F:\Projects\aperture-grafik
Original Request: F:\Projects\aperture-grafik\ORIGINAL_REQUEST.md
Prior Report: F:\Projects\aperture-grafik\REVIEW_REPORT.md
Working Directory: F:\Projects\aperture-grafik\.agents\explorer_r4

Tasks:
1. Re-audit `lib/data/sqlite_app_repository.dart`:
   - Inspect `load()` and error handling on corrupt payloads.
   - Verify that corrupted SQLite payloads are quarantined (e.g. into `app_state_quarantine` table) rather than silently overwritten with `AppState.initial()`.
   - Verify whether quarantine table creation and error throwing are implemented properly.
   - Verify that `replace` / `save` wraps database operations in `db.transaction(...)` for atomic consistency.
2. Re-audit `lib/domain/models.dart`:
   - Inspect enum deserialization across models (`AppThemeMode`, `ShiftType`, `DayOffReason`, etc.).
   - Verify that `byNameOr` safe fallback extension or equivalent safe deserialization is implemented and used to prevent unhandled `ArgumentError` crashes on unknown enum strings.
3. Re-audit `lib/presentation/app_shell.dart`:
   - Inspect backup import (`_import` / `_importBackup`).
   - Verify `FilePicker` safe guards (handling null, empty files list, or picking cancellation without `StateError`).
   - Verify global exception catching (`catch (e)` or catching all `Object`/`Exception`) so `TypeError` and `ArgumentError` cannot crash the application during backup restore.
4. Provide code snippets, line numbers, analysis, and verdict in F:\Projects\aperture-grafik\.agents\explorer_r4\handoff.md.
