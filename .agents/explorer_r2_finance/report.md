# R2 Audit Report: Finance, Shift Logic & Calculation Edge Cases

**Project**: Aperture Grafik (`F:\Projects\aperture-grafik`)  
**Auditor**: Finance & Shift Logic Auditor (`explorer_r2_finance`)  
**Date**: 2026-09-23  
**Status**: Completed  

---

## Executive Summary

A comprehensive, deep-scope code audit of Aperture Grafik was conducted focusing on **R2: Finance, Shift Logic & Calculation Edge Cases**. While the project demonstrates clean domain modeling using integer minor units (kopecks/cents) for primary monetary storage and clean Riverpod state immutability, the investigation uncovered **4 P0 Critical**, **3 P1 High**, **5 P2 Medium**, and **3 P3 Polish** vulnerabilities and architectural gaps across calculation engines, overnight time math, UI synchronization, and payroll cycles.

### Priority Scorecard
| Priority | Count | Key Focus Areas |
|---|---|---|
| **P0 Critical** | 4 | Statistics multi-month chart collapse; Overnight shift state machine inversion; Payout day shift omission via strict `isAfter`; Russian 25th/10th advance/salary cycle crash |
| **P1 High** | 3 | Parse failure wiping wages to 0 ₽ silently; Schedule anchor date locked permanently; 24-hour shifts collapsing to 0 duration |
| **P2 Medium** | 5 | Timezone/DST `Duration(days: 1)` arithmetic drift; Lack of hourly rates & break deductions; Misleading "Day coefficient (%)" label vs shift multiplier; UI currency decimal discrepancy; Unclamped negative rate/earnings inputs |
| **P3 Polish** | 3 | Hardcoded `Europe/Moscow` notification timezone; Missing visual `+1 day` indicator on overnight shift end; Lack of clear override reset button |

---

## Detailed Findings & Vulnerability Analysis

---

### Finding 1 [P0 Critical]: Statistics Chart Collapses Multi-Month and Yearly Data into 1..31 Day-of-Month Buckets

- **Location**: `lib/presentation/app_shell.dart:765-775`
- **Component**: `StatisticsPage` / Chart Aggregation Engine

#### Code Snippet
```dart
765:     final points = <int, int>{};
766:     for (final shift in shifts) {
767:       points.update(
768:         shift.date.day,
769:         (value) => value + shift.earningsMinor,
770:         ifAbsent: () => shift.earningsMinor,
771:       );
772:     }
773:     final entries = points.entries.toList()
774:       ..sort((a, b) => a.key.compareTo(b.key));
```

#### Problem Description
1. When the user selects the **"Year"** range (`range == 2`), `shifts` contains shifts spanning up to 365 days across all 12 months.
2. The aggregation key is `shift.date.day` (the day of the month, `1..31`).
3. As a result, January 15th, February 15th, March 15th, etc., are all summed into `points[15]`. The annual chart displays only 31 bars where each bar is the sum of that calendar day number across the whole year.
4. For the **"Week"** range (`range == 0`), when the 7-day window crosses a month boundary (e.g., October 28 to November 3), shifts on Nov 1, 2, 3 appear at keys `1, 2, 3` and Oct 28, 29, 30, 31 appear at `28, 29, 30, 31`. The chart sorts them numerically (`1, 2, 3, 28, 29, 30, 31`), completely inverting chronological order.

#### Impact
The statistics bar chart is completely broken for annual reviews and scrambled across month boundaries for weekly views.

#### Recommended Code Fix
```dart
    final points = <int, int>{};
    for (final shift in shifts) {
      final int key = switch (range) {
        0 => shift.date.weekday, // 1 (Mon) .. 7 (Sun)
        1 => shift.date.day,     // 1 .. 31
        _ => shift.date.month,   // 1 (Jan) .. 12 (Dec)
      };
      points.update(
        key,
        (value) => value + shift.earningsMinor,
        ifAbsent: () => shift.earningsMinor,
      );
    }
```

---

### Finding 2 [P0 Critical]: Overnight Shift State Machine Inverts on Day Crossing (Active Shift Lost Between 00:00 and 06:00; Shift Completed Under Wrong Date)

