# Architecture & Riverpod Audit Report: Aperture Grafik (R1)

**Audit Scope**: R1 Architecture & Layering Integrity  
**Target Codebase**: `F:\Projects\aperture-grafik`  
**Auditor**: Teamwork Explorer (Architecture & Riverpod Auditor)  
**Date**: 2026-09-23  
**Analysis Baseline**: `flutter analyze` (0 issues), `flutter test` (13/13 tests passing)

---

## Executive Summary

The Aperture Grafik codebase is a compact, functional offline-first Flutter application tracking shifts, salaries, advances, and revenue. However, a deep architectural and state-management audit reveals **critical architectural anti-patterns, data-loss vulnerabilities, and Riverpod lifecycle flaws**:

1. **P0 Critical Data Loss Risk**: `SqliteAppRepository` treats SQLite as a single-row JSON document store. If JSON deserialization encounters any schema mismatch or corrupted payload, `load()` silently swallows the exception and returns `AppState.initial()`. Any subsequent save immediately overwrites row 1 in SQLite, permanently erasing the user's entire history with zero recovery mechanism.
2. **P0 Critical UI Crash & Cascading Teardown**: When any save operation encounters an I/O or SQLite error, `AppController._save` sets `state = AsyncValue.error(...)` without preserving previous data. Consequently, `state.requireValue` in `AppController` and `ref.watch(appControllerProvider).requireValue` in `AppShell` immediately throw unhandled `StateError`s. Furthermore, `main.dart` tears down the entire application tree to display `_StartupError`, destroying unsaved user work and navigation state.
3. **P1 High Riverpod 3 API Deprecation & Missing Lifecycle Guards**: `AppController` relies on `flutter_riverpod/legacy.dart` (`StateNotifier` / `StateNotifierProvider`), which is soft-deprecated in Riverpod 3. Asynchronous initialization is fired unawaited in the constructor without checking `mounted`, risking `StateError: Bad state: Cannot emit new states after calling dispose`.
4. **P1 High Platform Channel Storm & Hardcoded Timezone**: `ref.listenManual` triggers `NotificationService.scheduleNextEndReminder` on **every single state change** (even theme or language switches), cancelling 97 alarms and scheduling 96 alarms unawaited. The timezone is hardcoded to `'Europe/Moscow'`, breaking notifications for any user in other timezones.
5. **P1 High Rebuild Storm Across IndexedStack**: Zero usage of `.select()` or sliced providers. `AppShell` watches monolithic `appControllerProvider` and drills the entire `AppState` down to all 4 tabs in `IndexedStack`, causing full rebuilds and re-execution of heavy domain math across all pages on every keystroke or update.
6. **P2-P3 Architectural Smells**: Presentation directly instantiates domain services in `Widget.build`; UI theme enums leak into `domain/models.dart`; ARGB color values are hardcoded in application controllers; and the presentation layer is packed into a monolithic 3,562-line file (`app_shell.dart`).

---

## Finding Summary Matrix

| ID | Title | Priority | Category | File & Line Range |
|---|---|---|---|---|
| **P0-1** | Silent Data Reset & Permanent Destruction on DB Deserialization Error | **P0 Critical** | Data Persistence & Safety | `lib/data/sqlite_app_repository.dart:34-50` |
| **P0-2** | Destructive `AsyncValue.error` Cascade & UI Teardown via `.requireValue` | **P0 Critical** | Riverpod Lifecycle & Error Handling | `lib/application/app_controller.dart:38, 40-47`, `lib/presentation/app_shell.dart:33` |
| **P1-1** | Deprecated Riverpod 3 Legacy APIs & Unmounted State Mutations | **P1 High** | Riverpod Lifecycle | `lib/application/app_controller.dart:4, 16-24, 32, 41` |
| **P1-2** | Notification Alarm Saturation & Hardcoded Moscow Timezone | **P1 High** | Architecture & Lifecycle | `lib/main.dart:34-42`, `lib/core/notifications/notification_service.dart:22, 38-78` |
| **P1-3** | Monolithic State Distribution & Global Rebuild Storm Across IndexedStack | **P1 High** | Performance & State Architecture | `lib/presentation/app_shell.dart:33-40` |
| **P2-1** | Direct Domain Service Instantiation & Heavy Math in `Widget.build()` | **P2 Medium** | Clean Architecture & Layering | `lib/presentation/app_shell.dart:431, 440, 570, 1203, 1650` |
| **P2-2** | Layer Pollution: UI Models & Serialization Injected into Domain Entities | **P2 Medium** | Clean Architecture & Separation of Concerns | `lib/domain/models.dart:7, 455-494`, `lib/application/app_controller.dart:56-62` |
| **P2-3** | Pseudo-Database Anti-Pattern: SQLite as Single JSON Blob Bucket | **P2 Medium** | Data Architecture | `lib/data/sqlite_app_repository.dart:18-21, 45-50` |
| **P3-1** | 3,562-Line Monolithic Presentation File (`app_shell.dart`) | **P3 Polish** | Code Organization & Modularity | `lib/presentation/app_shell.dart:1-3562` |
| **P3-2** | `ref.listenManual` Anti-Pattern in `ConsumerState` | **P3 Polish** | Riverpod Best Practices | `lib/main.dart:28-49` |

