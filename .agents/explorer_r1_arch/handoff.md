# Handoff Report — R1. Architecture & Riverpod Audit

**Author**: explorer_r1_arch  
**Role**: Architecture & Riverpod Auditor  
**Working Directory**: `F:\Projects\aperture-grafik\.agents\explorer_r1_arch`  
**Target Project**: `F:\Projects\aperture-grafik`  
**Date**: 2026-09-23  

---

## 1. Observation

- **Tool Execution & Baseline Status**:
  - `& "F:\Development\flutter\bin\flutter.bat" analyze`: Exited with code 0 (`No issues found!`).
  - `& "F:\Development\flutter\bin\flutter.bat" test`: Exited with code 0 (`All 13 tests passed!`).
- **Dependencies (`pubspec.yaml`)**:
  - `flutter_riverpod: ^3.0.0` is specified in `pubspec.yaml:18`.
- **Database Architecture (`lib/data/sqlite_app_repository.dart`)**:
  - Line 19: `CREATE TABLE app_state (id INTEGER PRIMARY KEY, payload TEXT NOT NULL)`.
  - Line 34-41: Catch block catches all exceptions during `jsonDecode` / `AppState.fromJson` and returns `AppState.initial()`.
  - Line 45-50: `save(AppState state)` executes `INSERT INTO app_state VALUES (1, jsonEncode(state.toJson())) ON CONFLICT REPLACE`.
- **Riverpod Implementation (`lib/application/app_controller.dart`)**:
  - Line 4: `import 'package:flutter_riverpod/legacy.dart';`
  - Lines 16-19: `StateNotifierProvider<AppController, AsyncValue<AppState>>`.
  - Lines 21-24: `class AppController extends StateNotifier<AsyncValue<AppState>> { AppController(...) { initialize(); } }`. Unawaited async call in constructor.
  - Line 38: `AppState get _data => state.requireValue;`.
  - Lines 40-47: `_save` sets `state = AsyncValue.error(error, stackTrace)` without `copyWithPrevious`.
- **UI & State Binding (`lib/presentation/app_shell.dart` and `lib/main.dart`)**:
  - `lib/presentation/app_shell.dart:33`: `final data = ref.watch(appControllerProvider).requireValue;`.
  - `lib/presentation/app_shell.dart:35-40`: `data` (monolithic `AppState`) drilled down to `HomePage`, `CalendarPage`, `StatisticsPage`, `ProfilePage` inside `IndexedStack`.
  - Zero usages of `ref.watch(provider.select(...))` in entire repository.
  - Direct domain service instantiation: Lines 431, 440, 570, 1203, 1576, 1650, 2183 instantiate `const ScheduleService()`, `const FinanceService()`, and `const RevenueRecommendationService()`.
  - Monolithic file: `lib/presentation/app_shell.dart` contains 3,562 lines.
- **Notification Lifecycle (`lib/main.dart` & `lib/core/notifications/notification_service.dart`)**:
  - `lib/main.dart:34-42`: `_stateSubscription = ref.listenManual(...)` with `fireImmediately: true` invokes `scheduleNextEndReminder(data)` on all state mutations.
  - `lib/core/notifications/notification_service.dart:22`: `tz.setLocalLocation(tz.getLocation('Europe/Moscow'));` hardcoded.
  - Lines 80-88: `_cancelShiftReminders()` loops from 1000 to 1097 cancelling 97 alarms. Lines 63-77 loop 96 times scheduling repeat alarms.

---

## 2. Logic Chain

1. **Catastrophic Data Loss (P0)**:
   - Observation: `sqlite_app_repository.dart:34-41` catches JSON decode/parsing errors and returns `AppState.initial()`.
   - Observation: `sqlite_app_repository.dart:45-50` saves `AppState` by replacing row 1 with JSON-encoded data.
   - Inference: If a payload is unparseable (e.g. corrupted byte, schema version mismatch, bad backup import), `load()` silently treats the database as empty (`AppState.initial()`). The subsequent user action or auto-save triggers `save()`, which overwrites row 1 in SQLite, permanently erasing the user's historical records.