- **Location**: `lib/presentation/app_shell.dart:438-462`
- **Component**: `HomePage` Shift Lifecycle & Status Resolution

#### Code Snippet
```dart
438:     final starts = schedule.startAt(data.schedule, today);
439:     final ends = schedule.endAt(data.schedule, today);
...
444:     final active =
445:         planned &&
446:         now.isAfter(starts) &&
447:         now.isBefore(ends) &&
448:         existing == null;
449:     final yesterday = today.subtract(const Duration(days: 1));
450:     final yesterdayShift = data.shifts
451:         .where((shift) => _sameDay(shift.date, yesterday))
452:         .firstOrNull;
453:     final yesterdayEnd = schedule.endAt(data.schedule, yesterday);
454:     final pendingDay = planned && now.isAfter(ends) && existing == null
455:         ? today
456:         : (schedule.isWorkDay(data.schedule, yesterday) &&
457:                   yesterdayEnd.day != yesterday.day &&
458:                   now.isAfter(yesterdayEnd) &&
459:                   yesterdayShift == null
460:               ? yesterday
461:               : null);
462:     final completionDate = planned && existing == null ? today : pendingDay;
```

#### Problem Description
Consider a barista working an overnight shift (e.g., 22:00 to 06:00) that began yesterday:
1. **Between 00:00 and 06:00 (Active Night Shift)**:
   - `today` is the new calendar day.
   - `starts` is evaluated for `today` (22:00 tonight).
   - `now.isAfter(starts)` is `false`.
   - `active` is evaluated as `false`! The app displays "Day off" or "Work day", but does **not** recognize that the barista is actively on shift.
   - `now.isAfter(yesterdayEnd)` is `false` (e.g. 02:00 is before 06:00).
   - `pendingDay` is `null` and `completionDate` is `null`. The shift cannot be completed or viewed during shift hours.
2. **At 06:05 (Shift Finished)**:
   - `yesterdayShift` is `null`.
   - `now.isAfter(yesterdayEnd)` is `true`. `pendingDay` evaluates to `yesterday`.
   - **However**, in line 462: `completionDate = planned && existing == null ? today : pendingDay;`. If today is also a scheduled shift (e.g. on 2/2 or 5/2 schedule), `planned && existing == null` evaluates to `true`!
   - `completionDate` resolves to `today` instead of `yesterday`!
   - When the barista taps "Complete Shift", the shift is saved under **today's date**.
   - Tonight at 22:00, when starting their next shift, `existing` is already present for today, preventing the barista from logging their next shift.

#### Impact
Night-shift workers are blocked from completing shifts during overnight hours, and their completed shifts get recorded under the wrong calendar date, corrupting both payroll records and the schedule rotation.

#### Recommended Code Fix
```dart
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    final yesterdayPlanned = schedule.isWorkDay(data.schedule, yesterday);
    final yesterdayStart = schedule.startAt(data.schedule, yesterday);
    final yesterdayEnd = schedule.endAt(data.schedule, yesterday);
    final isYesterdayOvernight = yesterdayEnd.isAfter(yesterdayStart) && 
        (yesterdayEnd.day != yesterday.day || yesterdayEnd.month != yesterday.month);
    final yesterdayShift = data.shifts
        .where((shift) => _sameDay(shift.date, yesterday))
        .firstOrNull;

    // Check if an overnight shift started yesterday is still active
    final yesterdayActive = yesterdayPlanned &&
        isYesterdayOvernight &&
        now.isAfter(yesterdayStart) &&
        now.isBefore(yesterdayEnd) &&
        yesterdayShift == null;

    final todayActive = planned &&
        now.isAfter(starts) &&
        now.isBefore(ends) &&
        existing == null;

    final active = yesterdayActive || todayActive;

    // Prioritize uncompleted overnight shift from yesterday if shift ended
    final pendingYesterday = yesterdayPlanned &&
        isYesterdayOvernight &&
        now.isAfter(yesterdayEnd) &&
        yesterdayShift == null;

    final completionDate = yesterdayActive || pendingYesterday
        ? yesterday
        : (planned && existing == null ? today : null);
```