---

## Detailed Audit Findings

### P0-1: Silent Data Reset & Permanent Destruction on DB Deserialization Error

- **Priority**: P0 Critical
- **Category**: Data Persistence & Safety
- **File**: `lib/data/sqlite_app_repository.dart:34-50`

#### Problem Observation
In `SqliteAppRepository.load()`, if reading from SQLite fails during JSON parsing or model creation, the catch block silently swallows the error and returns a blank `AppState.initial()`:

```dart
// lib/data/sqlite_app_repository.dart:34-42
    try {
      return AppState.fromJson(
        jsonDecode(rows.single['payload']! as String) as Map<String, dynamic>,
      );
    } catch (error) {
      // Return initial state only if payload is missing or unparseable, but do not clear DB automatically
      return AppState.initial();
    }
```

And in `save()`:
```dart
// lib/data/sqlite_app_repository.dart:45-50
  @override
  Future<void> save(AppState state) async {
    await (await _db).insert('app_state', {
      'id': 1,
      'payload': jsonEncode(state.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
```

#### Logic Chain & Impact
1. If the user installs an update where model schemas evolve, or if a single corrupted character enters the database, `AppState.fromJson` throws an exception (e.g. `FormatException('Unsupported backup version.')`).
2. `SqliteAppRepository.load()` swallows the exception and returns `AppState.initial()`.
3. The app starts up displaying the onboarding screen (`onboardingComplete == false`).
4. As soon as the user completes onboarding, modifies a setting, or any auto-save fires, `save(AppState)` is called.
5. SQLite executes `INSERT OR REPLACE INTO app_state VALUES (1, payload)`.
6. **Result**: The entire historical record of shifts, payouts, custom rates, and colleagues is permanently destroyed with no backup file created and no error notification to the user.

#### Recommended Code Fix

```dart
// lib/data/sqlite_app_repository.dart
  @override
  Future<AppState> load() async {
    final db = await _db;
    final rows = await db.query(
      'app_state',
      where: 'id = ?',
      whereArgs: [1],
    );
    if (rows.isEmpty) return AppState.initial();

    final payloadString = rows.single['payload']! as String;
    try {
      final decoded = jsonDecode(payloadString) as Map<String, dynamic>;
      return AppState.fromJson(decoded);
    } catch (error, stackTrace) {
      // Create emergency backup of corrupted payload before any write can occur
      await db.insert('app_state_quarantine', {
        'timestamp': DateTime.now().toIso8601String(),
        'corrupted_payload': payloadString,
        'error_reason': error.toString(),
      });
      // Do NOT silently return initial state if data actually existed!
      // Propagate error to let application controller show recovery dialog
      Error.throwWithStackTrace(
        DataCorruptedException(
          'Failed to deserialize existing database payload. Quarantined for recovery.',
          error,
        ),
        stackTrace,
      );
    }
  }
```

---

### P0-2: Destructive `AsyncValue.error` Cascade & UI Teardown via `.requireValue`

- **Priority**: P0 Critical
- **Category**: Riverpod Lifecycle & Error Handling
- **Files**: `lib/application/app_controller.dart:38, 40-47`, `lib/presentation/app_shell.dart:33`, `lib/main.dart:66-73`

#### Problem Observation
In `AppController`:
```dart
// lib/application/app_controller.dart:38, 40-47
  AppState get _data => state.requireValue;

  Future<void> _save(AppState value) async {
    state = AsyncValue.data(value);
    try {
      await _repository.save(value);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }
```

