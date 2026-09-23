# R2 Finance, Shift Logic & Accounting Re-Audit Report

## 1. Observation

### 1.1 Statistics Chart Bucketing (`lib/presentation/app_shell.dart:762-795`)
In `_StatisticsPageState.build` (`lib/presentation/app_shell.dart`):
```dart
762:     final now = DateTime.now();
763:     final from = switch (range) {
764:       0 => now.subtract(const Duration(days: 7)),
765:       1 => DateTime(now.year, now.month, 1),
766:       _ => DateTime(now.year, 1, 1),
767:     };
768:     final shifts = data.shifts
769:         .where(
770:           (item) =>
771:               !item.date.isBefore(DateTime(from.year, from.month, from.day)),
772:         )
773:         .toList();
774:     final revenue = shifts.fold<int>(0, (sum, item) => sum + item.revenueMinor);
775:     final earnings = shifts.fold<int>(
776:       0,
777:       (sum, item) => sum + item.earningsMinor,
778:     );
779:     final points = <int, int>{};
780:     for (final shift in shifts) {
781:       final int key = switch (range) {
782:         0 => shift.date
783:             .difference(DateTime(from.year, from.month, from.day))
784:             .inDays,
785:         1 => shift.date.day,
786:         _ => shift.date.month,
787:       };
788:       points.update(
789:         key,
790:         (value) => value + shift.earningsMinor,
791:         ifAbsent: () => shift.earningsMinor,
792:       );
793:     }
794:     final entries = points.entries.toList()
795:       ..sort((a, b) => a.key.compareTo(b.key));
```

### 1.2 Active Shift & Overnight Shift Resolution (`lib/presentation/app_shell.dart:430-472, 485-499, 511-516`)
In `HomePage.build` (`lib/presentation/app_shell.dart`):
```dart
430:     final strings = Strings(data.settings.language);
431:     final schedule = const ScheduleService();
432:     final now = DateTime.now();
433:     final today = DateTime(now.year, now.month, now.day);
434:     final planned = schedule.isWorkDay(data.schedule, today);
435:     final existing = data.shifts
436:         .where((shift) => _sameDay(shift.date, today))
437:         .firstOrNull;
438:     final starts = schedule.startAt(data.schedule, today);
439:     final ends = schedule.endAt(data.schedule, today);
...
444:     final yesterday = today.subtract(const Duration(days: 1));
445:     final yesterdayShift = data.shifts
446:         .where((shift) => _sameDay(shift.date, yesterday))
447:         .firstOrNull;
448:     final yesterdayStart = schedule.startAt(data.schedule, yesterday);
449:     final yesterdayEnd = schedule.endAt(data.schedule, yesterday);
450:     final isYesterdayOvernightActive =
451:         schedule.isWorkDay(data.schedule, yesterday) &&
452:             yesterdayEnd.day != yesterday.day &&
453:             now.isAfter(yesterdayStart) &&
454:             now.isBefore(yesterdayEnd) &&
455:             yesterdayShift == null;
456:     final active = (planned &&
457:             now.isAfter(starts) &&
458:             now.isBefore(ends) &&
459:             existing == null) ||
460:         isYesterdayOvernightActive;
461:     final pendingDay = planned && now.isAfter(ends) && existing == null
462:         ? today
463:         : (schedule.isWorkDay(data.schedule, yesterday) &&
464:                 yesterdayEnd.day != yesterday.day &&
465:                 now.isAfter(yesterdayEnd) &&
466:                 yesterdayShift == null
467:             ? yesterday
468:             : null);
469:     final completionDate = isYesterdayOvernightActive
470:         ? yesterday
471:         : (planned && existing == null ? today : pendingDay);
```

In `_HeroCard` title resolution (`lib/presentation/app_shell.dart:485-499`):
```dart
485:           _HeroCard(
486:             title: planned
487:                 ? (active
488:                       ? (strings.isRu ? 'Смена идёт' : 'Shift in progress')
489:                       : (strings.isRu ? 'Рабочий день' : 'Work day'))
490:                 : (strings.isRu ? 'Сегодня выходной' : 'Day off'),
491:             subtitle: planned
492:                 ? '${data.schedule.start.format()} – ${data.schedule.end.format()}'
493:                 : (strings.isRu
494:                       ? 'Следующая смена появится в календаре'
495:                       : 'Your next shift is in the calendar'),
496:             icon: planned
497:                 ? Icons.work_history_outlined
498:                 : Icons.weekend_outlined,
499:           ),
```

