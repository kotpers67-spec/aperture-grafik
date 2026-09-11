import 'models.dart';

class PayoutStatus {
  const PayoutStatus({
    required this.nextKind,
    required this.nextDate,
    required this.daysLeft,
    required this.lastPayout,
    required this.earnedSinceLastPayoutMinor,
    required this.estimatedNextPayoutMinor,
  });

  final PayoutKind nextKind;
  final DateTime nextDate;
  final int daysLeft;
  final Payout? lastPayout;
  final int earnedSinceLastPayoutMinor;
  final int estimatedNextPayoutMinor;
}

class FinanceService {
  const FinanceService();

  int earnings({required int revenueMinor, required PaymentSettings payment}) =>
      payment.dailyRateMinor +
      (revenueMinor * payment.revenuePercent / 100).round();

  DateTime _resolveDate(int year, int month, int targetDay) {
    final maxDay = DateTime(year, month + 1, 0).day;
    final clampedDay = targetDay > maxDay ? maxDay : (targetDay < 1 ? 1 : targetDay);
    return DateTime(year, month, clampedDay);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  PayoutStatus calculatePayoutStatus({
    required AppState state,
    required DateTime now,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final payment = state.payment;

    // Generate candidate payout dates for previous, current and next month to find the next upcoming payout
    final candidates = <({DateTime date, PayoutKind kind})>[];
    for (int monthOffset = -1; monthOffset <= 2; monthOffset++) {
      final m = DateTime(today.year, today.month + monthOffset, 1);
      candidates.add((
        date: _resolveDate(m.year, m.month, payment.advanceDay),
        kind: PayoutKind.advance,
      ));
      candidates.add((
        date: _resolveDate(m.year, m.month, payment.salaryDay),
        kind: PayoutKind.salary,
      ));
    }

    candidates.sort((a, b) => a.date.compareTo(b.date));

    // Next payout is the first one that is >= today
    final upcoming = candidates.firstWhere(
      (c) => !c.date.isBefore(today),
      orElse: () => (
        date: _resolveDate(today.year, today.month + 1, payment.salaryDay),
        kind: PayoutKind.salary,
      ),
    );

    final nextKind = upcoming.kind;
    final nextDate = upcoming.date;
    final daysLeft = _sameDay(nextDate, today) ? 0 : nextDate.difference(today).inDays;

    // Find the most recent payout (before or on today, or overall latest recorded)
    final sortedPayouts = [...state.payouts]
      ..sort((a, b) => b.date.compareTo(a.date));
    final lastPayout = sortedPayouts.isEmpty ? null : sortedPayouts.first;

    // Shifts earned since last payout (or current month if no payout recorded)
    final DateTime baselineDate;
    if (lastPayout != null) {
      baselineDate = DateTime(
        lastPayout.date.year,
        lastPayout.date.month,
        lastPayout.date.day,
      );
    } else {
      baselineDate = DateTime(today.year, today.month, 1).subtract(const Duration(days: 1));
    }

    final shiftsSinceLastPayout = state.shifts.where((s) {
      final shiftDay = DateTime(s.date.year, s.date.month, s.date.day);
      return shiftDay.isAfter(baselineDate);
    }).toList();

    final earnedSinceLastPayoutMinor = shiftsSinceLastPayout.fold<int>(
      0,
      (sum, s) => sum + s.earningsMinor,
    );

    // Calculate estimated next payout
    int estimatedNextPayoutMinor;
    if (nextKind == PayoutKind.advance) {
      // If waiting for advance, expected amount is what was earned in this advance cycle
      // (from last salary or start of current period up to today)
      final lastSalary = sortedPayouts.where((p) => p.kind == PayoutKind.salary).firstOrNull;
      final DateTime advanceCycleStart = lastSalary != null
          ? DateTime(lastSalary.date.year, lastSalary.date.month, lastSalary.date.day)
          : DateTime(today.year, today.month, 1).subtract(const Duration(days: 1));

      final shiftsInAdvanceCycle = state.shifts.where((s) {
        final shiftDay = DateTime(s.date.year, s.date.month, s.date.day);
        return shiftDay.isAfter(advanceCycleStart);
      }).toList();

      estimatedNextPayoutMinor = shiftsInAdvanceCycle.fold<int>(
        0,
        (sum, s) => sum + s.earningsMinor,
      );
    } else {
      // Next is Salary: total earnings for the period minus any advances paid in this period
      final lastSalary = sortedPayouts.where((p) => p.kind == PayoutKind.salary).firstOrNull;
      final DateTime periodStart = lastSalary != null
          ? DateTime(lastSalary.date.year, lastSalary.date.month, lastSalary.date.day)
          : DateTime(today.year, today.month, 1).subtract(const Duration(days: 1));

      final shiftsInPeriod = state.shifts.where((s) {
        final shiftDay = DateTime(s.date.year, s.date.month, s.date.day);
        return shiftDay.isAfter(periodStart);
      }).toList();

      final totalEarningsInPeriod = shiftsInPeriod.fold<int>(
        0,
        (sum, s) => sum + s.earningsMinor,
      );

      final advancesPaidInPeriod = state.payouts.where((p) {
        if (p.kind != PayoutKind.advance) return false;
        final pDay = DateTime(p.date.year, p.date.month, p.date.day);
        return pDay.isAfter(periodStart);
      }).fold<int>(0, (sum, p) => sum + p.amountMinor);

      final remainingSalary = totalEarningsInPeriod - advancesPaidInPeriod;
      estimatedNextPayoutMinor = remainingSalary > 0 ? remainingSalary : 0;
    }

    return PayoutStatus(
      nextKind: nextKind,
      nextDate: nextDate,
      daysLeft: daysLeft,
      lastPayout: lastPayout,
      earnedSinceLastPayoutMinor: earnedSinceLastPayoutMinor,
      estimatedNextPayoutMinor: estimatedNextPayoutMinor,
    );
  }
}