In `AppShell.build`:
```dart
// lib/presentation/app_shell.dart:33
  @override
  Widget build(BuildContext context) {
    final data = ref.watch(appControllerProvider).requireValue;
```

In `ApertureApp.build`:
```dart
// lib/main.dart:66-73
      home: state.when(
        loading: () => const _Splash(),
        error: (error, _) => _StartupError(error: error),
        data: (loaded) => loaded.settings.onboardingComplete
            ? const AppShell()
            : const OnboardingScreen(),
      ),
```

#### Logic Chain & Impact
1. When any action triggers `_save` (e.g., adding a shift, recording a payout, updating settings), `_save` attempts `_repository.save(value)`.
2. If SQLite throws an error (e.g., storage full, database lock, temporary I/O issue), `state = AsyncValue.error(error, stackTrace)` is executed.
3. This creates a triple failure cascade:
   - **Failure 1**: In `AppController`, `_data` calls `state.requireValue`. Any subsequent method call immediately throws an unhandled `StateError`.
   - **Failure 2**: In `AppShell.build()`, `ref.watch(appControllerProvider).requireValue` throws an unhandled `StateError`.
   - **Failure 3**: In `main.dart`, `state.when(...)` executes `error: (error, _) => _StartupError(...)`. The entire `AppShell` (and all four tabs, modal sheets, and active form inputs) is unmounted and replaced with `_StartupError`.
4. The user is kicked completely out of the app. The only available action is the "Повторить" button, which calls `initialize()` and re-reads the database, completely discarding the in-memory edits the user was working on.

#### Recommended Code Fix

```dart
// lib/application/app_controller.dart
  Future<void> _save(AppState value) async {
    final previousState = state;
    state = AsyncValue.data(value);
    try {
      await _repository.save(value);
    } catch (error, stackTrace) {
      // Preserve current data while attaching error metadata using copyWithPrevious
      state = AsyncValue<AppState>.error(error, stackTrace).copyWithPrevious(previousState);
      // Notify transient UI listener / banner instead of killing app tree
    }
  }
```

And in `AppShell`:
```dart
// lib/presentation/app_shell.dart
  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(appControllerProvider);
    final data = asyncState.valueOrNull;
    if (data == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // Listen for transient save errors and show a SnackBar without rebuilding the tree
    ref.listen(appControllerProvider, (prev, next) {
      if (next.hasError && !prev!.hasError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения данных: ${next.error}')),
        );
      }
    });
...
```

---

### P1-1: Deprecated Riverpod 3 Legacy APIs & Unmounted State Mutations

- **Priority**: P1 High
- **Category**: Riverpod Lifecycle
- **File**: `lib/application/app_controller.dart:4, 16-24, 32, 41`

#### Problem Observation
`AppController` imports and extends `StateNotifier` from `flutter_riverpod/legacy.dart`:

```dart
// lib/application/app_controller.dart:3-4, 16-24
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

final appControllerProvider =
    StateNotifierProvider<AppController, AsyncValue<AppState>>(
      (ref) => AppController(ref.read(appRepositoryProvider)),
    );

class AppController extends StateNotifier<AsyncValue<AppState>> {
  AppController(this._repository) : super(const AsyncValue.loading()) {
    initialize();
  }
```

#### Logic Chain & Impact
1. `StateNotifier` and `StateNotifierProvider` are explicitly deprecated in Riverpod 3 and moved to `legacy.dart`. Future minor or major bumps of Riverpod will remove `legacy.dart`.
2. `AppController` starts an unawaited async call `initialize()` in its constructor.
3. If the controller is disposed before `_repository.load()` finishes (e.g. during widget tests, provider re-scoping, or fast navigation transitions), line 32 (`state = AsyncValue.data(...)`) executes on a disposed `StateNotifier`.
4. In `StateNotifier`, mutating `state` when `mounted == false` immediately throws:
   `StateError: Bad state: Cannot emit new states after calling dispose`.
5. Neither `initialize()` nor `_save()` checks `if (!mounted) return;`.

#### Recommended Code Fix
Migrate `AppController` to Riverpod 3's modern `AsyncNotifier`:

