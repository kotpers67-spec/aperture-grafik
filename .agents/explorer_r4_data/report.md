# R4 Deep Audit Report: Data Persistence, Backup & Privacy

**Project**: Aperture Grafik (Offline-First Android Flutter Application)  
**Target Directory**: `F:\Projects\aperture-grafik`  
**Auditor**: Explorer R4 Data Persistence & Privacy Auditor  
**Date**: 2026-09-23  
**Status**: Complete  

---

## 1. Executive Summary

A comprehensive, full-scope audit of the data persistence, backup/restore mechanisms, and privacy/offline architecture was performed for Aperture Grafik. 

### Key Findings Summary:
1. **Critical Silent Data Loss Flaw (P0)**: In `SqliteAppRepository.load()`, when a stored database row exists but fails to deserialize (due to corrupted JSON, an unrecognized enum from an updated version, or a missing field), the repository silently catches the exception and returns `AppState.initial()`. When the user subsequent performs any state update (e.g. saves a shift or completes onboarding), `SqliteAppRepository.save()` overwrites the single SQLite record (`id: 1`) with `ConflictAlgorithm.replace`, **permanently and irreversibly erasing all user history, shifts, and earnings without backup or quarantine**.
2. **Missing ACID Transaction Blocks & False Documentation Claims (P1)**: The repository does not implement `db.transaction(...)` anywhere in the codebase. Both `save()` and `replace()` execute single unwrapped insert statements. The statement in `README.md:57` claiming *"Import validates the top-level schema before replacing the single SQLite state transaction"* is inaccurate — no transaction wraps the replacement or validates rollback safety.
3. **Fragile Backup Import with Unhandled Runtime Errors (P1)**: `app_shell.dart:3518` catches only `on FormatException`. Any `TypeError` (e.g. `Null is not a subtype of type Map`, invalid field types) or `ArgumentError` (unrecognized enum value thrown by `EnumByName.byName`) during `importBackup()` escapes completely uncaught, crashing the UI flow instead of showing an error feedback SnackBar.
4. **Complete Absence of Schema Migration Infrastructure (P2)**: `openDatabase` in `sqlite_app_repository.dart:15` sets `version: 1` without `onUpgrade`, `onDowngrade`, or `onConfigure` handlers. Upgrading or downgrading SQLite schema will fail or corrupt data. Missing `PRAGMA foreign_keys = ON;` and `PRAGMA journal_mode = WAL;`.
5. **Monolithic Denormalized Blob Store (P2)**: The entire application state is serialized into a single JSON string in a single row (`app_state`). Every minor edit (e.g. changing 1 comment) incurs full-history JSON serialization and full-table write amplification.
6. **Outstanding On-Device Privacy & Strict Offline Guarantees (Verified Clean)**: The application declares **zero** network SDKs, **zero** telemetry/analytics packages, has **no `android.permission.INTERNET`** in `AndroidManifest.xml` (release), and uses strictly private local storage paths (`MODE_PRIVATE`).

---

## 2. Architecture Overview: Persistence & Privacy Layer

The persistence and privacy subsystem consists of:
- **`lib/data/app_repository.dart`**: Interface defining `load()`, `save(state)`, and `replace(state)`.
- **`lib/data/sqlite_app_repository.dart`**: Concrete implementation utilizing `sqflite` with SQLite file `aperture_grafik.db`.
- **`lib/domain/models.dart`**: Domain entities (`AppState`, `AppSettings`, `Schedule`, `PaymentSettings`, `Colleague`, `Shift`, `Payout`) and JSON serializers (`toJson`, `fromJson`, `toBackupJson`).
- **`lib/application/app_controller.dart`**: Riverpod `StateNotifier` orchestrating mutations and backup import/export.
- **`lib/presentation/app_shell.dart`**: UI layer containing `_export` (using `getTemporaryDirectory` + `SharePlus`) and `_import` (using `FilePicker` + `utf8.decode`).
- **`android/app/src/main/AndroidManifest.xml`**: OS-level manifest declaring strictly local permissions (`POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`).

---

## 3. Detailed Audit Findings & Evidence