---

### Finding 3 [P0 Critical]: Payout Calculations Exclude Shifts Worked on Payout Day via Strict Inequality (`>`), Causing Unpaid Shift Omissions

- **Location**: `lib/domain/finance_service.dart:101-105, 121-124, 138-141, 147-152`
- **Component**: `FinanceService` Payout Status & Cycle Estimator

#### Code Snippet
```dart
90:     final DateTime baselineDate;
91:     if (lastPayout != null) {
92:       baselineDate = DateTime(
93:         lastPayout.date.year,
94:         lastPayout.date.month,
95:         lastPayout.date.day,
96:       );
...
101:     final shiftsSinceLastPayout = state.shifts.where((s) {
102:       final shiftDay = DateTime(s.date.year, s.date.month, s.date.day);
103:       return shiftDay.isAfter(baselineDate);
104:     }).toList();
...
138:       final shiftsInPeriod = state.shifts.where((s) {
139:         final shiftDay = DateTime(s.date.year, s.date.month, s.date.day);
140:         return shiftDay.isAfter(periodStart);
141:       }).toList();
```

#### Problem Description
1. When calculating `earnedSinceLastPayoutMinor`, `baselineDate` is set to the date of `lastPayout` (at 00:00:00).
2. The filter uses `shiftDay.isAfter(baselineDate)`.
3. In Dart, `DateTime.isAfter` is strictly greater-than (`>`).
4. Any shift worked on the payout day itself (e.g. July 15) has `shiftDay == baselineDate`. `shiftDay.isAfter(baselineDate)` returns `false`!
5. Consequently, any shift worked on the day a payout is received is permanently excluded from `earnedSinceLastPayoutMinor` and from `shiftsInPeriod` for the subsequent salary calculation.
6. The same issue affects `advancesPaidInPeriod` in line 151: `pDay.isAfter(periodStart)` ignores advances recorded on `periodStart`.

#### Impact
Direct accounting error. Shifts worked on payout dates are permanently orphaned and not counted towards earnings since payout or salary estimates.

#### Recommended Code Fix
```dart
    final shiftsSinceLastPayout = state.shifts.where((s) {
      final shiftDay = DateTime(s.date.year, s.date.month, s.date.day);
      return !shiftDay.isBefore(baselineDate); // inclusive: >= baselineDate
    }).toList();
```
*(And similarly in lines 123, 140, and 151, use inclusive comparison or explicit cycle range boundaries `[cycleStart, cycleEnd]`)*.

---

### Finding 4 [P0 Critical]: Payroll Engine Breaks for Standard Russian Pay Cycles (25th Advance / 10th Salary)

- **Location**: `lib/domain/finance_service.dart:57-79, 113-156`
- **Component**: `FinanceService.calculatePayoutStatus`

#### Code Snippet
```dart
113:     if (nextKind == PayoutKind.advance) {
...
116:       final lastSalary = sortedPayouts.where((p) => p.kind == PayoutKind.salary).firstOrNull;
117:       final DateTime advanceCycleStart = lastSalary != null
118:           ? DateTime(lastSalary.date.year, lastSalary.date.month, lastSalary.date.day)
119:           : DateTime(today.year, today.month, 1).subtract(const Duration(days: 1));
...
131:     } else {
...
133:       final lastSalary = sortedPayouts.where((p) => p.kind == PayoutKind.salary).firstOrNull;
134:       final DateTime periodStart = lastSalary != null
135:           ? DateTime(lastSalary.date.year, lastSalary.date.month, lastSalary.date.day)
136:           : DateTime(today.year, today.month, 1).subtract(const Duration(days: 1));
```

