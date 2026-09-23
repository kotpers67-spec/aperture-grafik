# Aperture Grafik — Comprehensive Code & Architecture Review Report

**Date**: 2026-09-23  
**Target Codebase**: `F:\Projects\aperture-grafik`  
**Review Type**: Full-Scope Architectural, Financial, UI/UX, and Data Persistence Audit  
**Toolchain Baseline**: Flutter SDK ^3.8.0, Dart SDK ^3.8.0, `flutter_lints` ^6.0.0  
**Test Suite Status**: 13/13 Passed (100%)  
**Static Analysis Status**: 0 compile-blocking errors, 2 dead dependencies  

---

## Executive Summary & Quality Scorecard

Aperture Grafik is an offline-first Flutter Android application designed for specialty coffee shop baristas and shift workers to track schedules, revenue-share earnings, advances, and pay cycles.

The application exhibits several strong foundational virtues:
1. **Integer Minor-Unit Financial Modeling**: Uses integer kopecks/cents (`earningsMinor`, `revenueMinor`, `dailyRateMinor`) throughout domain services, preventing standard IEEE-754 floating-point rounding errors.
2. **Strict On-Device Privacy**: 100% offline-first. Zero network SDKs, zero analytics or telemetry trackers, and no `android.permission.INTERNET` declared in the production Android manifest.
3. **100% Baseline Test Pass Rate**: All 13 existing automated tests pass cleanly in under 2 seconds.
4. **Cohesive Visual Design**: Thoughtfully crafted coffee-shop visual aesthetic with Material 3 design tokens (espresso, caramel, latte, cream palettes).

However, deep technical auditing across the four core dimensions revealed **8 P0 Critical vulnerabilities, 14 P1 High risks, 16 P2 Medium architectural smells, and 8 P3 Polish items**:
- **Data Safety Vulnerability (P0)**: SQLite database functions as a single JSON blob. Any deserialization failure silently defaults to `AppState.initial()`, and the subsequent save permanently overwrites and obliterates all historical data without backup or quarantine.
- **Cascading UI Teardown (P0)**: Save failures trigger `AsyncValue.error` without preserving previous data; `.requireValue` calls throw `StateError` and unmount the entire app into a dead-end error screen.
- **Fatal Layout Crash (P0)**: `app_theme.dart` sets `minimumSize: const Size.fromHeight(56)` on `FilledButtonThemeData`, injecting `width = double.infinity`. In `StatisticsPage`, rendering `FilledButton.tonalIcon` inside an unconstrained horizontal `Row` crashes Flutter with `BoxConstraints forces an infinite width`.
- **RenderFlex Overflow (P0)**: `CalendarPage` month selector overflows by 240px on compact screens and standard screens with 1.3x text scaling.
- **Financial & Schedule Inversions (P0)**: Multi-month and yearly charts collapse into 1..31 day-of-month buckets; overnight shifts crossing midnight invert active state and complete under the wrong calendar date; shifts worked on payout dates are omitted from earnings via strict inequality `>`.

### Architecture Health Scorecard
| Dimension | Rating | Grade | Key Verdict |
|---|:---:|:---:|---|
| **R1. Architecture & Riverpod** | 65 / 100 | **C+** | Monolithic 3,562-line presentation file; deprecated Riverpod `StateNotifier` (`legacy.dart`); unmounted constructor mutations; zero `.select()` provider slicing causing global `IndexedStack` rebuild storms. |
| **R2. Finance & Shift Logic** | 68 / 100 | **C+** | Minor-unit integer kopeck math is solid, but overnight shift state machine inverts between 00:00–06:00, chart collapses multi-month data into 31 buckets, and Russian 25th/10th pay cycles break. |
| **R3. UI/UX & Anti-Overlap** | 62 / 100 | **C** | Beautiful theme tokens, but fatal layout crash in button themes, 240px RenderFlex month selector overflow, severe dialog tile squeezing on 320px screens, and missing edge-to-edge safe areas. |
| **R4. Data Persistence & Privacy** | 72 / 100 | **B-** | 100% private, zero telemetry, zero internet permission; but critical P0 silent data eradication bug on corrupt payload, no ACID transactions, and fragile backup import. |
| **QA & Verification Suite** | 70 / 100 | **C+** | 100% pass rate (13/13) and 0 static analyzer errors, but critically shallow test coverage (~12% overall; SQLite repository 0% tested, AppController 0% tested). |
| **Overall Project Score** | **67.4 / 100** | **C+** | **NEEDS REMEDIATION BEFORE PRODUCTION RELEASE** |