### 3.1 SQLite Database Transactions & ACID Guarantees

#### Finding 3.1.1 — Complete Absence of ACID Transaction Blocks (`db.transaction`)
- **File**: `lib/data/sqlite_app_repository.dart`
- **Lines**: 45–54
- **Code**:
```dart
45:   @override
46:   Future<void> save(AppState state) async {
47:     await (await _db).insert('app_state', {
48:       'id': 1,
49:       'payload': jsonEncode(state.toJson()),
50:     }, conflictAlgorithm: ConflictAlgorithm.replace);
51:   }
52: 
53:   @override
54:   Future<void> replace(AppState state) => save(state);
```
- **Analysis**:
  - `save()` and `replace()` directly execute `insert` without a `db.transaction(...)` wrapper.
  - When importing a backup in `AppController.importBackup()`:
    ```dart
    final parsed = AppState.fromJson(decoded);
    await _repository.replace(parsed);
    state = AsyncValue.data(parsed);
    ```
    If disk writing fails, power is lost, or the process is killed by Android LMK mid-write, there is no transactional rollback.
  - In `README.md:57`, the documentation states:
    > *"The exported JSON has `schemaVersion: 1`. Import validates the top-level schema before replacing the single SQLite state transaction."*
    This is misleading because no SQLite transaction exists in code.
- **Severity**: **P1 (High)**

---

### 3.2 Schema Migrations, Versioning & Corruption Fallbacks

#### Finding 3.2.1 — Silent Data Eradication Vulnerability on Corrupted/Evolved Payload
- **File**: `lib/data/sqlite_app_repository.dart`
- **Lines**: 27–42
- **Code**:
```dart
27:   @override
28:   Future<AppState> load() async {
29:     final rows = await (await _db).query(
30:       'app_state',
31:       where: 'id = ?',
32:       whereArgs: [1],
33:     );
34:     if (rows.isEmpty) return AppState.initial();
35:     try {
36:       return AppState.fromJson(
37:         jsonDecode(rows.single['payload']! as String) as Map<String, dynamic>,
38:       );
39:     } catch (error) {
40:       // Return initial state only if payload is missing or unparseable, but do not clear DB automatically
41:       return AppState.initial();
42:     }
43:   }
```
- **Analysis**:
  - The author added a comment on line 40: `// Return initial state only if payload is missing or unparseable, but do not clear DB automatically`.
  - While `load()` does not directly call `DELETE`, returning `AppState.initial()` propagates an empty state to `AppController`.
  - `AppController` sets its state to `AppState.initial()` where `onboardingComplete == false`, `shifts == []`, and `colleagues == []`.
  - In `main.dart:69-72`, the UI detects `onboardingComplete == false` and displays `OnboardingScreen()`.
  - As soon as the user completes onboarding or makes any change, `AppController._save()` is triggered, which executes `_repository.save(newState)`.
  - Because `save()` does `insert('app_state', {'id': 1, 'payload': ...}, conflictAlgorithm: ConflictAlgorithm.replace)`, **the previous payload at id: 1 is immediately overwritten and permanently destroyed**.
  - Any minor parsing failure (such as an added enum value in a new release or a corrupted character) triggers total, unrecoverable data loss.
  - Furthermore, `main.dart` contains a `_StartupError` widget (line 85), but it is never reached because `SqliteAppRepository.load()` swallows the exception and pretends the database is freshly initialized.
- **Severity**: **P0 (Critical)**

#### Finding 3.2.2 — Missing Database Migration Lifecycle Handlers (`onUpgrade`, `onDowngrade`, `onConfigure`)
- **File**: `lib/data/sqlite_app_repository.dart`
- **Lines**: 15–21
- **Code**:
```dart
15:       return openDatabase(
16:         path.join(directory, 'aperture_grafik.db'),
17:         version: 1,
18:         onCreate: (db, _) => db.execute(
19:           'CREATE TABLE app_state (id INTEGER PRIMARY KEY, payload TEXT NOT NULL)',
20:         ),
21:       );
```
- **Analysis**:
  - Only `onCreate` is specified.
  - If `version` is incremented to `2` in a future release, sqflite requires an `onUpgrade` callback. Without it, existing users upgrading the app will not have migrations applied.
  - If a user downgrades or rolls back to a previous APK version, sqflite throws `SqfliteDatabaseException(downgrade not supported)`.
  - No `onConfigure` is provided to enable `PRAGMA foreign_keys = ON;`, `PRAGMA journal_mode = WAL;`, and `PRAGMA synchronous = NORMAL;`. Default SQLite rollback journal mode causes synchronous I/O blocks on mobile flash storage on every save.