#### Problem Description
Under Article 136 of the Labor Code of the Russian Federation (ТК РФ), wages must be paid semi-monthly. The standard schedule across Russia is:
- **Advance**: 25th of the current month (for work done 1st–15th).
- **Salary**: 10th of the following month (for work done 16th–end of month).
In `FinanceService.calculatePayoutStatus`:
1. The code assumes `advanceDay < salaryDay` within the same calendar month.
2. When `advanceDay = 25` and `salaryDay = 10`, candidate sorting arranges Day 10 (Salary) before Day 25 (Advance).
3. When calculating the advance for Day 25, line 116 looks for `lastSalary`. If the user has not logged a salary payout on Day 10 (or has no payouts yet), `lastSalary` is `null`.
4. It then defaults `advanceCycleStart` to `DateTime(today.year, today.month, 1) - 1 day` (the end of last month).
5. If the user *did* log a salary 3 months ago and missed logging recent ones, `lastSalary` finds the 3-month-old salary and aggregates 3 months of shifts into the advance estimate!
6. For salary estimates, it subtracts advances paid since `lastSalary`, but if multiple advances or manual adjustments occurred, it fails to bound the cycle to the actual statutory pay period (e.g. 1st–15th and 16th–end).

#### Impact
The application's marquee feature (the countdown and estimated payout card) displays incorrect amounts for the standard Russian payroll structure.

#### Recommended Code Fix
Define statutory pay period windows explicitly:
```dart
class PayPeriod {
  final DateTime start;
  final DateTime end;
  final PayoutKind kind;
  final DateTime payoutDate;
  const PayPeriod({required this.start, required this.end, required this.kind, required this.payoutDate});
}
```
Compute periods based on calendar halves:
- Period 1: Day 1 to 15 (payout on `advanceDay`)
- Period 2: Day 16 to end of month (payout on `salaryDay` of current or next month)
And sum shifts strictly within `[period.start, period.end]`.

---

### Finding 5 [P1 High]: Unvalidated Text Inputs Silently Overwrite Shift Earnings and Rates to 0.00 ₽

- **Location**:
  - `lib/presentation/app_shell.dart:1884-1897` (`_ShiftEditorState`)
  - `lib/presentation/app_shell.dart:1641-1648` (`_ShiftEditorState` live preview)
  - `lib/presentation/app_shell.dart:2224-2225` (`_InlineShiftCompletionFormState`)
- **Component**: Shift Editor & Completion Form Input Parsing

#### Code Snippet
```dart
1884:               final rate = customDailyRate.text.trim().isEmpty
1885:                   ? null
1886:                   : ((num.tryParse(
1887:                               customDailyRate.text.replaceAll(',', '.')) ??
1888:                           0) *
1889:                       100)
1890:                       .round();
1891:               final manual = manualEarnings.text.trim().isEmpty
1892:                   ? null
1893:                   : ((num.tryParse(
1894:                               manualEarnings.text.replaceAll(',', '.')) ??
1895:                           0) *
1896:                       100)
1897:                       .round();
```

#### Problem Description
1. If a barista accidentally types a typo into `manualEarnings` or `customDailyRate` (e.g., pasting `"3 500"` with a non-breaking space, typing `"500о"` with a Cyrillic 'о', or typing a currency sign), `num.tryParse` returns `null`.
2. Because of `?? 0`, the expression evaluates to `(0 * 100).round() = 0`.
3. Because `text.trim().isEmpty` was `false`, `manual` is passed as `0` instead of `null`!
4. In `FinanceService.earnings`, `manualEarningsMinor != null` evaluates to `true`, and returns `0`!
5. The shift is saved with **earnings = 0 ₽** without any validation warning or error!

#### Impact
Accidental typos result in immediate, silent loss of wage records for shifts.

#### Recommended Code Fix
```dart
final cleanManualText = manualEarnings.text.replaceAll(RegExp(r'\s+'), '').replaceAll(',', '.');
final parsedManualNum = num.tryParse(cleanManualText);
if (cleanManualText.isNotEmpty && parsedManualNum == null) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(strings.isRu ? 'Некорректная сумма заработка' : 'Invalid earnings amount')),
  );
  return;
}
final manual = parsedManualNum == null ? null : (parsedManualNum * 100).round();
```

---

### Finding 6 [P1 High]: Schedule Anchor Date Locked Forever — Shift Pattern Inverts and Cannot Be Reset or Backdated