2. **UI Crash & Screen Teardown on Save Error (P0)**:
   - Observation: `app_controller.dart:40-47` sets `state = AsyncValue.error(...)` if `_repository.save` fails.
   - Observation: `app_shell.dart:33` calls `.requireValue`. `app_controller.dart:38` calls `.requireValue`. `main.dart:68` replaces the home widget with `_StartupError` on error.
   - Inference: Any transient SQLite or disk write error causes `.requireValue` to throw unhandled `StateError`, and unmounts the entire app view in `main.dart`, losing user input and current screen state.

3. **Riverpod 3 Deprecation & Lifecycle Risk (P1)**:
   - Observation: `app_controller.dart:4` imports `legacy.dart` for `StateNotifier`. Constructor fires `initialize()` unawaited without checking `mounted`.
   - Inference: If the notifier is destroyed while `initialize()` is in flight, setting `state` throws `StateError: Bad state: Cannot emit new states after calling dispose`.

4. **Platform Alarm Saturation & Timezone Flaw (P1)**:
   - Observation: `main.dart:34-42` calls `scheduleNextEndReminder` on every `AppState` change. `notification_service.dart:22` hardcodes Moscow time.
   - Inference: Every edit (theme change, colleague edit, note change) un-awaitedly cancels 97 alarms and reschedules 96 alarms, causing concurrency races and platform overhead. Hardcoded timezone breaks notifications outside Moscow.

5. **Performance Rebuild Storm Across IndexedStack (P1)**:
   - Observation: `AppShell` watches monolithic `AppState` and passes it to all 4 tabs in `IndexedStack`. No `.select()` is used.
   - Inference: All 4 tabs remain alive and rebuild simultaneously on every change, executing heavy domain math and list filtering inside `Widget.build`.

---

## 3. Caveats

- **Calculation Logic (R2)**: Specific financial edge cases (overnight time math, rate overrides, countdown details) were reviewed only from an architectural standpoint; deep algorithmic verification belongs to the R2 auditor.
- **UI Overflow & Anti-Overlap (R3)**: Visual rendering, text overflow, and Material 3 design tokens across viewports were noted (e.g. `app_shell.dart` file size) but belong to the R3 auditor.
- **Backup & SQLite Migrations (R4)**: Data serialization flaws were flagged from a layering and data-loss risk angle; detailed SQLite migration and backup safety belong to the R4 auditor.

---

## 4. Conclusion

The application architecture has clean domain mathematical logic but suffers from **architectural coupling and fragility in state persistence and lifecycle**:
1. **P0**: Silent database reset in `SqliteAppRepository.load()` risking permanent data loss, and destructive error handling via `.requireValue` tearing down the app UI on save errors.
2. **P1**: Deprecated `legacy.dart` Riverpod usage without `mounted` checks, notification alarm churn on every state mutation, hardcoded Moscow timezone, and global rebuild storms across `IndexedStack`.
3. **P2-P3**: Presentation directly instantiating domain services in `Widget.build`, UI models polluting domain entities, and a 3,562-line monolithic presentation file.

---

## 5. Verification Method

- **Automated Static Analysis**:
  ```powershell
  & "F:\Development\flutter\bin\flutter.bat" analyze
  ```
- **Automated Unit & Widget Tests**:
  ```powershell
  & "F:\Development\flutter\bin\flutter.bat" test
  ```
- **File Inspection**:
  - Inspect `F:\Projects\aperture-grafik\.agents\explorer_r1_arch\report.md` for full detailed analysis and drop-in code fixes.
  - Inspect `lib/data/sqlite_app_repository.dart:34-50` to verify silent reset and single-blob storage.
  - Inspect `lib/application/app_controller.dart:4, 16-24, 38, 40-47` to verify Riverpod deprecation and error handling.
  - Inspect `lib/presentation/app_shell.dart:33, 431, 440, 1203` to verify monolithic state passing and direct service instantiation.