- **Severity**: **P2 (Medium)**

#### Finding 3.2.3 — Repository Database Connection Error Poisoning
- **File**: `lib/data/sqlite_app_repository.dart`
- **Lines**: 12–24
- **Code**:
```dart
12:   Future<Database> get _db {
13:     _dbFuture ??= () async {
14:       final directory = await getDatabasesPath();
15:       return openDatabase(...);
16:     }();
17:     return _dbFuture!;
18:   }
```
- **Analysis**:
  - If `openDatabase` throws an asynchronous error (e.g. disk locked, temporary permission issue), `_dbFuture` caches the failed Future.
  - Subsequent calls to `_db` will perpetually rethrow the same cached error. If the user taps "Повторить" (Retry) on `_StartupError` (`AppController.initialize()`), it can never recover without killing the app process.
- **Severity**: **P2 (Medium)**

---

### 3.3 Backup Import/Export Integrity & JSON Serialization

#### Finding 3.3.1 — Fragile Enum Deserialization Crashing on Future/Unknown Values
- **File**: `lib/domain/models.dart`
- **Lines**: 72, 78, 124, 311, 379
- **Code**:
```dart
72:  language: AppLanguage.values.byName(json['language'] as String? ?? 'russian'),
78:  themeMode: AppThemeMode.values.byName(json['themeMode'] as String? ?? 'standard'),
124: type: ScheduleType.values.byName(json['type'] as String? ?? 'twoTwo'),
311: kind: ShiftKind.values.byName(json['kind'] as String? ?? 'scheduled'),
379: kind: PayoutKind.values.byName(json['kind'] as String? ?? 'advance'),
```
- **Analysis**:
  - `EnumByName.byName(name)` throws an `ArgumentError: No element with name` when `name` does not match an existing enum identifier.
  - If an exported backup contains an enum from a newer version (e.g. a new theme or schedule type) or a localized/modified string, deserialization throws `ArgumentError`.
  - In `SqliteAppRepository.load()`, this triggers P0 data loss.
  - In `_import()`, this causes an uncaught crash because `_import` only catches `FormatException`.
- **Severity**: **P1 (High)**

#### Finding 3.3.2 — Uncaught Exceptions in UI Backup Import (`_import`)
- **File**: `lib/presentation/app_shell.dart`
- **Lines**: 3507–3530
- **Code**:
```dart
3507:   try {
3508:     await controller.importBackup(
3509:       utf8.decode(picked.files.single.bytes!),
3510:     );
3511:     if (context.mounted) {
3512:       ScaffoldMessenger.of(context).showSnackBar(
3513:         SnackBar(content: Text(ru ? 'Данные восстановлены.' : 'Data restored.')),
3514:       );
3515:     }
3516:   } on FormatException {
3517:     if (context.mounted) {
3518:       ScaffoldMessenger.of(context).showSnackBar(
3519:         SnackBar(content: Text(ru ? 'Неверный или несовместимый backup.' : 'Invalid or incompatible backup.')),
3520:       );
3521:     }
3522:   }
```
- **Analysis**:
  - `_import` specifies `on FormatException`.
  - In Dart, type mismatch errors (e.g. `json['settings'] as Map` when null, `json['revenueMinor'] as num` when string) throw `TypeError`.
  - Unrecognized enums throw `ArgumentError`.
  - Both `TypeError` and `ArgumentError` inherit from `Error`, NOT `Exception` or `FormatException`.
  - When importing a corrupted, hand-edited, or structurally malformed JSON file, the error escapes uncaught, terminating the widget execution and showing no error SnackBar to the user.