```dart
// lib/application/app_controller.dart (Riverpod 3 Idiomatic AsyncNotifier)
final appControllerProvider =
    AsyncNotifierProvider<AppController, AppState>(AppController.new);

class AppController extends AsyncNotifier<AppState> {
  late final AppRepository _repository;
  final _uuid = const Uuid();
  final _finance = const FinanceService();

  @override
  FutureOr<AppState> build() {
    _repository = ref.watch(appRepositoryProvider);
    return _repository.load();
  }

  Future<void> _save(AppState value) async {
    final previous = state;
    state = AsyncValue.data(value);
    try {
      await _repository.save(value);
    } catch (error, stackTrace) {
      state = AsyncValue<AppState>.error(error, stackTrace).copyWithPrevious(previous);
    }
  }
...
```

---

### P1-2: Notification Alarm Saturation & Hardcoded Moscow Timezone

- **Priority**: P1 High
- **Category**: Architecture & Lifecycle
- **Files**: `lib/main.dart:34-42`, `lib/core/notifications/notification_service.dart:22, 38-78`

#### Problem Observation
In `main.dart`:
```dart
// lib/main.dart:34-42
    _stateSubscription = ref.listenManual(appControllerProvider, (
      previous,
      next,
    ) {
      final data = next.asData?.value;
      if (data != null) {
        unawaited(NotificationService.instance.scheduleNextEndReminder(data));
      }
    }, fireImmediately: true);
```

In `NotificationService`:
```dart
// lib/core/notifications/notification_service.dart:22
    tz.setLocalLocation(tz.getLocation('Europe/Moscow'));

// lib/core/notifications/notification_service.dart:80-88
  Future<void> _cancelShiftReminders() async {
    for (
      var id = _endNotificationId;
      id < _firstRepeatNotificationId + _repeatReminderCount;
      id++
    ) {
      await _plugin.cancel(id);
    }
  }
```

#### Logic Chain & Impact
1. `ref.listenManual` fires `scheduleNextEndReminder` on **every single state change**, including:
   - Toggling theme mode (`AppThemeMode`)
   - Changing app language (`AppLanguage`)
   - Adding or deleting a colleague
   - Recording an advance or salary payout
2. Each run executes `_cancelShiftReminders()` (cancels 97 alarms via platform channels) followed by 96 calls to `_plugin.zonedSchedule()`.
3. Because the call is `unawaited(...)`, if a user rapidly edits items, multiple asynchronous loops run concurrently over the same Android Alarm IDs, causing platform channel saturation, battery consumption, and race conditions.
4. Line 22 hardcodes `tz.getLocation('Europe/Moscow')`. If an employee is located in Ekaterinburg (UTC+5), Novosibirsk (UTC+7), Vladivostok (UTC+10), Almaty (UTC+5), or any other timezone, their shift end notifications will fire hours too early or late.

#### Recommended Code Fix
1. Only trigger reminder rescheduling when relevant shift/schedule fields actually change:
```dart
// In application listener or ref.listen
ref.listen(
  appControllerProvider.select((s) => (
    s.valueOrNull?.schedule,
    s.valueOrNull?.shifts.length,
    s.valueOrNull?.settings.notificationsEnabled,
  )),
  (prev, next) {
    if (next != prev && next.$1 != null) {
      NotificationService.instance.scheduleNextEndReminder(ref.read(appControllerProvider).requireValue);
    }
  },
);
```
2. Detect local device timezone dynamically:
```dart
import 'package:flutter_timezone/flutter_timezone.dart';

Future<void> initialize() async {
  tz.initializeTimeZones();
  final timeZoneName = await FlutterTimezone.getLocalTimezone();
  tz.setLocalLocation(tz.getLocation(timeZoneName));
...
```

---

### P1-3: Monolithic State Distribution & Global Rebuild Storm Across IndexedStack

- **Priority**: P1 High
- **Category**: Performance & State Architecture
- **File**: `lib/presentation/app_shell.dart:33-40`

#### Problem Observation
```dart
// lib/presentation/app_shell.dart:33-40
  @override
  Widget build(BuildContext context) {
    final data = ref.watch(appControllerProvider).requireValue;
    final strings = Strings(data.settings.language);
    final pages = [
      HomePage(data: data),
      CalendarPage(data: data),
      StatisticsPage(data: data),
      ProfilePage(data: data),
    ];
    return Scaffold(
      body: IndexedStack(index: index, children: pages),
...
```