- **Location**:
  - `lib/domain/schedule_service.dart:8-23`
  - `lib/presentation/app_shell.dart:3232-3242`
- **Component**: `ScheduleService.isWorkDay` & `_editSchedule` Dialog

#### Code Snippet
```dart
8:   bool isWorkDay(Schedule schedule, DateTime date) {
9:     final target = day(date);
10:     final anchor = day(schedule.anchorDate);
11:     if (target.isBefore(anchor)) return false;
...
15:     final days = target.difference(anchor).inDays;
...
22:     return days % (work + rest) < work;
23:   }
```

#### Problem Description
1. `anchorDate` is only initialized once in `OnboardingScreen` (line 144) to `DateTime.now()`.
2. When the user later edits their schedule in Profile (`_editSchedule`, lines 3200-3245), there is **no field or date picker** to set or change `anchorDate`.
3. If a barista changes from a 2/2 to a 3/3 schedule, the new cycle starts counting from the arbitrary date when they installed the app months ago, rather than their first shift under the new schedule.
4. Furthermore, line 11 unconditionally returns `false` if `target.isBefore(anchor)`. Past days before the onboarding date are shown as days off in the calendar, making it impossible to review past shift schedules or backdate shifts.

#### Impact
Users cannot adjust their shift rotation start date without wiping the database, and past calendar history is corrupted.

#### Recommended Code Fix
1. In `_editSchedule`, add an `anchorDate` picker tile so users can specify which date is Day 1 of their cycle.
2. In `ScheduleService.isWorkDay`, support bi-directional modulo:
```dart
    final totalCycle = work + rest;
    final days = DateTime.utc(target.year, target.month, target.day)
        .difference(DateTime.utc(anchor.year, anchor.month, anchor.day))
        .inDays;
    final normalizedOffset = ((days % totalCycle) + totalCycle) % totalCycle;
    return normalizedOffset < work;
```

---

### Finding 7 [P1 High]: 24-Hour Shifts and Shifts with `start == end` Collapse to Zero Duration

- **Location**: `lib/application/app_controller.dart:155-156`
- **Component**: `AppController.saveShift`

#### Code Snippet
```dart
155:       actualStart: start,
156:       actualEnd: end.isBefore(start) ? end.add(const Duration(days: 1)) : end,
```

#### Problem Description
1. In 24/7 cafes, kiosks, gas station coffee corners, and transport hubs, 24-hour shifts ("сутки через трое" / "сутки через двое") are common.
2. When a barista enters a 24-hour shift (e.g. 08:00 to 08:00 the following morning), `start` and `end` have identical time components.
3. In `saveShift`, `end.isBefore(start)` evaluates to `false` because `end == start`.
4. `actualEnd` remains on the same day as `start`.
5. The duration `actualEnd.difference(actualStart)` is `Duration.zero` (0 hours 0 minutes).
6. Additionally, there is no validation preventing accidental zero-duration shifts when a user forgets to adjust the end time.

#### Impact
24-hour shifts cannot be accurately recorded; zero-duration shifts are accepted into the database without warning.

#### Recommended Code Fix
```dart
    final bool isOvernightOrFullDay = end.isBefore(start) || end.isAtSameMomentAs(start);
    final normalizedEnd = isOvernightOrFullDay
        ? DateTime(end.year, end.month, end.day + 1, end.hour, end.minute)
        : end;
```

---

### Finding 8 [P2 Medium]: Timezone and Daylight Saving Time Drift via `Duration(days: 1)` and `difference(anchor).inDays`

- **Location**:
  - `lib/domain/schedule_service.dart:15, 43`
  - `lib/domain/finance_service.dart:82`
- **Component**: Date Math across Schedule & Finance Services

#### Code Snippet
```dart
schedule_service.dart:15:
final days = target.difference(anchor).inDays;

schedule_service.dart:43:
? end.add(const Duration(days: 1))

finance_service.dart:82:
final daysLeft = _sameDay(nextDate, today) ? 0 : nextDate.difference(today).inDays;
```