- **Severity**: **P1 (High)**

#### Finding 3.3.3 — Unsafe `picked.files.single` Invocation in FilePicker
- **File**: `lib/presentation/app_shell.dart`
- **Line**: 3484
- **Code**:
```dart
3484:   if (picked == null || picked.files.single.bytes == null) return;
```
- **Analysis**:
  - If the platform file picker returns an empty list (`picked.files.isEmpty`) or multiple items, `picked.files.single` throws `StateError: Bad state: No element`.
  - This error is completely unhandled.
- **Severity**: **P2 (Medium)**

#### Finding 3.3.4 — Accumulation of Unencrypted Backup Dumps in Cache
- **File**: `lib/presentation/app_shell.dart`
- **Lines**: 3445–3457
- **Code**:
```dart
3445:     final directory = await getTemporaryDirectory();
3446:     final file = File(
3447:       '${directory.path}${Platform.pathSeparator}aperture_grafik_backup_${DateTime.now().toIso8601String().replaceAll(':', '-')}.json',
3448:     );
3449:     await file.writeAsString(controller.exportBackup());
3450:     await SharePlus.instance.share(
3451:       ShareParams(
3452:         files: [XFile(file.path)],
3453:         text: ru ? '...' : '...',
3454:       ),
3455:     );
```
- **Analysis**:
  - Every backup export generates a new file in `getTemporaryDirectory()`.
  - The file is never deleted after the share sheet completes or fails.
  - Over time, numerous plaintext backups containing full user financial data, comments, and names linger in cache storage.
- **Severity**: **P3 (Polish / Hygiene)**

---

### 3.4 On-Device Privacy & Offline-First Guarantees

#### Finding 3.4.1 — Verified Strict Zero-Telemetry and Network Isolation
- **Evidence**:
  1. `pubspec.yaml` contains **no network or telemetry packages** (no `http`, `dio`, `firebase_*`, `sentry`, `amplitude`, `posthog`, `google_mobile_ads`).
  2. `android/app/src/main/AndroidManifest.xml` does **not** declare `android.permission.INTERNET`. The OS kernel prohibits the application process from opening sockets or transmitting packets off-device.
  3. All data persistence resides in `getDatabasesPath()` (`/data/user/0/com.example.aperture_grafik/databases/`), which is sandboxed in private internal flash storage.
  4. Scheduled notifications (`NotificationService`) run exclusively via on-device exact alarm scheduling (`AlarmManager`) without remote push infrastructure.
- **Verdict**: **100% Compliant with Strict Privacy and Offline-First Standard**.

---

## 4. Prioritized Issues Matrix

| ID | Priority | Category | File & Lines | Description | Impact |
|:---|:---:|:---|:---|:---|:---|
| **R4-01** | **P0** | Persistence / Safety | `lib/data/sqlite_app_repository.dart:39-42` | Silent DB clobber on corrupted payload load | Overwrites and permanently erases all user data on next save |
| **R4-02** | **P1** | Transactions | `lib/data/sqlite_app_repository.dart:45-54` | Missing `db.transaction` for state replacement | No atomicity or rollback during backup import or write failure |
| **R4-03** | **P1** | Backup Import | `lib/presentation/app_shell.dart:3516-3522` | `_import` only catches `FormatException` | Unhandled `TypeError`/`ArgumentError` crash during malformed JSON import |
| **R4-04** | **P1** | Serialization | `lib/domain/models.dart:72,78,124,311,379` | Unchecked `EnumByName.byName` throws `ArgumentError` | Deserialization crashes on unknown enum values |
| **R4-05** | **P2** | Migrations | `lib/data/sqlite_app_repository.dart:15-21` | Missing `onUpgrade` and `onDowngrade` handlers | DB version upgrades/downgrades fail or drop state |
| **R4-06** | **P2** | Architecture | `lib/data/sqlite_app_repository.dart:18-20` | Monolithic denormalized single-row JSON store | Full-table rewrite and memory pressure on every single mutation |
| **R4-07** | **P2** | SQLite Pragma | `lib/data/sqlite_app_repository.dart:15-21` | Missing `PRAGMA journal_mode = WAL;` & foreign keys | Synchronous flash storage latency and no FK enforcement |
| **R4-08** | **P2** | UI Safety | `lib/presentation/app_shell.dart:3484` | Unsafe `picked.files.single` access | `StateError` if picker returns empty file list |
| **R4-09** | **P3** | Privacy Hygiene | `lib/presentation/app_shell.dart:3445-3450` | Lingering exported backup JSON files in cache | Plaintext financial dumps accumulate in temporary directory |
| **R4-10** | **P3** | Documentation | `README.md:57` | Inaccurate claim about SQLite state transaction | Docs claim transaction verification that does not exist in code |

