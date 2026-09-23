# R4 Data Safety, Persistence & Serialization Re-Audit Report

## 1. Observation

Direct observations from the target codebase at `F:\Projects\aperture-grafik`:

### 1.1 `lib/data/sqlite_app_repository.dart`
- **Quarantine table initialization**:
  - `onCreate` callback lines 22–24:
    ```dart
    await db.execute(
      'CREATE TABLE IF NOT EXISTS app_state_quarantine (id INTEGER PRIMARY KEY AUTOINCREMENT, payload TEXT NOT NULL, saved_at TEXT NOT NULL, error TEXT)',
    );
    ```
  - In `load()` lines 34–36:
    ```dart
    await db.execute(
      'CREATE TABLE IF NOT EXISTS app_state_quarantine (id INTEGER PRIMARY KEY AUTOINCREMENT, payload TEXT NOT NULL, saved_at TEXT NOT NULL, error TEXT)',
    );
    ```
- **Error handling and quarantine on corrupt payload in `load()`** (lines 44–58):
  ```dart
  44:     try {
  45:       return AppState.fromJson(
  46:         jsonDecode(raw) as Map<String, dynamic>,
  47:       );
  48:     } catch (error) {
  49:       // Quarantine corrupted payload to prevent silent permanent destruction
  50:       try {
  51:         await db.insert('app_state_quarantine', {
  52:           'payload': raw,
  53:           'saved_at': DateTime.now().toIso8601String(),
  54:           'error': error.toString(),
  55:         });
  56:       } catch (_) {}
  57:       return AppState.initial();
  58:     }
  ```
- **Database transaction wrapping in `save()` and `replace()`** (lines 62–74):
  ```dart
  62:   @override
  63:   Future<void> save(AppState state) async {
  64:     final db = await _db;
  65:     final payload = jsonEncode(state.toJson());
  66:     await db.transaction((txn) async {
  67:       await txn.insert('app_state', {
  68:         'id': 1,
  69:         'payload': payload,
  70:       }, conflictAlgorithm: ConflictAlgorithm.replace);
  71:     });
  72:   }
  73: 
  74:   @override
  75:   Future<void> replace(AppState state) => save(state);
  ```

### 1.2 `lib/domain/models.dart`
- **Safe enum deserialization extension `SafeEnumByName`** (lines 15–23):
  ```dart
  15: extension SafeEnumByName<T extends Enum> on Iterable<T> {
  16:   T byNameOr(String? name, T fallback) {
  17:     if (name == null) return fallback;
  18:     for (final value in this) {
  19:       if (value.name == name) return value;
  20:     }
  21:     return fallback;
  22:   }
  23: }
  ```
- **Enum deserialization across all domain models**:
  - `AppSettings.fromJson` (lines 81–95):
    ```dart
    language: AppLanguage.values.byNameOr(
      json['language'] as String?,
      AppLanguage.russian,
    ),
    currency: Currency.rub,
    themeMode: AppThemeMode.values.byNameOr(
      json['themeMode'] as String?,
      AppThemeMode.standard,
    ),
    ```
  - `Schedule.fromJson` (line 136):
    ```dart
    type: ScheduleType.values.byNameOr(json['type'] as String?, ScheduleType.twoTwo),
    ```
  - `Shift.fromJson` (line 323):
    ```dart
    kind: ShiftKind.values.byNameOr(json['kind'] as String?, ShiftKind.scheduled),
    ```
  - `Payout.fromJson` (line 391):
    ```dart
    kind: PayoutKind.values.byNameOr(json['kind'] as String?, PayoutKind.advance),
    ```

### 1.3 `lib/presentation/app_shell.dart`
- **Backup import safeguards and error handling in `_import`** (lines 3500–3554):
  ```dart
  3500:   final picked = await FilePicker.platform.pickFiles(
  3501:     type: FileType.custom,
  3502:     allowedExtensions: const ['json'],
  3503:     withData: true,
  3504:   );
  3505:   if (!context.mounted) return;
  3506:   if (picked == null || picked.files.isEmpty || picked.files.first.bytes == null) return;
  3507:   final bytes = picked.files.first.bytes!;
  ...
  3530:   try {
  3531:     await controller.importBackup(
  3532:       utf8.decode(bytes),
  3533:     );
  3534:     if (context.mounted) {
  3535:       ScaffoldMessenger.of(context).showSnackBar(
  3536:         SnackBar(
  3537:           content: Text(ru ? 'Данные восстановлены.' : 'Data restored.'),
  3538:         ),
  3539:       );
  3540:     }
  3541:   } catch (_) {
  3542:     if (context.mounted) {
  3543:       ScaffoldMessenger.of(context).showSnackBar(
  3544:         SnackBar(
  3545:           content: Text(
  3546:             ru
  3547:                 ? 'Неверный или несовместимый backup.'
  3548:                 : 'Invalid or incompatible backup.',
  3549:           ),
  3550:         ),
  3551:       );
  3552:     }
  3553:   }
  ```

### 1.4 Automated Verification Commands
- `& "F:\Development\flutter\bin\flutter.bat" test`:
  `00:01 +13: All tests passed!` (13/13 tests pass, 100%).
- `& "F:\Development\flutter\bin\flutter.bat" analyze`:
  `No issues found! (ran in 9.4s)` (0 errors, 0 warnings, 0 lints).

---

## 2. Logic Chain

