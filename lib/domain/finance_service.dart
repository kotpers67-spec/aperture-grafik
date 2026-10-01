import 'models.dart';

class PayoutStatus {
  const PayoutStatus({
    required this.nextKind,
    required this.nextDate,
    required this.daysLeft,
    required this.lastPayout,
    required this.earnedSinceLastPayoutMinor,
    required this.estimatedNextPayoutMinor,
    required this.workedHoursInPeriod,
    required this.estimatedNextPayoutHours,
  });

  final PayoutKind nextKind;
  final DateTime nextDate;
  final int daysLeft;
  final Payout? lastPayout;
  final int earnedSinceLastPayoutMinor;
  final int estimatedNextPayoutMinor;

  /// Суммарные отработанные часы за период (с последней выплаты).
  final double workedHoursInPeriod;

  /// Часы, за которые рассчитана следующая выплата (аванс / зарплата).
  final double estimatedNextPayoutHours;
}

class FinanceService {
  const FinanceService();

  int earnings({
    required int revenueMinor,
    required PaymentSettings payment,
    double? customRevenuePercent,
    int? customDailyRateMinor,
    int? manualEarningsMinor,
  }) {
    if (manualEarningsMinor != null) {
      return manualEarningsMinor;
    }
    final rate = customDailyRateMinor ?? payment.dailyRateMinor;
    final percent = customRevenuePercent ?? payment.revenuePercent;
    return rate + (revenueMinor * percent / 100).round();
  }

  DateTime _resolveDate(int year, int month, int targetDay) {
    final maxDay = DateTime(year, month + 1, 0).day;
    final clampedDay =
        targetDay > maxDay ? maxDay : (targetDay < 1 ? 1 : targetDay);
    return DateTime(year, month, clampedDay);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Суммирует отработанные часы по списку смен.
  double _totalHours(List<Shift> shifts) {
    return shifts.fold<double>(0.0, (sum, s) {
      final minutes = s.actualEnd.difference(s.actualStart).inMinutes;
      return sum + (minutes < 0 ? 0 : minutes / 60.0);
    });
  }

  PayoutStatus calculatePayoutStatus({
    required AppState state,
    required DateTime now,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final payment = state.payment;

    // Кандидаты на выплату: -1..+2 месяца
    final candidates = <({DateTime date, PayoutKind kind})>[];
    for (int mo = -1; mo <= 2; mo++) {
      final m = DateTime(today.year, today.month + mo, 1);
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

    // Первая выплата >= сегодня
    final upcoming = candidates.firstWhere(
      (c) => !c.date.isBefore(today),
      orElse: () => (
        date: _resolveDate(today.year, today.month + 1, payment.salaryDay),
        kind: PayoutKind.salary,
      ),
    );

    final nextKind = upcoming.kind;
    final nextDate = upcoming.date;
    final daysLeft =
        _sameDay(nextDate, today) ? 0 : nextDate.difference(today).inDays;

    // Последняя зафиксированная выплата
    final sortedPayouts = [...state.payouts]
      ..sort((a, b) => b.date.compareTo(a.date));
    final lastPayout = sortedPayouts.isEmpty ? null : sortedPayouts.first;

    // Смены с момента последней выплаты
    final DateTime baselineDate;
    if (lastPayout != null) {
      baselineDate = DateTime(
        lastPayout.date.year,
        lastPayout.date.month,
        lastPayout.date.day,
      );
    } else {
      baselineDate =
          DateTime(today.year, today.month, 1).subtract(const Duration(days: 1));
    }

    final shiftsSince = state.shifts.where((s) {
      final d = DateTime(s.date.year, s.date.month, s.date.day);
      return d.isAfter(baselineDate);
    }).toList();

    final earnedSinceLastPayoutMinor =
        shiftsSince.fold<int>(0, (sum, s) => sum + s.earningsMinor);
    final workedHoursInPeriod = _totalHours(shiftsSince);

    // ── Расчёт суммы и часов следующей выплаты ─────────────────────────────
    int estimatedNextPayoutMinor;
    double estimatedNextPayoutHours;

    if (nextKind == PayoutKind.advance) {
      // Аванс = 30% от всего заработка за текущий месяц (все отработанные дни × ставка)
      final monthStart =
          DateTime(today.year, today.month, 1).subtract(const Duration(days: 1));
      final monthShifts = state.shifts.where((s) {
        final d = DateTime(s.date.year, s.date.month, s.date.day);
        return d.isAfter(monthStart);
      }).toList();

      final totalMonthEarnings =
          monthShifts.fold<int>(0, (sum, s) => sum + s.earningsMinor);
      estimatedNextPayoutMinor = (totalMonthEarnings * 0.3).round();
      // Пропорциональные часы (30% рабочего времени за месяц)
      estimatedNextPayoutHours = _totalHours(monthShifts) * 0.3;
    } else {
      // Зарплата = весь заработок с последней зарплаты минус уже выданные авансы
      final lastSalary = sortedPayouts
          .where((p) => p.kind == PayoutKind.salary)
          .firstOrNull;
      final DateTime periodStart = lastSalary != null
          ? DateTime(
              lastSalary.date.year,
              lastSalary.date.month,
              lastSalary.date.day,
            )
          : DateTime(today.year, today.month, 1)
              .subtract(const Duration(days: 1));

      final periodShifts = state.shifts.where((s) {
        final d = DateTime(s.date.year, s.date.month, s.date.day);
        return d.isAfter(periodStart);
      }).toList();

      final totalPeriod =
          periodShifts.fold<int>(0, (sum, s) => sum + s.earningsMinor);
      final advancesPaid = state.payouts.where((p) {
        if (p.kind != PayoutKind.advance) return false;
        final d = DateTime(p.date.year, p.date.month, p.date.day);
        return d.isAfter(periodStart);
      }).fold<int>(0, (sum, p) => sum + p.amountMinor);

      final remaining = totalPeriod - advancesPaid;
      estimatedNextPayoutMinor = remaining > 0 ? remaining : 0;
      estimatedNextPayoutHours = _totalHours(periodShifts);
    }

    return PayoutStatus(
      nextKind: nextKind,
      nextDate: nextDate,
      daysLeft: daysLeft,
      lastPayout: lastPayout,
      earnedSinceLastPayoutMinor: earnedSinceLastPayoutMinor,
      estimatedNextPayoutMinor: estimatedNextPayoutMinor,
      workedHoursInPeriod: workedHoursInPeriod,
      estimatedNextPayoutHours: estimatedNextPayoutHours,
    );
  }
}