#### Logic Chain & Impact
1. `AppShell` watches the entire `appControllerProvider`.
2. When any field changes anywhere in `AppState`, `AppShell.build()` runs.
3. Because `IndexedStack` maintains the state of all 4 pages simultaneously:
   - `HomePage` rebuilds and re-evaluates all shift status, active shifts, and revenue recommendations.
   - `CalendarPage` rebuilds and regenerates 35-42 day containers, executing `data.shifts.where(...)` for every day.
   - `StatisticsPage` rebuilds and iterates through all shifts, recalculating revenue, earnings, and bar chart groups.
   - `ProfilePage` rebuilds and recalculates payout statuses.
4. There is **zero usage of `select`** anywhere in `app_shell.dart`. Even a minor change in the profile screen causes the background `CalendarPage` and `StatisticsPage` to re-execute heavy list aggregations.

#### Recommended Code Fix
Create granular derived providers so individual widgets only listen to the slice of state they depend on:

```dart
// lib/application/providers.dart
final settingsProvider = Provider<AppSettings>((ref) {
  return ref.watch(appControllerProvider).value?.settings ?? AppState.initial().settings;
});

final scheduleProvider = Provider<Schedule>((ref) {
  return ref.watch(appControllerProvider).value?.schedule ?? AppState.initial().schedule;
});

final shiftsProvider = Provider<List<Shift>>((ref) {
  return ref.watch(appControllerProvider).value?.shifts ?? const [];
});

final payoutsProvider = Provider<List<Payout>>((ref) {
  return ref.watch(appControllerProvider).value?.payouts ?? const [];
});

final colleaguesProvider = Provider<List<Colleague>>((ref) {
  return ref.watch(appControllerProvider).value?.colleagues ?? const [];
});
```

Widgets can then watch only their relevant provider:
```dart
// In CalendarPage:
final shifts = ref.watch(shiftsProvider);
final schedule = ref.watch(scheduleProvider);
```

---

### P2-1: Direct Domain Service Instantiation & Heavy Math in `Widget.build()`

- **Priority**: P2 Medium
- **Category**: Clean Architecture & Layering
- **Files**: `lib/presentation/app_shell.dart:431, 440, 570, 1203, 1576, 1650, 2183`

#### Problem Observation
Domain services are instantiated directly with `const` inside presentation widgets:
```dart
// lib/presentation/app_shell.dart:431
final schedule = const ScheduleService();

// lib/presentation/app_shell.dart:440
final recommendation = const RevenueRecommendationService().recommend(
  shifts: data.shifts,
  targetDate: today,
);

// lib/presentation/app_shell.dart:1203
const finance = FinanceService();
final status = finance.calculatePayoutStatus(
  state: data,
  now: DateTime.now(),
);
```

#### Logic Chain & Impact
1. **Architectural Boundary Breach**: The presentation layer is directly computing complex domain logic (e.g. weighted revenue averages, standard deviation, candidate payout date clamping, shift intervals) instead of consuming prepared view models or selectors from the application layer.
2. **Synchronous UI Blocking**: `RevenueRecommendationService.recommend` executes sorting, list reversals, variance calculations, and `math.sqrt` inside `Widget.build()`. In `StatisticsPage`, filtering and folding over historical shifts occurs on every render frame.
3. **Untestable Widgets**: Widgets cannot be tested with mock or fake domain calculations because the services are hard-instantiated with `const Service()`.

#### Recommended Code Fix
Wrap domain services and their derived calculations in Riverpod providers:

```dart
// lib/application/domain_providers.dart
final financeServiceProvider = Provider<FinanceService>((ref) => const FinanceService());
final scheduleServiceProvider = Provider<ScheduleService>((ref) => const ScheduleService());
final recommendationServiceProvider = Provider<RevenueRecommendationService>((ref) => const RevenueRecommendationService());

final payoutStatusProvider = Provider<PayoutStatus>((ref) {
  final state = ref.watch(appControllerProvider).valueOrNull ?? AppState.initial();
  final finance = ref.watch(financeServiceProvider);
  return finance.calculatePayoutStatus(state: state, now: DateTime.now());
});

final recommendationProvider = Provider.family<RevenueRecommendation?, DateTime>((ref, targetDate) {
  final shifts = ref.watch(shiftsProvider);
  final service = ref.watch(recommendationServiceProvider);
  // Normalize targetDate to avoid microsecond cache misses
  final normalizedDate = DateTime(targetDate.year, targetDate.month, targetDate.day);
  return service.recommend(shifts: shifts, targetDate: normalizedDate);
});
```

---