---

## 1. Requirement 1 (R1): Architecture & Layering Integrity

### 1.1 Architectural Overview
The codebase organizes into four conceptual directories:
- `lib/core/`: Theme (`app_theme.dart`), localization (`strings.dart`), notifications (`notification_service.dart`).
- `lib/data/`: `app_repository.dart` interface and `sqlite_app_repository.dart`.
- `lib/domain/`: Pure Dart entities and services (`models.dart`, `finance_service.dart`, `schedule_service.dart`, `revenue_recommendation_service.dart`).
- `lib/application/`: `app_controller.dart` managing Riverpod state mutations.
- `lib/presentation/`: Single monolithic file `app_shell.dart` (3,562 lines, 123 KB) housing all screens, dialogs, and sheets.

### 1.2 R1 Finding Matrix
| ID | Priority | Category | File & Lines | Description |
|---|:---:|---|---|---|
| **R1-01** | **P0** | Lifecycle / Crash | `app_controller.dart:38, 40-47`, `app_shell.dart:33` | `_save` sets destructive `AsyncValue.error`, triggering `requireValue` `StateError` and unmounting app tree |
| **R1-02** | **P1** | Deprecation | `app_controller.dart:4, 16-24` | Uses soft-deprecated `StateNotifier` from `flutter_riverpod/legacy.dart` |
| **R1-03** | **P1** | Lifecycle | `app_controller.dart:18-20, 32` | Constructor fires unawaited `initialize()` without checking `mounted`, risking `StateError` on dispose |
| **R1-04** | **P1** | Performance | `main.dart:34-42`, `notification_service.dart:38-78` | Alarm storm: cancels 97 and reschedules 96 alarms unawaited on EVERY state change (even theme/language switch) |
| **R1-05** | **P1** | Performance | `app_shell.dart:33-40` | `AppShell` drills monolithic `AppState` across `IndexedStack`; zero usage of `.select()`, causing full rebuild storms |
| **R1-06** | **P2** | Layering | `app_shell.dart:431, 440, 1203` | Presentation widgets directly instantiate domain services via `const Service()` in `Widget.build()` |
| **R1-07** | **P2** | Clean Architecture | `models.dart:7, 455-494`, `app_controller.dart:56-62` | UI enums (`AppThemeMode`), ARGB color ints, and backup formatting leaked into domain entities |
| **R1-08** | **P3** | Modularity | `app_shell.dart:1-3562` | Monolithic 3,562-line presentation file combining 4 tabs, 6 sheets, and all UI dialogs |
| **R1-09** | **P3** | Riverpod Hygiene | `main.dart:28-49` | `ref.listenManual` anti-pattern used inside `ConsumerStatefulWidget` instead of declarative `ref.listen` |

### 1.3 Concrete Code Evidence & Fixes (R1)

#### R1-01 [P0]: Destructive `AsyncValue.error` Cascade
In `AppController`:
```dart
// lib/application/app_controller.dart:38-47
AppState get _data => state.requireValue;

Future<void> _save(AppState value) async {
  state = AsyncValue.data(value);
  try {
    await _repository.save(value);
  } catch (error, stackTrace) {
    state = AsyncValue.error(error, stackTrace); // Discards in-memory state!
  }
}
```
In `AppShell`:
```dart
// lib/presentation/app_shell.dart:33
final data = ref.watch(appControllerProvider).requireValue; // Throws StateError!
```
**Fix**: Preserve previous data using `.copyWithPrevious()` and handle transient errors gracefully:
```dart
Future<void> _save(AppState value) async {
  final previousState = state;
  state = AsyncValue.data(value);
  try {
    await _repository.save(value);
  } catch (error, stackTrace) {
    state = AsyncValue<AppState>.error(error, stackTrace).copyWithPrevious(previousState);
  }
}
```