1. **SQLite Quarantine Mechanism**:
   - `CREATE TABLE IF NOT EXISTS app_state_quarantine` is invoked both in `onCreate` (for new installs) and directly inside `load()` (lines 34–36) before querying `app_state`. This guarantees the table exists even on legacy databases initialized under version 1 that did not have the table previously.
   - When `AppState.fromJson(jsonDecode(raw))` fails on a corrupted payload, lines 50–56 insert `payload`, `saved_at`, and `error` into `app_state_quarantine`. The user's corrupted data is preserved and not immediately wiped from disk.
   - However, line 57 evaluates `return AppState.initial()`. Because it does not rethrow or throw a dedicated error, `AppController.initialize()` receives `AppState.initial()` as valid data. The app routes the user to `OnboardingScreen()`. If the user completes onboarding or performs any save, `_save()` overwrites row `id: 1` in `app_state`. While historical data remains in `app_state_quarantine`, the active app silently resets rather than showing `_StartupError` in `main.dart:68, 85-114`.

2. **Atomic Write Consistency**:
   - In `SqliteAppRepository.save()` (lines 62–72), the insert into `app_state` with `ConflictAlgorithm.replace` is executed inside `await db.transaction((txn) async { ... })`. `replace()` delegates directly to `save()`. This ensures all writes to SQLite are wrapped in atomic ACID transactions.

3. **Enum Serialization Safety**:
   - Dart's built-in `EnumByName.byName` throws an unhandled `ArgumentError` if a string does not match any enum constant.
   - The extension `SafeEnumByName` (lines 15–23) defines `byNameOr(String? name, T fallback)` which iterates through `this` and returns `fallback` if `name == null` or no matching name is found.
   - Every domain enum (`AppLanguage`, `AppThemeMode`, `ScheduleType`, `ShiftKind`, `PayoutKind`) uses `.byNameOr(...)` with an explicit sensible default (e.g. `AppLanguage.russian`, `AppThemeMode.standard`, `ScheduleType.twoTwo`, `ShiftKind.scheduled`, `PayoutKind.advance`).
   - `Currency` is explicitly locked to `Currency.rub` with backward-compatible normalization for older backups.
   - As a result, unrecognized enum values in JSON backups or DB rows will safely fall back to defaults without throwing `ArgumentError`.

4. **FilePicker and Import Exception Safety**:
   - In `_import()` (lines 3506–3507), the check `if (picked == null || picked.files.isEmpty || picked.files.first.bytes == null) return;` prevents:
     - Crashes on cancel/dismiss (`picked == null`).
     - Empty result list access.
     - Accessing missing bytes (`bytes == null`).
     - Using `picked.files.first` instead of `picked.files.single` eliminates `StateError` if the OS file picker returns multiple files.
   - Lines 3541–3553 use `catch (_)` instead of catching only `FormatException`. This ensures that any `TypeError`, `ArgumentError`, `StateError`, or unexpected decoding exception is caught, displaying a friendly SnackBar (`Неверный или несовместимый backup.`) without terminating or crashing the Flutter UI.

---

## 3. Caveats

- **Quarantine Error Suppression**: Although the corrupted payload is preserved in `app_state_quarantine`, `load()` suppresses the error and returns `AppState.initial()`. If the intention was to trigger the existing `_StartupError` recovery screen in `main.dart:68`, `load()` should throw (e.g. `throw CorruptedDataException(...)` or `rethrow`) instead of returning `AppState.initial()`.
- **Database Vacuum / Pruning**: The `app_state_quarantine` table does not have an automatic eviction policy or max-row limit. In practice, corruptions are rare one-off events, so storage impact is negligible.

---

## 4. Conclusion

| Component / Finding | Status | Verdict & Assessment |
|---|:---:|---|
| **Quarantine Table Creation** (`sqlite_app_repository.dart:22, 34`) | **PASSED** | Properly declared in `onCreate` and checked dynamically in `load()`. |
| **Payload Quarantining** (`sqlite_app_repository.dart:50-56`) | **PASSED** | Corrupt payload, timestamp, and error string are preserved in `app_state_quarantine`. |
| **Quarantine Error Throwing** (`sqlite_app_repository.dart:57`) | **ATTENTION** | `load()` returns `AppState.initial()` instead of throwing. Corrupt payload is backed up in quarantine, but active state silently resets. |
| **Atomic Transactions** (`sqlite_app_repository.dart:66-71`) | **PASSED** | `save()` and `replace()` wrap write operations in `db.transaction(...)`. |
| **Safe Enum Parsing** (`models.dart:15-23, 82, 89, 136, 323, 391`) | **PASSED** | `SafeEnumByName.byNameOr` implemented and applied across all models; eliminates `ArgumentError` crashes. |
| **FilePicker Safeguards** (`app_shell.dart:3506-3507`) | **PASSED** | Safely checks `picked == null`, `isEmpty`, null bytes, and uses `.first`. |
| **Global Import Exception Catching** (`app_shell.dart:3541`) | **PASSED** | Uses `catch (_)` to intercept all error/exception types (`TypeError`, `ArgumentError`, etc.). |
| **Automated Verification** | **PASSED** | `flutter test` passes 13/13 (100%); `flutter analyze` reports 0 issues. |

---

## 5. Verification Method

To independently reproduce and verify this audit:

1. **Verify Static Analysis**:
   ```powershell
   & "F:\Development\flutter\bin\flutter.bat" analyze
   ```
   *Expected result*: `No issues found! (ran in ~9s)`

2. **Verify Test Suite**:
   ```powershell
   & "F:\Development\flutter\bin\flutter.bat" test
   ```
   *Expected result*: `All tests passed! (13/13)`

3. **Verify Code Locations**:
   - Inspect `F:\Projects\aperture-grafik\lib\data\sqlite_app_repository.dart` lines 34–58 and lines 62–75.
   - Inspect `F:\Projects\aperture-grafik\lib\domain\models.dart` lines 15–23, 82, 89, 136, 323, 391.
   - Inspect `F:\Projects\aperture-grafik\lib\presentation\app_shell.dart` lines 3500–3554.