### P2-2: Layer Pollution: UI Models & Serialization Injected into Domain Entities

- **Priority**: P2 Medium
- **Category**: Clean Architecture & Separation of Concerns
- **Files**: `lib/domain/models.dart:7, 455-494`, `lib/application/app_controller.dart:56-62, 103-109`

#### Problem Observation
1. UI configuration enums are declared inside `lib/domain/models.dart`:
```dart
// lib/domain/models.dart:7
enum AppThemeMode { standard, laboratory, aperture, chamber }
```
2. Hardcoded ARGB color hex integers are maintained in `lib/application/app_controller.dart`:
```dart
// lib/application/app_controller.dart:56-62
    final colors = <int>[
      0xFF2F80ED,
      0xFF9B51E0,
      0xFFF2994A,
      0xFF27AE60,
      0xFFEB5757,
    ];
```
3. Backup JSON serialization, schema versioning, and formatting are embedded directly inside domain entities:
```dart
// lib/domain/models.dart:455-470
  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
...
  String toBackupJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory AppState.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported backup version.');
    }
```

#### Logic Chain & Impact
- In strict Clean Architecture, the **Domain** layer must be independent of external frameworks, UI representations, and data storage formats.
- Having `AppThemeMode` in `domain/` means changing a visual UI theme concept modifies the core domain layer.
- Hardcoding UI color palettes in `AppController` tightly couples application logic to specific hexadecimal color choices that belong in presentation theme tokens.
- Having `toJson`/`fromJson` with backup versioning embedded in `AppState` prevents domain evolution and forces the domain layer to bear the burden of database migration and serialization schema versions.

#### Recommended Code Fix
1. Move `AppThemeMode` to `lib/core/theme/app_theme.dart` or `lib/presentation/theme/`.
2. Move colleague color palette generation to a presentation-layer theme utility (e.g. `ColleagueColorPalette.getColor(int index)`).
3. Introduce Data Transfer Objects (DTOs) or serialization mappers in the `data/` layer:
   `lib/data/dto/app_state_dto.dart` to handle JSON encoding/decoding and schema version migration independently of pure domain entities.

---

### P2-3: Pseudo-Database Anti-Pattern: SQLite as Single JSON Blob Bucket

- **Priority**: P2 Medium
- **Category**: Data Architecture
- **File**: `lib/data/sqlite_app_repository.dart:18-21, 45-50`

#### Problem Observation
```dart
// lib/data/sqlite_app_repository.dart:18-21
        onCreate: (db, _) => db.execute(
          'CREATE TABLE app_state (id INTEGER PRIMARY KEY, payload TEXT NOT NULL)',
        ),
```
The entire database consists of a single table with one row storing a single JSON blob string containing all shifts, payouts, colleagues, and settings.

#### Logic Chain & Impact
1. **Inefficient O(N) I/O**: Every time a user marks a shift or edits a note, the entire historical shift list is serialized into a string and written to SQLite via `INSERT OR REPLACE`. As shift history grows over months and years, the payload string grows linearly, increasing disk write latency, CPU consumption, and flash wear on the mobile device.
2. **No Relational Integrity & Querying**: The application cannot use SQL queries such as:
   `SELECT * FROM shifts WHERE date BETWEEN ? AND ?`.
   All filtering must be done in-memory in Dart after decoding the entire JSON document.
3. **No Incremental Migrations**: Standard SQLite migration mechanisms (`onUpgrade`) cannot be used for individual table columns.

#### Recommended Code Fix
Migrate `SqliteAppRepository` to true relational tables:
- `shifts` (id, date, kind, actual_start, actual_end, revenue_minor, earnings_minor, comment, ...)
- `shift_colleagues` (shift_id, colleague_id)
- `colleagues` (id, name, color_value, created_at, updated_at)
- `payouts` (id, date, kind, amount_minor, comment, ...)
- `settings` (key, value)

Provide relational repository methods:
`Future<List<Shift>> getShiftsInRange(DateTime from, DateTime to)`
`Future<void> saveShift(Shift shift)`
`Future<void> deleteShift(String shiftId)`

---

### P3-1: 3,562-Line Monolithic Presentation File (`app_shell.dart`)

- **Priority**: P3 Polish
- **Category**: Code Organization & Modularity
- **File**: `lib/presentation/app_shell.dart:1-3562`