In `_InlineShiftCompletionForm` dispatch (`lib/presentation/app_shell.dart:511-516`):
```dart
511:           if (completionDate != null)
512:             _InlineShiftCompletionForm(
513:               data: data,
514:               date: completionDate,
515:               kind: ShiftKind.scheduled,
516:             )
```

In `ScheduleService.endAt` (`lib/domain/schedule_service.dart:33-45`):
```dart
33:   DateTime endAt(Schedule schedule, DateTime date) {
34:     final end = DateTime(
35:       date.year,
36:       date.month,
37:       date.day,
38:       schedule.end.hour,
39:       schedule.end.minute,
40:     );
41:     return schedule.end.minutesSinceMidnight <=
42:             schedule.start.minutesSinceMidnight
43:         ? end.add(const Duration(days: 1))
44:         : end;
45:   }
```

In `_InlineShiftCompletionFormState._save` (`lib/presentation/app_shell.dart:2244-2258`):
```dart
2244:   Future<void> _save() async {
2245:     final revenueMinor =
2246:         ((num.tryParse(_revenue.text.replaceAll(',', '.')) ?? 0) * 100).round();
2247:     await ref
2248:         .read(appControllerProvider.notifier)
2249:         .saveShift(
2250:           date: widget.date,
2251:           kind: widget.kind,
2252:           start: _start,
2253:           end: _end,
2254:           colleagueIds: _colleagueIds.toList(),
2255:           revenueMinor: revenueMinor,
2256:           comment: _comment.text,
2257:         );
2258:   }
```

In `AppController.saveShift` (`lib/application/app_controller.dart:154`):
```dart
154:       date: DateTime(date.year, date.month, date.day),
```

### 1.3 Payout Boundary Calculation (`lib/domain/finance_service.dart:101-105, 121-125, 137-141`)
In `FinanceService.calculatePayoutStatus` (`lib/domain/finance_service.dart`):
```dart
90:     final DateTime baselineDate;
91:     if (lastPayout != null) {
92:       baselineDate = DateTime(
93:         lastPayout.date.year,
94:         lastPayout.date.month,
95:         lastPayout.date.day,
96:       );
97:     } else {
98:       baselineDate = DateTime(today.year, today.month, 1).subtract(const Duration(days: 1));
99:     }
100: 
101:     final shiftsSinceLastPayout = state.shifts.where((s) {
102:       final shiftDay = DateTime(s.date.year, s.date.month, s.date.day);
103:       return shiftDay.isAfter(baselineDate);
104:     }).toList();
...
121:       final shiftsInAdvanceCycle = state.shifts.where((s) {
122:         final shiftDay = DateTime(s.date.year, s.date.month, s.date.day);
123:         return shiftDay.isAfter(advanceCycleStart);
124:       }).toList();
...
137:       final shiftsInPeriod = state.shifts.where((s) {
138:         final shiftDay = DateTime(s.date.year, s.date.month, s.date.day);
139:         return shiftDay.isAfter(periodStart);
140:       }).toList();
```

---

## 2. Logic Chain

### 2.1 Statistics Chart Bucketing (Range 0 and Range 2)
1. In `app_shell.dart:781-787`, `range == 0` assigns `key = shift.date.difference(DateTime(from.year, from.month, from.day)).inDays`.
2. Because `from` is `now.subtract(const Duration(days: 7))`, `shift.date.difference(fromDay).inDays` produces a chronological 0-indexed integer offset (0..7).
3. Even when the 7-day span crosses month or year boundaries (e.g. Aug 28 to Sep 3), `shift.date.difference(fromDay).inDays` strictly increases (0, 1, 2, ... 6), preventing calendar day numbers (1..3) from sorting ahead of prior month dates (28..31).
4. `entries` are sorted via `a.key.compareTo(b.key)` (line 795), ensuring strict chronological rendering.
5. In `app_shell.dart:786`, `range == 2` assigns `key = shift.date.month` (1..12).
6. Shifts belonging to the same calendar month aggregate into a single month bucket via `points.update(key, ...)`.
7. This completely resolves the previous bug where shifts from all 12 months were collapsed into 1..31 day-of-month buckets.