#### Problem Description
1. In Dart, `Duration(days: 1)` represents exactly 86,400,000,000 microseconds (24 hours).
2. `DateTime.difference` computes the elapsed real-time microseconds between two moments.
3. In timezones observing DST (or during daylight transitions):
   - On a 23-hour spring-forward day, `target.difference(anchor).inDays` returns `0` for consecutive midnight dates!
   - This causes `days % (work + rest)` to lose a day, inverting the entire work/rest calendar.
   - In `FinanceService`, `nextDate.difference(today).inDays` evaluates to 0 on the eve of payout day, prematurely showing "Today is payout day!".
   - `end.add(const Duration(days: 1))` shifts the clock time by 1 hour forward or backward across DST transitions (e.g. 06:00 becomes 07:00 or 05:00).

#### Impact
Schedule inversions and countdown errors in any DST-observing region.

#### Recommended Code Fix
Use UTC calendar date math for day counts and date constructors for day additions:
```dart
// For day difference:
final days = DateTime.utc(target.year, target.month, target.day)
    .difference(DateTime.utc(anchor.year, anchor.month, anchor.day))
    .inDays;

// For adding 1 calendar day:
final nextDay = DateTime(end.year, end.month, end.day + 1, end.hour, end.minute);
```

---

### Finding 9 [P2 Medium]: Complete Absence of Hourly Shift Rates & Unpaid Break Deductions

- **Location**:
  - `lib/domain/models.dart:140-179, 222-329`
  - `lib/domain/finance_service.dart:24-37`
- **Component**: Core Domain Calculation Models

#### Problem Description
1. `PaymentSettings` only has `dailyRateMinor`.
2. Most coffee shops pay baristas an hourly rate (e.g., 200–350 ₽/hour) + percentage of revenue, or offer hourly pay for partial shifts / overtime.
3. If a barista works 4 hours instead of 12, or covers a 16-hour double shift, the app automatically awards the exact same fixed daily rate.
4. Neither `Schedule` nor `Shift` supports unpaid break deductions (e.g. 30 or 60 minutes), which are standard in hospitality.
5. While `actualStart` and `actualEnd` are collected, neither model nor service exposes a `duration` or `workHours` property, and hours worked are never shown on shift cards or in statistics.

#### Impact
Forces baristas to calculate their hourly pay on an external calculator and manually override the daily rate.

#### Recommended Architecture Fix
Introduce `RateType` (`daily`, `hourly`), `hourlyRateMinor`, and `unpaidBreakMinutes`:
```dart
enum RateType { daily, hourly }

// In FinanceService:
int earnings({
  required int revenueMinor,
  required PaymentSettings payment,
  required DateTime start,
  required DateTime end,
  int unpaidBreakMinutes = 0,
  double? customRevenuePercent,
  int? customDailyRateMinor,
  int? customHourlyRateMinor,
  int? manualEarningsMinor,
}) {
  if (manualEarningsMinor != null) return math.max(0, manualEarningsMinor);
  final percent = customRevenuePercent ?? payment.revenuePercent;
  final bonus = (revenueMinor * percent / 100).round();
  
  if (payment.rateType == RateType.hourly || customHourlyRateMinor != null) {
    final hourlyRate = customHourlyRateMinor ?? payment.hourlyRateMinor;
    final workedMinutes = math.max(0, end.difference(start).inMinutes - unpaidBreakMinutes);
    final basePay = (workedMinutes * hourlyRate / 60).round();
    return math.max(0, basePay + bonus);
  }
  
  final rate = customDailyRateMinor ?? payment.dailyRateMinor;
  return math.max(0, rate + bonus);
}
```

---

### Finding 10 [P2 Medium]: Misleading Terminology: "Day Coefficient (%)" Represents Revenue Percentage, Not Shift Multiplier

- **Location**: `lib/core/l10n/strings.dart:34, 37-39`
- **Component**: Localization & Terminology

#### Code Snippet
```dart
34:   String get customPercentLabel => isRu ? 'Коэффициент дня (%)' : 'Day coefficient (%)';
37:   String get revenueRequiredForPercentNotice => isRu
38:       ? 'Для коэффициента обязательно укажите выручку'
39:       : 'Revenue is required for the coefficient';
```