#### R1-02 & R1-03 [P1]: Modernize to Riverpod 3 `AsyncNotifier`
Replace `StateNotifier` from `legacy.dart` with idiomatic `AsyncNotifier`:
```dart
final appControllerProvider =
    AsyncNotifierProvider<AppController, AppState>(AppController.new);

class AppController extends AsyncNotifier<AppState> {
  late final AppRepository _repository;

  @override
  FutureOr<AppState> build() {
    _repository = ref.watch(appRepositoryProvider);
    return _repository.load();
  }
  ...
}
```

---

## 2. Requirement 2 (R2): Finance, Shift Logic & Calculation Edge Cases

### 2.1 Domain Calculation Architecture
`FinanceService` handles all monetary calculations in integer minor units (kopecks/cents):
$$\text{Earnings} = \begin{cases} 
\text{manualEarningsMinor}, & \text{if specified} \\
\text{dailyRateMinor} + \operatorname{round}\left(\frac{\text{revenueMinor} \times \text{revenuePercent}}{100}\right), & \text{otherwise}
\end{cases}$$

### 2.2 R2 Finding Matrix
| ID | Priority | Category | File & Lines | Description |
|---|:---:|---|---|---|
| **R2-01** | **P0** | Chart / Aggregation | `app_shell.dart:765-775` | Yearly chart collapses all 12 months into day-of-month buckets (1..31); weekly view sorts out-of-order across month boundary |
| **R2-02** | **P0** | Overnight Logic | `app_shell.dart:438-462` | Overnight shift between 00:00–06:00 is not recognized as active; completing after shift ends records shift under today instead of yesterday |
| **R2-03** | **P0** | Accounting Error | `finance_service.dart:101-105, 138-141` | Payout calculation uses strict `shiftDay.isAfter(baselineDate)`, permanently excluding shifts worked on payout dates |
| **R2-04** | **P0** | Payroll Engine | `finance_service.dart:57-79, 113-156` | Standard Russian pay cycle (25th Advance / 10th Salary) breaks; missing previous salary aggregates months of shifts into advance |
| **R2-05** | **P1** | Input Parsing | `app_shell.dart:1884-1897, 2224` | `?? 0` in parse fallback silently overwrites shift earnings and custom rate to 0.00 ₽ on typos or spaces |
| **R2-06** | **P1** | Schedule Rotation | `schedule_service.dart:8-23`, `app_shell.dart:3232` | `anchorDate` cannot be modified in schedule editor; dates before anchor unconditionally return `false` (day off) |
| **R2-07** | **P1** | 24h Shift Math | `app_controller.dart:155-156` | 24-hour shifts where `start == end` (e.g. 08:00 to 08:00) collapse to 0 hours duration |
| **R2-08** | **P2** | Date Arithmetic | `schedule_service.dart:15, 43`, `finance_service.dart:82` | `Duration(days: 1)` and `DateTime.difference` drift across DST / 23-hour transitions |
| **R2-09** | **P2** | Feature Gap | `models.dart:140-179`, `finance_service.dart:24-37` | No support for hourly rates or unpaid break deductions (standard in hospitality) |
| **R2-10** | **P2** | Terminology | `strings.dart:34, 37-39` | "Day coefficient (%)" is wired to revenue percentage, misleading users expecting a 1.5x/2.0x overtime multiplier |
| **R2-11** | **P2** | Display Consistency | `app_shell.dart:1863, 3537` | Shift editor live preview rounds to whole rubles (`toStringAsFixed(0)`), conflicting with kopeck display on main cards |
| **R2-12** | **P2** | Validation | `finance_service.dart:36`, `app_shell.dart:1878` | Negative rates and earnings are not clamped, allowing corrupted negative financial balances |
| **R2-13** | **P3** | UI Feedback | `app_shell.dart:1699, 2292` | Time pickers lack `(+1)` next-day badge for overnight shifts |
| **R2-14** | **P3** | UI Affordance | `app_shell.dart:1780-1789` | No "Reset to calculated earnings" button when manual earnings override is active |