#### Problem Observation
`app_shell.dart` contains 3,562 lines of code. It contains:
- `AppShell`
- `OnboardingScreen`
- `HomePage`
- `CalendarPage`
- `StatisticsPage`
- `ProfilePage`
- `_PayoutEditor`
- `_ShiftEditor`
- `_InlineShiftCompletionForm`
- `_RevenueRecommendationCard`
- `_HeroCard`, `_MetricCard`, `_SummaryCard`
- Dozens of private modal sheets and helper widgets.

#### Logic Chain & Impact
- Massive file size makes code navigation, code review, and conflict resolution extremely cumbersome.
- High risk of unintended regression during simultaneous edits.
- Violates Single Responsibility Principle and Flutter architectural best practices.

#### Recommended Code Fix
Decompose `lib/presentation/` into modular feature directories:
```
lib/presentation/
├── app_shell.dart            # Only AppShell and navigation scaffold
├── onboarding/               # OnboardingScreen and steps
├── home/                     # HomePage, _HeroCard, _HomeGreeting, _InlineShiftCompletionForm
├── calendar/                 # CalendarPage, _CalendarLegend, month grid
├── statistics/               # StatisticsPage, chart wrappers
├── profile/                  # ProfilePage, settings tiles, theme selector
├── shifts/                   # ShiftEditor bottom sheet
├── payouts/                  # PayoutEditor, _PayoutSummaryCard, _PayoutsSection
└── common/                   # Shared UI cards, avatars, badges
```

---

### P3-2: `ref.listenManual` Anti-Pattern in `ConsumerState`

- **Priority**: P3 Polish
- **Category**: Riverpod Best Practices
- **File**: `lib/main.dart:28-49`

#### Problem Observation
```dart
// lib/main.dart:28-49
class _ApertureAppState extends ConsumerState<ApertureApp> {
  late final ProviderSubscription<AsyncValue<AppState>> _stateSubscription;

  @override
  void initState() {
    super.initState();
    _stateSubscription = ref.listenManual(appControllerProvider, (
      previous,
      next,
    ) {
      final data = next.asData?.value;
      if (data != null) {
        unawaited(NotificationService.instance.scheduleNextEndReminder(data));
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _stateSubscription.close();
    super.dispose();
  }
```

#### Logic Chain & Impact
- In Riverpod, `ref.listenManual` is designed for use outside the widget lifecycle (such as in non-widget services or testing).
- Inside a `ConsumerStatefulWidget`, calling `ref.listen` in `build()` is the declarative, idiomatic approach. It automatically handles subscription disposal and avoids manual `ProviderSubscription` boilerplate.

#### Recommended Code Fix
```dart
// lib/main.dart
  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<AppState>>(appControllerProvider, (previous, next) {
      final data = next.asData?.value;
      if (data != null) {
        unawaited(NotificationService.instance.scheduleNextEndReminder(data));
      }
    });

    final state = ref.watch(appControllerProvider);
...
```

---

## Action Plan & Roadmap for Implementation

### Step 1: Immediate Safety Fixes (P0) — Target: 1 Day
1. Update `SqliteAppRepository.load()` to quarantine corrupted payloads instead of silently returning `AppState.initial()`.
2. Update `AppController._save` to use `copyWithPrevious` on `AsyncValue.error` so in-memory state is never destroyed upon save failure.
3. Replace `.requireValue` in `AppShell` with safe fallback handling and display transient error snackbars.

### Step 2: Modernization & Stability (P1) — Target: 2-3 Days
1. Migrate `AppController` from deprecated `StateNotifier` (`legacy.dart`) to Riverpod 3 `AsyncNotifier`.
2. Add selective provider listeners so `NotificationService` only runs when shifts or schedules mutate.
3. Dynamically resolve device timezone in `NotificationService`.
4. Introduce granular derived providers (`shiftsProvider`, `scheduleProvider`, etc.) to stop `IndexedStack` rebuild storms.

### Step 3: Architecture & Clean Code (P2 & P3) — Target: 3-5 Days
1. Expose domain services via Riverpod providers and eliminate `const Service()` instantiation in presentation.
2. Decouple domain entities from persistence DTOs (`AppStateDto`) and UI themes (`AppThemeMode`).
3. Refactor monolithic `app_shell.dart` into feature-specific presentation sub-packages.
4. Plan migration from single-blob SQLite table to relational tables with incremental schema migrations.

---
*Report prepared by Teamwork Explorer (Architecture & Riverpod Auditor).*