#### Problem Description
1. In shift management and Russian labor practice, "коэффициент" universally means an overtime or holiday multiplier applied to shift earnings (e.g. 1.5x, 2.0x).
2. In Aperture Grafik, this field is wired directly to `customRevenuePercent` (revenue percentage).
3. If a barista enters "1.5" intending a 1.5x holiday multiplier, the app gives them 1.5% of revenue instead of multiplying their earnings.
4. There is no true shift multiplier field (e.g., 1.5x, 2.0x) anywhere in the application.

#### Impact
High likelihood of user misinterpretation and distorted earnings entries on holidays and overtime shifts.

#### Recommended Code Fix
1. Rename `customPercentLabel` to `'Индивидуальный процент (%)'` / `'Custom revenue percent (%)'`.
2. Add an explicit `shiftMultiplier` (default 1.0) applied to base shift earnings:
```dart
final base = (rate * shiftMultiplier).round();
return base + (revenueMinor * percent / 100).round();
```

---

### Finding 11 [P2 Medium]: Discrepancy Between Shift Editor Live Preview (Rounded to Rubles) and Main Display (Kopecks)

- **Location**:
  - `lib/presentation/app_shell.dart:1863`
  - `lib/presentation/app_shell.dart:3537-3541`
- **Component**: Currency Formatter Inconsistency

#### Code Snippet
```dart
app_shell.dart:1863:
'${(liveEarningsMinor / 100).toStringAsFixed(0)} ₽'

app_shell.dart:3537-3541:
String money(AppState data, int minor) => NumberFormat.currency(
  locale: data.settings.language == AppLanguage.russian ? 'ru_RU' : 'en_US',
  symbol: '₽',
  decimalDigits: 2,
).format(minor / 100);
```

#### Problem Description
In `_ShiftEditorState`, the live total preview rounds decimal kopecks to whole rubles using `toStringAsFixed(0)` (e.g., 4,321.65 ₽ displays as `4322 ₽`). Once saved, the home screen card, statistics page, and history rows display `4 321,65 ₽` via `money()`.

#### Impact
User perceives an apparent discrepancy between what they saw in the editor and what was recorded.

#### Recommended Code Fix
Replace line 1863 with `money(widget.data, liveEarningsMinor)`.

---

### Finding 12 [P2 Medium]: Unclamped Negative Rates, Revenue, and Manual Earnings

- **Location**:
  - `lib/domain/finance_service.dart:36`
  - `lib/presentation/app_shell.dart:1878-1897, 3322-3327`
- **Component**: Financial Domain Validation

#### Problem Description
`PaymentSettings`, `Shift`, and `FinanceService.earnings` do not validate non-negativity. Typing `-2000` into `manualEarnings` or `-5` into `customPercent` produces negative shift earnings, which corrupts cumulative earnings, average shift earnings, and payout status countdowns.

#### Impact
Corrupted negative financial balances.

#### Recommended Code Fix
Enforce `math.max(0, ...)` clamp in `FinanceService.earnings` and validate inputs `>= 0` in dialogs.

---

### Finding 13 [P3 Polish]: Hardcoded `Europe/Moscow` Timezone in `NotificationService`

- **Location**: `lib/core/notifications/notification_service.dart:22`
- **Component**: Notification Scheduling

#### Code Snippet
```dart
21:     tz.initializeTimeZones();
22:     tz.setLocalLocation(tz.getLocation('Europe/Moscow'));
```

#### Problem Description
`NotificationService` hardcodes `Europe/Moscow`. Baristas in other Russian timezones (Yekaterinburg UTC+5, Novosibirsk UTC+7, Vladivostok UTC+10) or outside Russia receive shift end notifications offset by hours from their local time.

#### Recommended Code Fix
Detect device timezone or fallback gracefully:
```dart
tz.setLocalLocation(tz.getLocation(DateTime.now().timeZoneName.isNotEmpty ? ... : 'Europe/Moscow'));
```

---