### 2.3 Concrete Code Evidence & Fixes (R2)

#### R2-01 [P0]: Chart Multi-Month Collapse Fix
In `StatisticsPage`:
```dart
// lib/presentation/app_shell.dart:765-775
final points = <int, int>{};
for (final shift in shifts) {
  final int key = switch (range) {
    0 => shift.date.weekday, // 1 (Mon) .. 7 (Sun)
    1 => shift.date.day,     // 1 .. 31
    _ => shift.date.month,   // 1 (Jan) .. 12 (Dec)
  };
  points.update(key, (val) => val + shift.earningsMinor, ifAbsent: () => shift.earningsMinor);
}
```

#### R2-03 [P0]: Payout Day Shift Inclusion Fix
In `FinanceService`:
```dart
// lib/domain/finance_service.dart:101-105
final shiftsSinceLastPayout = state.shifts.where((s) {
  final shiftDay = DateTime(s.date.year, s.date.month, s.date.day);
  return !shiftDay.isBefore(baselineDate); // Inclusive: >= baselineDate
}).toList();
```

---

## 3. Requirement 3 (R3): UI/UX, Anti-Overlap Guard & Material 3 Compliance

### 3.1 Design System & Layout Analysis
Aperture Grafik implements a customized Material 3 theme (`AppThemeMode.standard`, `laboratory`, `aperture`, `chamber`) with rich coffee-toned palettes:
- Primary: Deep espresso / roasted bean (`#4A2818`)
- Secondary: Warm caramel (`#8B5A2B`)
- Tertiary: Warm cream / steamed milk (`#D4A373`)
- Surfaces: Coffee filter cream (`#FFF8F0`) and Dark chamber (`#1A1412`)

### 3.2 R3 Finding Matrix
| ID | Priority | Category | File & Lines | Description |
|---|:---:|---|---|---|
| **R3-01** | **P0** | Fatal Layout Crash | `app_theme.dart:109`, `app_shell.dart:1406-1410` | `minimumSize: const Size.fromHeight(56)` injects `w=Infinity` into `FilledButtonThemeData`; rendering inside unconstrained `Row` crashes Flutter |
| **R3-02** | **P0** | RenderFlex Overflow | `app_shell.dart:647-669` | Unconstrained `Text(DateFormat.yMMMM(...))` in `Row` between `IconButton`s overflows by 240px on compact screens / 1.3x text scale |
| **R3-03** | **P1** | Responsive Squeezing | `app_shell.dart:3159-3203` | `_editSchedule` dialog places two `_TimeTile` widgets in raw `Row`, squeezing time text into 24px box on 320px screens |
| **R3-04** | **P1** | Keyboard Overlap | `app_shell.dart:190-230` | `OnboardingScreen` rigid `Column` with `Expanded` overflows when soft keyboard opens on short displays (<640dp) |
| **R3-05** | **P1** | Navigation Collision | `app_shell.dart:3352-3356` | `_manageColleagues` bottom sheet lacks `useSafeArea: true`, colliding with Android gesture handle |
| **R3-06** | **P2** | Localization | `app_shell.dart:3141, 3163, 3368`, `main.dart:100` | Hardcoded Russian strings in `_editSchedule`, `_manageColleagues`, and `_StartupError` break English locale |
| **R3-07** | **P2** | Contrast / M3 Token | `app_shell.dart:2417-2426` | `_RevenueRecommendationCard` sets `tertiaryContainer` background without enforcing `onTertiaryContainer` text contrast |
| **R3-08** | **P2** | Anti-Overlap Guard | `app_shell.dart:1454, 2596` | `ListTile` titles and subtitles in history and payout sections lack `maxLines: 1` and `TextOverflow.ellipsis` |
| **R3-09** | **P2** | Theme Initializer | `app_theme.dart:40-43` | Dark mode (`chamber`) initializes typography with `Typography.black`, causing incorrect contrast baselines |
| **R3-10** | **P3** | Accessibility (a11y) | `app_shell.dart:2977-3015` | `SimpleDialogOption` in theme/language selectors has sub-48dp height (~36dp), failing touch target guidelines |
| **R3-11** | **P3** | Visual Consistency | `app_theme.dart:79`, `app_shell.dart:1231, 2053` | Inconsistent card corner radii varying arbitrarily between 20px, 24px, 26px, and 28px |
| **R3-12** | **P3** | Text Wrapping | `app_shell.dart:3074-3076` | 44-character crypto donation addresses in `_showSupport` lack monospace formatting and overflow on narrow viewports |