---

## 5. Concrete Remediation Proposals & Code Fixes

### 5.1 Fix for P0 & P1 (Transactions, Quarantine & Corrupted Data Recovery)

#### Proposed Update: `lib/data/sqlite_app_repository.dart`
```dart
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import '../domain/models.dart';
import 'app_repository.dart';

class CorruptedDataException implements Exception {
  final Object cause;
  final String rawPayload;
  const CorruptedDataException(this.cause, this.rawPayload);

  @override
  String toString() => 'CorruptedDataException: $cause';
}

class SqliteAppRepository implements AppRepository {
  Future<Database>? _dbFuture;

  Future<Database> get _db {
    _dbFuture ??= () async {
      try {
        final directory = await getDatabasesPath();
        return await openDatabase(
          path.join(directory, 'aperture_grafik.db'),
          version: 1,
          onConfigure: (db) async {
            await db.execute('PRAGMA foreign_keys = ON;');
            await db.execute('PRAGMA journal_mode = WAL;');
            await db.execute('PRAGMA synchronous = NORMAL;');
          },
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE app_state (id INTEGER PRIMARY KEY, payload TEXT NOT NULL);',
            );
            await db.execute(
              'CREATE TABLE app_state_quarantine (id INTEGER PRIMARY KEY AUTOINCREMENT, payload TEXT NOT NULL, saved_at TEXT NOT NULL, error TEXT NOT NULL);',
            );
          },
          onUpgrade: (db, oldVersion, newVersion) async {
            // Migration handlers for future versions
          },
          onDowngrade: onDatabaseDowngradeDelete,
        );
      } catch (e) {
        _dbFuture = null; // Prevent error poisoning
        rethrow;
      }
    }();
    return _dbFuture!;
  }

  @override
  Future<AppState> load() async {
    final db = await _db;
    final rows = await db.query(
      'app_state',
      where: 'id = ?',
      whereArgs: [1],
    );
    if (rows.isEmpty) return AppState.initial();

    final rawPayload = rows.single['payload']! as String;
    try {
      final decoded = jsonDecode(rawPayload);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Payload is not a valid JSON map');
      }
      return AppState.fromJson(decoded);
    } catch (error) {
      // Quarantine corrupted payload to prevent silent permanent loss
      await db.insert('app_state_quarantine', {
        'payload': rawPayload,
        'saved_at': DateTime.now().toIso8601String(),
        'error': error.toString(),
      });
      // Throw explicitly so AppController & UI can alert the user instead of silently overwriting
      throw CorruptedDataException(error, rawPayload);
    }
  }

  @override
  Future<void> save(AppState state) async {
    final db = await _db;
    final encoded = jsonEncode(state.toJson());
    await db.transaction((txn) async {
      await txn.insert('app_state', {
        'id': 1,
        'payload': encoded,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  @override
  Future<void> replace(AppState state) async {
    final db = await _db;
    final encoded = jsonEncode(state.toJson());
    await db.transaction((txn) async {
      // Archive current state into quarantine as backup before replacing
      final existing = await txn.query('app_state', where: 'id = ?', whereArgs: [1]);
      if (existing.isNotEmpty) {
        await txn.insert('app_state_quarantine', {
          'payload': existing.single['payload'] as String,
          'saved_at': DateTime.now().toIso8601String(),
          'error': 'PRE_REPLACE_BACKUP',
        });
      }
      await txn.insert('app_state', {
        'id': 1,
        'payload': encoded,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }
}
```