### 2.2 Active Shift & Overnight Shift Recognition & Completion
1. For an overnight shift spanning midnight (e.g. 20:00 to 04:00 or 22:00 to 06:00), `ScheduleService.endAt` identifies `end.minutesSinceMidnight <= start.minutesSinceMidnight` and adds `Duration(days: 1)`.
2. When the current time `now` is between midnight 00:00 and 04:00/06:00:
   - `yesterdayEnd.day != yesterday.day` is `true`.
   - `now.isAfter(yesterdayStart)` is `true` (today 02:00 > yesterday 20:00).
   - `now.isBefore(yesterdayEnd)` is `true` (today 02:00 < today 04:00).
   - If yesterday was a work day and `yesterdayShift == null`, `isYesterdayOvernightActive` is `true`.
   - Consequently, `active` evaluates to `true` (line 456-460).
3. Completion date resolution during active overnight hours (line 469):
   - Because `isYesterdayOvernightActive` is `true`, `completionDate` evaluates directly to `yesterday`.
   - `_InlineShiftCompletionForm` receives `date: completionDate` (= `yesterday`).
   - Saving passes `widget.date`, saving the shift under `yesterday` (the starting date of the shift).
4. Completion date resolution after the shift ends (e.g. 05:00 the next morning):
   - If today is a day off (`planned == false`), `pendingDay` evaluates line 463-467: `yesterdayEnd.day != yesterday.day && now.isAfter(yesterdayEnd) && yesterdayShift == null` -> `yesterday`.
   - `completionDate` evaluates to `pendingDay` (= `yesterday`), correctly attributing the completed shift to yesterday.

### 2.3 Payout Date Boundary Logic
1. In `FinanceService.calculatePayoutStatus` (`finance_service.dart:101-105`):
   - When a payout has occurred, `baselineDate = DateTime(lastPayout.date.year, lastPayout.date.month, lastPayout.date.day)`.
   - `shiftsSinceLastPayout` filters with `shiftDay.isAfter(baselineDate)`.
2. For any shift worked on the exact calendar date of the payout (`shiftDay == baselineDate`):
   - `shiftDay.isAfter(baselineDate)` returns `false`.
3. The shift worked on the payout date is therefore completely excluded from `shiftsSinceLastPayout` and `earnedSinceLastPayoutMinor`.
4. Similarly, lines 123 and 139 use `shiftDay.isAfter(advanceCycleStart)` and `shiftDay.isAfter(periodStart)`, excluding shifts worked on the salary payout day from cycle earnings calculations.
5. The proposed fix `!shiftDay.isBefore(baselineDate)` (from `REVIEW_REPORT.md` Fix M1.7) has **not** been applied in `lib/domain/finance_service.dart`.

---

## 3. Caveats