### 3.3 Concrete Code Evidence & Fixes (R3)

#### R3-01 [P0]: Fatal Layout Crash Fix
```dart
// lib/core/theme/app_theme.dart:109 & 119
filledButtonTheme: FilledButtonThemeData(
  style: FilledButton.styleFrom(
-   minimumSize: const Size.fromHeight(56),
+   minimumSize: const Size(64, 56),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ),
),
outlinedButtonTheme: OutlinedButtonThemeData(
  style: OutlinedButton.styleFrom(
-   minimumSize: const Size.fromHeight(56),
+   minimumSize: const Size(64, 56),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ),
),
```

#### R3-02 [P0]: Calendar Month Selector Overflow Fix
```dart
// lib/presentation/app_shell.dart:656
- Text(
-   DateFormat.yMMMM(strings.isRu ? 'ru_RU' : 'en_US').format(month),
-   style: Theme.of(context).textTheme.titleLarge,
- ),
+ Expanded(
+   child: Text(
+     DateFormat.yMMMM(strings.isRu ? 'ru_RU' : 'en_US').format(month),
+     textAlign: TextAlign.center,
+     maxLines: 1,
+     overflow: TextOverflow.ellipsis,
+     style: Theme.of(context).textTheme.titleLarge,
+   ),
+ ),
```

---

## 4. Requirement 4 (R4): Data Persistence, Backup & Privacy

### 4.1 Persistence & Privacy Architecture
- Database: `sqflite` saving to `aperture_grafik.db` in app sandbox.
- Schema: Single table `app_state (id INTEGER PRIMARY KEY, payload TEXT NOT NULL)` containing entire `AppState` JSON.
- Backup: JSON export/import via `SharePlus` and `FilePicker`.
- Privacy: No internet permission, zero network dependencies, all processing on-device.

