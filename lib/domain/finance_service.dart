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

  static const defaultAdvanceShare = 0.30;

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
    final clampedDay = targetDay > maxDay
        ? maxDay
        : (targetDay < 1 ? 1 : targetDay);
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
      (c) =>
          !c.date.isBefore(today) &&
          !state.payouts.any(
            (p) => p.kind == c.kind && _sameDay(p.date, c.date),
          ),
      orElse: () => (
        date: _resolveDate(today.year, today.month + 1, payment.salaryDay),
        kind: PayoutKind.salary,
      ),
    );

    final nextKind = upcoming.kind;
    final nextDate = upcoming.date;
    final daysLeft = _sameDay(nextDate, today)
        ? 0
        : nextDate.difference(today).inDays;

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
      baselineDate = DateTime(
        today.year,
        today.month,
        1,
      ).subtract(const Duration(days: 1));
    }

    final shiftsSince = state.shifts.where((s) {
      final d = DateTime(s.date.year, s.date.month, s.date.day);
      return d.isAfter(baselineDate);
    }).toList();

    final earnedSinceLastPayoutMinor = shiftsSince.fold<int>(
      0,
      (sum, s) => sum + s.earningsMinor,
    );
    final workedHoursInPeriod = _totalHours(shiftsSince);

    // Аванс 30-го относится к текущему календарному месяцу. Если его внесли
    // с задержкой в первые дни следующего месяца, привязываем его к прошлому.
    final advanceMonth = advanceAccrualMonth(
      nextDate,
      advanceDay: payment.advanceDay,
      salaryDay: payment.salaryDay,
    );
    final advanceMonthShifts = state.shifts.where((shift) {
      final d = shift.date;
      return d.year == advanceMonth.year &&
          d.month == advanceMonth.month &&
          !_day(d).isAfter(today) &&
          !_day(d).isAfter(nextDate);
    }).toList();

    // Зарплата 15-го закрывает предыдущий месяц за вычетом реально внесённых
    // авансов и добавляет смены текущего месяца, уже отработанные к этой дате.
    final isLateMonthAdvance = payment.advanceDay > payment.salaryDay;
    final salaryMonth = DateTime(
      nextDate.year,
      nextDate.month - (isLateMonthAdvance ? 1 : 0),
      1,
    );
    final previousMonthShifts = state.shifts.where(
      (shift) =>
          shift.date.year == salaryMonth.year &&
          shift.date.month == salaryMonth.month,
    );
    final previousMonthEarnings = previousMonthShifts.fold<int>(
      0,
      (sum, shift) => sum + shift.earningsMinor,
    );
    final advancesInPreviousMonth = state.payouts
        .where((payout) {
          if (payout.kind != PayoutKind.advance) return false;
          final accrual = advanceAccrualMonth(
            payout.date,
            advanceDay: payment.advanceDay,
            salaryDay: payment.salaryDay,
          );
          return accrual.year == salaryMonth.year &&
              accrual.month == salaryMonth.month;
        })
        .fold<int>(0, (sum, payout) => sum + payout.amountMinor);
    final currentMonthShifts = state.shifts.where((shift) {
      final d = _day(shift.date);
      return d.year == nextDate.year &&
          d.month == nextDate.month &&
          !d.isAfter(today) &&
          !d.isAfter(nextDate);
    }).toList();
    final currentMonthEarnings = currentMonthShifts.fold<int>(
      0,
      (sum, shift) => sum + shift.earningsMinor,
    );
    final salaryRemaining = previousMonthEarnings - advancesInPreviousMonth;

    int estimatedNextPayoutMinor;
    double estimatedNextPayoutHours;

    if (nextKind == PayoutKind.advance) {
      final monthEarnings = advanceMonthShifts.fold<int>(
        0,
        (sum, shift) => sum + shift.earningsMinor,
      );
      final advanceShare = payment.advancePercent / 100;
      estimatedNextPayoutMinor = (monthEarnings * advanceShare).round();
      estimatedNextPayoutHours = _totalHours(advanceMonthShifts) * advanceShare;
    } else {
      if (isLateMonthAdvance) {
        estimatedNextPayoutMinor =
            (salaryRemaining > 0 ? salaryRemaining : 0) + currentMonthEarnings;
        estimatedNextPayoutHours =
            _totalHours(previousMonthShifts.toList()) +
            _totalHours(currentMonthShifts);
      } else {
        estimatedNextPayoutMinor = salaryRemaining > 0 ? salaryRemaining : 0;
        estimatedNextPayoutHours = _totalHours(previousMonthShifts.toList());
      }
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

  DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

  DateTime advanceAccrualMonth(
    DateTime payoutDate, {
    required int advanceDay,
    required int salaryDay,
  }) {
    final date = _day(payoutDate);
    if (advanceDay > salaryDay && date.day <= salaryDay) {
      return DateTime(date.year, date.month - 1, 1);
    }
    return DateTime(date.year, date.month, 1);
  }
}