1. **Sub-case 2b Overnight Flaw (Consecutive Workdays)**:
   In `app_shell.dart:469-471`:
   ```dart
   final completionDate = isYesterdayOvernightActive
       ? yesterday
       : (planned && existing == null ? today : pendingDay);
   ```
   If today is ALSO a scheduled workday (`planned == true`):
   Once `now` passes `yesterdayEnd` (e.g. at 04:30 or 08:00 before today's 20:00 night shift), `isYesterdayOvernightActive` is `false`.
   Because `planned && existing == null` is `true`, `completionDate` selects `today` instead of checking `pendingDay` (`yesterday`).
   This causes the inline form to prompt the barista to complete *today's* unstarted shift instead of *yesterday's* unrecorded ended night shift.
2. **`_HeroCard` Title Flaw on Off-Day Morning**:
   In `app_shell.dart:486`:
   ```dart
   title: planned ? (active ? 'Смена идёт' : 'Рабочий день') : 'Сегодня выходной',
   ```
   If yesterday was a workday and today is a day off, between 00:00 and 04:00 `active` is `true`, but `planned` is `false`. The hero card displays "Сегодня выходной" ("Day off") while the shift is actively running.
3. **DST Duration Drift**:
   In `app_shell.dart:782-784`, `shift.date.difference(fromDay).inDays` relies on Dart `Duration.inDays` (integer division by 24h). On 23-hour DST transition days, `difference.inDays` can produce off-by-one key indices. (Non-issue in modern Russia due to permanent standard time, but affects foreign timezones).
4. **Payout Date Inclusive Boundary Precondition**:
   If changing `shiftDay.isAfter(baselineDate)` to `!shiftDay.isBefore(baselineDate)`, line 98 must also be updated:
   Currently line 98 subtracts 1 day (`DateTime(today.year, today.month, 1).subtract(const Duration(days: 1))`). If `!isBefore` were applied without changing line 98, shifts from the last day of the prior month would erroneously be included when `lastPayout == null`.

---

## 4. Conclusion

| Area / Target | Code Location | Status | Verdict |
|---|---|:---:|---|
| **1. Weekly Statistics Bucketing** | `app_shell.dart:781-784` | **VERIFIED** | Chronological day difference `shift.date.difference(fromDay).inDays` cleanly prevents month boundary inversion. |
| **2. Yearly Statistics Bucketing** | `app_shell.dart:786` | **VERIFIED** | Correctly buckets by `shift.date.month` (1..12), eliminating the collapse into 1..31 day-of-month buckets. |
| **3. Overnight Shift Active Detection** | `app_shell.dart:450-460` | **VERIFIED** | `isYesterdayOvernightActive` correctly evaluates `true` between 00:00 and end-of-shift (04:00/06:00). |
| **4. Overnight Completion Date (Active)** | `app_shell.dart:469-470` | **VERIFIED** | Correctly resolves `completionDate = yesterday` while active after midnight. |
| **5. Overnight Completion Date (Ended on Off-day)** | `app_shell.dart:461-471` | **VERIFIED** | Correctly resolves `completionDate = yesterday` via `pendingDay` when today is not a workday. |
| **6. Overnight Completion Date (Ended on Workday)** | `app_shell.dart:471` | **DEFECT (P2)** | If today is also a scheduled workday, line 471 selects `today` before today's shift starts, masking yesterday's pending night shift. |
| **7. HeroCard Title on Night Shift Off-Day** | `app_shell.dart:486` | **DEFECT (P2)** | Checks `planned` before `active`, showing "Сегодня выходной" during active overnight shift between 00:00-04:00. |
| **8. Payout Day Shift Inclusion** | `finance_service.dart:103` | **DEFECT (P0)** | Still uses strict `shiftDay.isAfter(baselineDate)`. Shifts worked on payout dates are strictly omitted. |

---

## 5. Verification Method

### 5.1 Test Suite & Static Analyzer Execution
Execute the test suite and static analyzer to verify zero regressions:
```powershell
& "F:\Development\flutter\bin\flutter.bat" test
& "F:\Development\flutter\bin\flutter.bat" analyze
```
- **Test Results**: 13/13 passed (100%).
- **Analyzer Results**: No issues found (0 errors, 0 warnings, 0 lints).

### 5.2 Independent Verification Code Snippets

#### Verifying Payout Date Shift Exclusion Bug:
```dart
test('shifts on payout date are excluded under current finance_service.dart', () {
  const finance = FinanceService();
  final payoutDate = DateTime(2026, 7, 15);
  final shiftOnPayout = Shift(
    id: 's-15',
    date: DateTime(2026, 7, 15),
    kind: ShiftKind.scheduled,
    actualStart: DateTime(2026, 7, 15, 9),
    actualEnd: DateTime(2026, 7, 15, 21),
    colleagueIds: const [],
    revenueMinor: 1000000,
    earningsMinor: 500000,
    comment: '',
    createdAt: DateTime(2026, 7, 15),
    updatedAt: DateTime(2026, 7, 15),
  );
  final payout = Payout(
    id: 'p-1',
    date: payoutDate,
    kind: PayoutKind.advance,
    amountMinor: 1000000,
    comment: 'Advance',
    createdAt: payoutDate,
    updatedAt: payoutDate,
  );
  final state = AppState.initial().copyWith(
    shifts: [shiftOnPayout],
    payouts: [payout],
  );
  final status = finance.calculatePayoutStatus(state: state, now: DateTime(2026, 7, 20));
  // Under current code, earnedSinceLastPayoutMinor is 0 because shiftDay.isAfter(baselineDate) is false:
  expect(status.earnedSinceLastPayoutMinor, 0); // Demonstrates the exclusion defect!
});
```

#### Invalidation Conditions:
- If `finance_service.dart:103` is modified to `!shiftDay.isBefore(baselineDate)` (and line 98 adjusted), the above exclusion test fails, validating that the bug was fixed.
- If `app_shell.dart:471` is refactored to check `pendingDay` before `(planned && existing == null)`, consecutive overnight shifts will correctly offer yesterday's shift before today's shift starts.
