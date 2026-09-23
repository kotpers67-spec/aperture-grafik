# Handoff Report: R2 Finance, Shift Logic & Calculation Edge Cases

**Agent**: Finance & Shift Logic Auditor (`explorer_r2_finance`)  
**Target Project**: `F:\Projects\aperture-grafik`  
**Working Directory**: `F:\Projects\aperture-grafik\.agents\explorer_r2_finance`  
**Handoff Type**: Hard (Investigation & Audit Complete)  
**Date**: 2026-09-23  

---

## 1. Observation

Direct code inspections across `lib/` and `test/` revealed the following concrete observations:

1. **Statistics Aggregation Collision**:
   In `lib/presentation/app_shell.dart:765-772`, chart bars are mapped by `shift.date.day` (day of month, 1..31). For yearly statistics, all 12 months collapse into 31 bars (`points[15]` contains all 15th-day earnings across the entire year).
2. **Overnight Shift State Inversion**:
   In `lib/presentation/app_shell.dart:444-462`, `active` shift and `pendingDay` only evaluate `today`'s schedule. Between 00:00 and 06:00 during an ongoing night shift, `active` evaluates to `false`. After 06:00, if today is also a scheduled day, `completionDate` resolves to `today` instead of `yesterday`, attributing the shift to the wrong calendar date.
3. **Payout Day Shift Omission**:
   In `lib/domain/finance_service.dart:101-105` and `138-141`, filters use `shiftDay.isAfter(baselineDate)` (strict inequality `>`). Shifts worked on the day a payout occurs are permanently excluded from both `earnedSinceLastPayoutMinor` and `shiftsInPeriod`.
4. **Russian Payroll 25th/10th Cycle Failure**:
   In `lib/domain/finance_service.dart:113-156`, advance and salary estimation unconditionally expects `lastSalary` to be the boundary. In Russia (ТК РФ Art. 136), Advance is on the 25th (for 1st–15th) and Salary is on the 10th of next month (for 16th–end). When `advanceDay = 25` and `salaryDay = 10`, the estimator fails to identify cycle boundaries and accumulates stale months of shifts.
5. **Silent Zero-Wage Data Corruption**:
   In `lib/presentation/app_shell.dart:1886-1897`, number parsing uses `num.tryParse(...) ?? 0`. Entering any invalid character (e.g. "3 500" or a Cyrillic letter) results in `0 * 100 = 0`, saving the barista's manual shift earnings as `0 ₽`.
6. **Schedule Anchor Date Locked**:
   In `lib/domain/schedule_service.dart:8-23` and `lib/presentation/app_shell.dart:3232-3242`, `anchorDate` is only set at onboarding. `_editSchedule` provides no way to update it, and `isWorkDay` returns `false` unconditionally for any date before `anchorDate`.
7. **24-Hour Shift Collapse**:
   In `lib/application/app_controller.dart:156`, `actualEnd: end.isBefore(start) ? end.add(const Duration(days: 1)) : end`. When `start == end` (24-hour shift), `end.isBefore(start)` is false, yielding zero duration.
8. **Missing Hourly Rates & Break Deductions**:
   `PaymentSettings` only contains `dailyRateMinor`. No hourly rates, break time deductions, or duration calculations exist in `domain/`.
9. **Misleading "Day Coefficient (%)" Label**:
   In `lib/core/l10n/strings.dart:34`, `customPercentLabel` is translated as "Коэффициент дня (%)", but wires to revenue percent rather than a shift multiplier (e.g. 1.5x).

---

## 2. Logic Chain

1. **Observation 1 → Logic**: `shift.date.day` is bounded in `1..31`. A list of shifts across 365 days contains multiple instances of each day number. Grouping by day number without year and month disambiguation inevitably collapses annual data into 31 buckets.
2. **Observation 2 → Logic**: A shift starting at 22:00 crosses midnight. After 00:00, `DateTime.now()` belongs to the next calendar date. Because `starts` is initialized from `today` at 22:00, `now.isAfter(starts)` is false. Since `yesterdayShift == null` and `now < yesterdayEnd`, `pendingDay` is null. The overnight shift is invisible until after 06:00, at which point `planned && existing == null` for today overrides `yesterday`, logging the shift under today.
3. **Observation 3 → Logic**: `DateTime.isAfter` tests `a.isAfter(b) == true` iff `a > b`. When `a` and `b` represent the same midnight timestamp `DateTime(year, month, day)`, `a.isAfter(b)` is false. Thus any shift sharing the date of `lastPayout` is discarded from the summation.
4. **Observation 4 → Logic**: Looking backwards for the last recorded entity in SQLite is nondeterministic if users do not record every single payment. Real-world payroll cycles are bounded by statutory calendar intervals (first half vs second half), not by previous transaction logs.
5. **Observation 5 → Logic**: The UI checks `text.trim().isEmpty`. If text is non-empty but unparseable, `num.tryParse` returns `null`. The fallback `?? 0` coerces it to `0`. Passing `0` to `manualEarningsMinor` triggers the override branch in `FinanceService.earnings`, returning `0` total wages.
6. **Observation 7 → Logic**: `08:00.isBefore(08:00)` is false. Therefore `actualEnd` is not shifted to the next day. The difference between two identical moments is 0.

---

## 3. Caveats

1. The Flutter test suite was executed via `F:\Development\flutter\bin\flutter.bat test` and all 13 existing widget and domain tests currently pass, because existing tests only assert happy paths with fixed mock dates and non-zero durations.
2. `flutter analyze` reports 0 issues.
3. Code modifications were NOT applied directly to `lib/` in accordance with the read-only explorer constraint; all recommended code diffs are detailed in `report.md`.
4. Russian labor code norms (ТК РФ Art. 136) were used as the primary domain reference for coffee shop shift payroll schedules.

---

## 4. Conclusion

The Aperture Grafik codebase is well-structured and uses immutable state patterns, but contains critical flaws in shift lifecycle management for night shifts, statistics visualization, and payout calculations. Specifically:
- **P0 Critical**: 4 issues requiring immediate remediation (Statistics aggregation, Night shift lifecycle inversion, Payout day omission, Russian 25th/10th cycle failure).
- **P1 High**: 3 issues requiring fix before release (Input parsing zero-wage bug, Anchor date uneditable, 24-hour shift collapse).
- **P2 Medium**: 5 architectural improvements (Hourly rate & break deduction support, DST-safe date math, terminology clarification, UI rounding alignment, negative input guard).
- **P3 Polish**: 3 UX enhancements (Timezone notification detection, `+1 day` chip in time pickers, reset override button).

---

## 5. Verification Method

To verify these issues and ensure fixes work:
1. Run existing test suite:
   ```powershell
   & "F:\Development\flutter\bin\flutter.bat" test
   ```
2. Add the test group documented in Section "Verification Plan & Concrete Test Suite" of `report.md` to `test/domain_test.dart` to assert:
   - Overnight shift completion date on day after night shift.
   - Payout day shift inclusion (`>= baselineDate`).
   - 24-hour shift 24-hour duration retention.
   - Modulo calculation for dates before `anchorDate`.
3. Run static analyzer:
   ```powershell
   & "F:\Development\flutter\bin\flutter.bat" analyze
   ```