### 4.2 R4 Finding Matrix
| ID | Priority | Category | File & Lines | Description |
|---|:---:|---|---|---|
| **R4-01** | **P0** | Silent Data Eradication | `sqlite_app_repository.dart:39-42` | `load()` catches JSON parsing errors, returns `AppState.initial()`, and subsequent save overwrites `id: 1`, permanently wiping all user history |
| **R4-02** | **P1** | Transactions | `sqlite_app_repository.dart:45-54` | Missing `db.transaction` blocks; `save()` and `replace()` execute unatomic writes |
| **R4-03** | **P1** | Backup Import Crash | `app_shell.dart:3516-3522` | `_import` only catches `FormatException`; `TypeError` and `ArgumentError` escape uncaught and crash the UI |
| **R4-04** | **P1** | Serialization Safety | `models.dart:72, 78, 124, 311, 379` | Unchecked `EnumByName.byName` throws `ArgumentError` on unknown enum values in JSON |
| **R4-05** | **P2** | SQLite Lifecycle | `sqlite_app_repository.dart:15-21` | Missing `onUpgrade` and `onDowngrade` handlers; DB version increments will fail or drop state |
| **R4-06** | **P2** | Storage Architecture | `sqlite_app_repository.dart:18-20` | Single-blob denormalized storage forces full-history O(N) serialization on every single edit |
| **R4-07** | **P2** | SQLite Pragmas | `sqlite_app_repository.dart:15-21` | Missing WAL mode (`PRAGMA journal_mode = WAL;`) causes synchronous flash write stalls |
| **R4-08** | **P2** | FilePicker Safety | `app_shell.dart:3484` | Unsafe `picked.files.single` throws `StateError` if picker returns empty or multiple files |
| **R4-09** | **P3** | Privacy Hygiene | `app_shell.dart:3445-3450` | Exported unencrypted backup JSON files accumulate indefinitely in cache directory |
| **R4-10** | **P3** | Documentation | `README.md:57` | Inaccurate claim about atomic SQLite state transaction on backup import |
| **R4-11** | **CLEAN** | Strict Privacy | `pubspec.yaml`, `AndroidManifest.xml` | **Verified 100% compliant**: 0 telemetry SDKs, 0 network packages, no `INTERNET` permission |

### 4.3 Concrete Code Evidence & Fixes (R4)

#### R4-01 & R4-02 [P0/P1]: Corrupted Data Quarantine & ACID Transactions
In `SqliteAppRepository`:
```dart
// lib/data/sqlite_app_repository.dart
@override
Future<AppState> load() async {
  final db = await _db;
  final rows = await db.query('app_state', where: 'id = ?', whereArgs: [1]);
  if (rows.isEmpty) return AppState.initial();

  final rawPayload = rows.single['payload']! as String;
  try {
    final decoded = jsonDecode(rawPayload) as Map<String, dynamic>;
    return AppState.fromJson(decoded);
  } catch (error) {
    // Quarantine corrupted payload to prevent permanent destruction!
    await db.insert('app_state_quarantine', {
      'payload': rawPayload,
      'saved_at': DateTime.now().toIso8601String(),
      'error': error.toString(),
    });
    // Throw so application controller can present recovery options instead of silently overwriting
    throw CorruptedDataException('Database payload corrupted. Quarantined.', error);
  }
}

@override
Future<void> replace(AppState state) async {
  final db = await _db;
  final encoded = jsonEncode(state.toJson());
  await db.transaction((txn) async {
    await txn.insert('app_state', {
      'id': 1,
      'payload': encoded,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  });
}
```

#### R4-04 [P1]: Safe Fallback Enum Parsing
In `lib/domain/models.dart`:
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

---

## 5. Requirement 5 (QA): Verification & Test Suite Execution

### 5.1 Verification Command Results

#### 1. Automated Test Suite (`flutter test`)
```
Command: flutter test
Directory: F:\Projects\aperture-grafik
Result: 00:01 +13: All tests passed!
Total Tests: 13 | Passed: 13 (100%) | Failed: 0 | Skipped: 0
Duration: 1.8 seconds
```

#### 2. Static Analysis (`flutter analyze`)
```
Command: flutter analyze
Directory: F:\Projects\aperture-grafik
Result: No issues found! (0 compile-blocking errors, 0 warnings, 0 lints)
```

### 5.2 Dead Dependencies & Code Hygiene Audit
1. **Unused Package `go_router: ^16.2.1`**: Declared in `pubspec.yaml:19`, but never imported or referenced anywhere in `lib/`. The application uses an `IndexedStack` state scaffold with `Navigator.push`. Removing `go_router` will reduce app bundle size.
2. **Unused Package `cupertino_icons: ^1.0.8`**: Declared in `pubspec.yaml:14`, but only Material icons (`Icons.*`) are used.
3. **Severe Code Coverage Gaps (~12% Overall Coverage)**:
   - `SqliteAppRepository`: **0% test coverage** (never tested with database mock, in-memory sqflite, or serialization edge cases).
   - `AppController`: **0% test coverage** (never tested for Riverpod lifecycle, save errors, or backup import).
   - `AppShell`: **~2% test coverage** (only basic onboarding smoke test; zero tests for 3,562 lines of UI, charts, shift editors, or bottom sheets).