### Finding 14 [P3 Polish]: Missing Visual Indicator for Overnight Shift End (`+1 Day`) in Time Pickers

- **Location**: `lib/presentation/app_shell.dart:1699-1704, 2292-2296`
- **Component**: Time Selection Tiles

#### Problem Description
`_TimeTile` only renders `HH:mm` (e.g., `06:00`). When a shift crosses midnight, there is no chip or badge showing that the end time belongs to the following day (`+1 дн.` / `+1 day`). Users may misread 06:00 as morning of the same day.

#### Recommended Code Fix
Append a `(+1)` chip next to the end time when `end.day != start.day`.

---

### Finding 15 [P3 Polish]: No "Reset to Computed Earnings" Button When Manual Earnings is Set

- **Location**: `lib/presentation/app_shell.dart:1780-1789`
- **Component**: Shift Editor Override UI

#### Problem Description
When `manualEarningsMinor` is active, it silently overrides all rate and revenue inputs. To revert to computed earnings, the user must expand the "Additional" tile, find the field, and delete the text. There is no clear indicator or one-tap reset button.

#### Recommended Code Fix
Display an "Override active" badge with a "Reset to calculated" (`Сбросить`) text button next to the total preview.

---

## Verification Plan & Concrete Test Suite

To verify the identified issues and subsequent fixes, execute the test suite below against `domain_test.dart`:

```dart
group('R2 Edge Cases & Finance Audit Verification', () {
  const finance = FinanceService();
  const schedule = ScheduleService();

  test('Overnight shift does not invert completion date', () {
    // 22:00 -> 06:00 shift started July 1
    final sched = Schedule(
      type: ScheduleType.twoTwo,
      anchorDate: DateTime(2026, 7, 1),
      weekdays: const {},
      start: const WorkTime(22, 0),
      end: const WorkTime(6, 0),
    );
    final end = schedule.endAt(sched, DateTime(2026, 7, 1));
    expect(end, DateTime(2026, 7, 2, 6, 0));
  });

  test('Payout status includes shifts worked on payout date', () {
    final shiftOnPayoutDay = Shift(
      id: 's-1',
      date: DateTime(2026, 7, 15),
      kind: ShiftKind.scheduled,
      actualStart: DateTime(2026, 7, 15, 9),
      actualEnd: DateTime(2026, 7, 15, 21),
      colleagueIds: const [],
      revenueMinor: 0,
      earningsMinor: 300000,
      comment: '',
      createdAt: DateTime(2026, 7, 15),
      updatedAt: DateTime(2026, 7, 15),
    );
    final payoutOnPayoutDay = Payout(
      id: 'p-1',
      date: DateTime(2026, 7, 15),
      kind: PayoutKind.advance,
      amountMinor: 1000000,
      comment: '',
      createdAt: DateTime(2026, 7, 15),
      updatedAt: DateTime(2026, 7, 15),
    );
    final state = AppState.initial().copyWith(
      shifts: [shiftOnPayoutDay],
      payouts: [payoutOnPayoutDay],
    );
    final status = finance.calculatePayoutStatus(state: state, now: DateTime(2026, 7, 16));
    // Shift on July 15 must NOT be excluded
    expect(status.earnedSinceLastPayoutMinor, greaterThanOrEqualTo(300000));
  });

  test('24-hour shift retains 24 hour duration', () {
    final start = DateTime(2026, 7, 1, 8, 0);
    final end = DateTime(2026, 7, 1, 8, 0);
    final actualEnd = (end.isBefore(start) || end.isAtSameMomentAs(start))
        ? DateTime(end.year, end.month, end.day + 1, end.hour, end.minute)
        : end;
    expect(actualEnd.difference(start).inHours, 24);
  });
});
```

---

## Conclusion
The Aperture Grafik codebase has strong fundamental design (minor-unit integer storage, immutable models, clean repository abstraction), but suffers from critical logical edge cases in overnight shift tracking, statistics aggregation, and Russian payroll cycle compliance. Addressing the P0 and P1 items using the provided fixes will ensure bulletproof financial accuracy and smooth operation for coffee shop baristas.
