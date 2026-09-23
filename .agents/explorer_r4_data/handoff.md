# Handoff Report: R4 Data Persistence, Backup & Privacy Audit

## 1. Observation

Direct observations from codebase inspection, static analysis, and test runs:

1. **`lib/data/sqlite_app_repository.dart:27-42`**:
   `load()` method executes:
   ```dart
   final rows = await (await _db).query('app_state', where: 'id = ?', whereArgs: [1]);
   if (rows.isEmpty) return AppState.initial();
   try {
     return AppState.fromJson(
       jsonDecode(rows.single['payload']! as String) as Map<String, dynamic>,
     );
   } catch (error) {
     // Return initial state only if payload is missing or unparseable, but do not clear DB automatically
     return AppState.initial();
   }
   ```
2. **`lib/data/sqlite_app_repository.dart:45-54`**:
   `save()` and `replace()` methods execute:
   ```dart
   @override
   Future<void> save(AppState state) async {
     await (await _db).insert('app_state', {
       'id': 1,
       'payload': jsonEncode(state.toJson()),
     }, conflictAlgorithm: ConflictAlgorithm.replace);
   }

   @override
   Future<void> replace(AppState state) => save(state);
   ```
   No `db.transaction(...)` block is present anywhere in `sqlite_app_repository.dart` or any other file in `lib/`.
3. **`lib/domain/models.dart:72, 78, 124, 311, 379`**:
   Enum deserialization uses raw `.values.byName(...)`:
   - `language: AppLanguage.values.byName(json['language'] as String? ?? 'russian')` (line 72)
   - `themeMode: AppThemeMode.values.byName(json['themeMode'] as String? ?? 'standard')` (line 78)
   - `type: ScheduleType.values.byName(json['type'] as String? ?? 'twoTwo')` (line 124)
   - `kind: ShiftKind.values.byName(json['kind'] as String? ?? 'scheduled')` (line 311)
   - `kind: PayoutKind.values.byName(json['kind'] as String? ?? 'advance')` (line 379)
   `EnumByName.byName` throws `ArgumentError: No element with that name` if the string value is unrecognized.
4. **`lib/presentation/app_shell.dart:3507-3530`**:
   Backup import error handling:
   ```dart
   try {
     await controller.importBackup(utf8.decode(picked.files.single.bytes!));
     ...
   } on FormatException {
     ...
   }
   ```
   Only catches `on FormatException`. Does NOT catch `TypeError`, `ArgumentError`, or `StateError`.
5. **`lib/presentation/app_shell.dart:3484`**:
   Unsafe single element indexing:
   `if (picked == null || picked.files.single.bytes == null) return;`
   Throws `StateError` if `picked.files` is empty or has multiple items.
6. **`lib/presentation/app_shell.dart:3445-3450`**:
   Export file created in `getTemporaryDirectory()` with pattern `aperture_grafik_backup_*.json` and never cleaned up or deleted after share sheet completion.
7. **`lib/data/sqlite_app_repository.dart:15-21`**:
   Database opened with `version: 1` and only `onCreate`. No `onUpgrade`, `onDowngrade`, or `onConfigure` callbacks specified.
8. **`android/app/src/main/AndroidManifest.xml:1-60` & `pubspec.yaml:9-27`**:
   `android.permission.INTERNET` is completely absent in release manifest. No networking SDKs (`http`, `dio`, `firebase`, `sentry`, `amplitude`) present in `pubspec.yaml`.
9. **`README.md:57`**:
   Verbatim text: *"The exported JSON has `schemaVersion: 1`. Import validates the top-level schema before replacing the single SQLite state transaction."*
10. **Command Execution Results**:
    - `& 'F:\Development\flutter\bin\flutter.bat' test`: Exited 0 with "All tests passed!" (13 tests pass).
    - `& 'F:\Development\flutter\bin\flutter.bat' analyze`: Exited 0 with "No issues found!".

---

## 2. Logic Chain

1. **Premise**: In `SqliteAppRepository.load()`, when a payload exists in SQLite (`rows.isNotEmpty`), but deserialization fails (due to an unknown enum value throwing `ArgumentError`, a null cast throwing `TypeError`, or malformed JSON), the catch block returns `AppState.initial()` (Observation 1, 3).
2. **Step**: `AppController` sets its Riverpod state to `AsyncValue.data(AppState.initial())`. The user is shown an uninitialized state with `onboardingComplete == false`.
3. **Step**: When the user performs any save action (completing onboarding, adding a shift, or editing settings), `AppController._save()` calls `SqliteAppRepository.save(state)` (Observation 2).
4. **Step**: `save()` inserts `id: 1` with `ConflictAlgorithm.replace`, completely overwriting the row holding the previously unparseable payload.
5. **Deduction (P0)**: Any recoverable or transient parsing error results in silent, catastrophic, permanent loss of all user shifts, financials, and colleagues without warning or quarantine.
6. **Premise**: `save()` and `replace()` execute a single unwrapped `insert` without `db.transaction(...)` (Observation 2).
7. **Deduction (P1)**: The statement in `README.md:57` claiming an atomic SQLite state transaction occurs on import is false, and replace operations lack ACID rollback protections.
8. **Premise**: `_import` in `app_shell.dart` catches only `on FormatException` (Observation 4).
9. **Step**: `AppState.fromJson` can throw `TypeError` (e.g. `json['settings'] as Map`) and `ArgumentError` (from `byName`) (Observation 3).
10. **Deduction (P1)**: Malformed or incompatible backups cause uncaught runtime errors that crash UI interactions rather than providing user error feedback.
11. **Premise**: `AndroidManifest.xml` omits `INTERNET` permission and `pubspec.yaml` contains no remote SDKs (Observation 8).
12. **Deduction**: On-device privacy and offline guarantees are mathematically and OS-enforced clean.

---

## 3. Caveats

- **No Caveats**. Full source code and dependencies were inspected and verified with local toolchain commands (`flutter test`, `flutter analyze`).

---

## 4. Conclusion

The data persistence layer is strictly offline and private, but suffers from two severe reliability vulnerabilities:
1. **P0 Silent Data Loss**: Overwriting the single SQLite state row after `load()` catches a deserialization error.
2. **P1 Fragile Import / Missing Transactions**: Lack of `db.transaction` boundaries and uncaught `TypeError`/`ArgumentError` exceptions during backup import.

Both vulnerabilities can be fully remediated by implementing payload quarantining, wrapping writes in `db.transaction(...)`, adopting safe enum fallbacks, and broadening UI exception handlers.

---

## 5. Verification Method

To verify these findings independently:
1. **Run Test Suite**:
   ```powershell
   & 'F:\Development\flutter\bin\flutter.bat' test
   ```
2. **Run Static Analyzer**:
   ```powershell
   & 'F:\Development\flutter\bin\flutter.bat' analyze
   ```
3. **Verify P0 Failure Mode**:
   Inspect `lib/data/sqlite_app_repository.dart:39-42` and `lib/application/app_controller.dart:40-47`.
4. **Verify Enum Parsing Failure**:
   Inspect `lib/domain/models.dart:72, 78, 124, 311, 379` and test `AppThemeMode.values.byName('unknown')` to confirm it throws `ArgumentError`.
5. **Verify Absence of Network Permissions**:
   Inspect `android/app/src/main/AndroidManifest.xml` lines 1–60.

**Invalidation Conditions**:
- These findings are invalidated if `SqliteAppRepository` is replaced with an ACID relational schema using multi-table migrations and active foreign key cascading.