---

### 5.2 Fix for P1 (Resilient Enum Deserialization & Missing Field Defaults)

#### Proposed Helper Extension in `lib/domain/models.dart`:
```dart
extension SafeEnumByName<T extends Enum> on Iterable<T> {
  T byNameOr(String? name, T fallback) {
    if (name == null) return fallback;
    for (final value in this) {
      if (value.name == name) return value;
    }
    return fallback;
  }
}
```

#### Update `models.dart` deserializers:
```dart
// AppSettings.fromJson
language: AppLanguage.values.byNameOr(json['language'] as String?, AppLanguage.russian),
themeMode: AppThemeMode.values.byNameOr(json['themeMode'] as String?, AppThemeMode.standard),

// Schedule.fromJson
type: ScheduleType.values.byNameOr(json['type'] as String?, ScheduleType.twoTwo),

// Shift.fromJson
kind: ShiftKind.values.byNameOr(json['kind'] as String?, ShiftKind.scheduled),

// Payout.fromJson
kind: PayoutKind.values.byNameOr(json['kind'] as String?, PayoutKind.advance),
```

---

### 5.3 Fix for P1 & P2 in Backup Import & Export UI (`app_shell.dart`)

#### Proposed Update in `lib/presentation/app_shell.dart`:
```dart
Future<void> _import(
  BuildContext context,
  AppController controller,
  bool ru,
) async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['json'],
    withData: true,
  );
  if (!context.mounted) return;
  if (picked == null || picked.files.isEmpty) return;
  final file = picked.files.first;
  if (file.bytes == null) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(ru ? 'Заменить данные?' : 'Replace data?'),
      content: Text(
        ru
            ? 'Текущие локальные данные будут заменены содержимым backup.'
            : 'Current local data will be replaced by this backup.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(ru ? 'Отмена' : 'Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(ru ? 'Импортировать' : 'Import'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  try {
    final jsonString = utf8.decode(file.bytes!);
    await controller.importBackup(jsonString);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ru ? 'Данные восстановлены.' : 'Data restored.'),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ru
                ? 'Неверный или несовместимый backup: $e'
                : 'Invalid or incompatible backup: $e',
          ),
        ),
      );
    }
  }
}
```

#### Proposed Temporary File Cleanup in `_export`:
```dart
  try {
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}aperture_grafik_backup_${DateTime.now().toIso8601String().replaceAll(':', '-')}.json',
    );
    await file.writeAsString(controller.exportBackup());
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: ru
            ? 'Резервная копия Aperture Grafik. Файл не зашифрован.'
            : 'Aperture Grafik backup. This file is unencrypted.',
      ),
    );
  } finally {
    // Schedule asynchronous cleanup of exported backups older than 1 hour
    unawaited(_cleanupOldBackups());
  }
```

---

## 6. Verification and Invalidation Conditions

### Verification Method:
1. **Automated Testing Suite**:
   Run full test suite via Flutter toolchain:
   ```powershell
   & 'F:\Development\flutter\bin\flutter.bat' test
   ```
2. **Static Analysis**:
   Verify 0 lints and analyzer warnings:
   ```powershell
   & 'F:\Development\flutter\bin\flutter.bat' analyze
   ```
3. **P0 Data Loss Reproduction Test Case**:
   - Insert an invalid JSON payload into `app_state` (e.g. `{"schemaVersion": 1, "themeMode": "non_existent_theme"}`).
   - Launch app or call `SqliteAppRepository.load()`.
   - Observe whether `load()` silently returns `AppState.initial()` and whether subsequent save destroys the database.
4. **Backup Import Robustness Test**:
   - Create a test JSON backup with missing fields and unrecognized enum strings.
   - Run `controller.importBackup(jsonString)` and verify proper exception handling without uncaught runtime crashes.

### Invalidation Conditions:
- The findings in this report would be invalidated if the project moves away from sqflite to Hive/Isar/ObjectBox, or if `SqliteAppRepository` is refactored into normalized multi-table relational schema with active foreign key cascade triggers and migration scripts.