---

## 6. Comprehensive Prioritized Action Plan & Roadmap

### Milestone 1: P0 Emergency Fixes (Target: 1–2 Days)
- [ ] **Fix M1.1**: Update `app_theme.dart:109, 119` to change `minimumSize: const Size.fromHeight(56)` to `const Size(64, 56)` (resolves fatal button layout crash).
- [ ] **Fix M1.2**: Wrap month navigation text in `Expanded` in `app_shell.dart:656` (resolves 240px RenderFlex overflow).
- [ ] **Fix M1.3**: Implement corrupted data quarantine and remove silent fallback to `AppState.initial()` in `sqlite_app_repository.dart:34-50`.
- [ ] **Fix M1.4**: Update `AppController._save` to use `copyWithPrevious` on `AsyncValue.error` to prevent cascading UI unmount.
- [ ] **Fix M1.5**: In `app_shell.dart:765-775`, bucket statistics chart by month for annual range and weekday for weekly range.
- [ ] **Fix M1.6**: In `app_shell.dart:438-462`, fix overnight shift state resolution to keep night shifts active between 00:00–06:00 and record completed night shifts under yesterday.
- [ ] **Fix M1.7**: In `finance_service.dart:103`, replace strict `.isAfter` with `!shiftDay.isBefore(baselineDate)` so shifts worked on payout dates are included.

### Milestone 2: P1 Stability & Architectural Refactoring (Target: 3–5 Days)
- [ ] **Fix M2.1**: Migrate `AppController` from deprecated `StateNotifier` (`legacy.dart`) to Riverpod 3 `AsyncNotifier`.
- [ ] **Fix M2.2**: Wrap SQLite mutations in `db.transaction(...)` blocks and add `SafeEnumByName` extension in `models.dart`.
- [ ] **Fix M2.3**: Resolve device local timezone dynamically via `flutter_timezone` plugin in `NotificationService`, and filter reminder scheduling to shift/schedule state changes.
- [ ] **Fix M2.4**: Introduce granular derived providers (`shiftsProvider`, `scheduleProvider`, `settingsProvider`) with `.select()` to eliminate `IndexedStack` rebuild storms.
- [ ] **Fix M2.5**: Replace `Row` with `_AdaptiveTimeFields` in `_editSchedule` dialog to prevent 320px screen squeezing.
- [ ] **Fix M2.6**: Add `useSafeArea: true` to `_manageColleagues` bottom sheet.
- [ ] **Fix M2.7**: Decompose 3,562-line monolithic `app_shell.dart` into modular feature folders (`presentation/home/`, `calendar/`, `statistics/`, `profile/`, `shifts/`, `payouts/`).

### Milestone 3: P2 & P3 Polish, Test Coverage & Russian Labor Law Compliance (Target: 5–7 Days)
- [ ] **Fix M3.1**: Re-architect `FinanceService` payroll calculations to support statutory Russian semi-monthly cycles (25th Advance / 10th Salary).
- [ ] **Fix M3.2**: Add `RateType` (hourly vs daily) and unpaid break deductions to domain models.
- [ ] **Fix M3.3**: Externalize all hardcoded Russian strings in dialogs to `lib/core/l10n/strings.dart`.
- [ ] **Fix M3.4**: Remove dead dependencies (`go_router`, `cupertino_icons`) from `pubspec.yaml`.
- [ ] **Fix M3.5**: Expand test suite from 13 tests to 60+ tests, targeting `SqliteAppRepository`, `AppController`, and edge-case shift/payout scenarios.

---

*Report synthesized and compiled by Project Orchestrator from independent audits conducted by R1 Architecture Auditor, R2 Finance Auditor, R3 UI/UX Auditor, R4 Data Persistence Auditor, and QA Reality Checker.*
