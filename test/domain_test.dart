import 'package:aperture_grafik/domain/finance_service.dart';
import 'package:aperture_grafik/domain/models.dart';
import 'package:aperture_grafik/domain/revenue_recommendation_service.dart';
import 'package:aperture_grafik/domain/schedule_service.dart';
import 'package:aperture_grafik/core/notifications/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

void main() {
  group('ScheduleService', () {
    const service = ScheduleService();
    final schedule = Schedule(
      type: ScheduleType.twoTwo,
      anchorDate: DateTime(2026, 7, 1),
      weekdays: const {},
      start: const WorkTime(21, 0),
      end: const WorkTime(5, 0),
    );

    test('builds a 2/2 pattern and supports an overnight shift', () {
      expect(service.isWorkDay(schedule, DateTime(2026, 7, 1)), isTrue);
      expect(service.isWorkDay(schedule, DateTime(2026, 7, 2)), isTrue);
      expect(service.isWorkDay(schedule, DateTime(2026, 7, 3)), isFalse);
      expect(
        service.endAt(schedule, DateTime(2026, 7, 1)),
        DateTime(2026, 7, 2, 5),
      );
    });

    test('continues a repeating rotation before its anchor date', () {
      final restDay = DateTime(2026, 6, 30); // rotation continues across anchor
      expect(service.isWorkDay(schedule, restDay), isFalse);
      expect(service.isWorkDay(schedule, DateTime(2026, 6, 29)), isFalse);
      expect(service.isWorkDay(schedule, DateTime(2026, 6, 28)), isTrue);
    });
  });

  test('earnings include fixed rate and revenue percentage in minor units', () {
    const service = FinanceService();
    const payment = PaymentSettings(
      dailyRateMinor: 300000,
      revenuePercent: 5,
      advanceDay: 15,
      salaryDay: 30,
    );
    expect(service.earnings(revenueMinor: 5000000, payment: payment), 550000);
  });

  test(
    'payment settings default advance to 30 percent and roundtrip custom share',
    () {
      const defaults = PaymentSettings(
        dailyRateMinor: 130000,
        revenuePercent: 0,
        advanceDay: 30,
        salaryDay: 15,
      );
      expect(defaults.advancePercent, 30);
      expect(defaults.salaryPercent, 70);
      final custom = defaults.copyWith(advancePercent: 40);
      expect(PaymentSettings.fromJson(custom.toJson()).advancePercent, 40);
      expect(PaymentSettings.fromJson(custom.toJson()).salaryPercent, 60);
    },
  );

  test('visual and motion preferences survive backup serialization', () {
    const settings = AppSettings(
      language: AppLanguage.russian,
      currency: Currency.rub,
      themeMode: AppThemeMode.sakura,
      onboardingComplete: true,
      notificationsEnabled: true,
      designStyle: AppDesignStyle.aurora,
      shiftAnimationsEnabled: false,
    );
    final restored = AppSettings.fromJson(settings.toJson());
    expect(restored.themeMode, AppThemeMode.sakura);
    expect(restored.designStyle, AppDesignStyle.aurora);
    expect(restored.shiftAnimationsEnabled, isFalse);
  });

  test('earnings respect custom daily rate and custom revenue percent', () {
    const service = FinanceService();
    const payment = PaymentSettings(
      dailyRateMinor: 300000,
      revenuePercent: 5,
      advanceDay: 15,
      salaryDay: 30,
    );
    // Custom 10% percent and custom 4000 rate: 400000 + 500000 = 900000
    expect(
      service.earnings(
        revenueMinor: 5000000,
        payment: payment,
        customDailyRateMinor: 400000,
        customRevenuePercent: 10,
      ),
      900000,
    );
  });

  test(
    'manual earnings override has highest priority over rate and percent',
    () {
      const service = FinanceService();
      const payment = PaymentSettings(
        dailyRateMinor: 300000,
        revenuePercent: 5,
        advanceDay: 15,
        salaryDay: 30,
      );
      expect(
        service.earnings(
          revenueMinor: 5000000,
          payment: payment,
          customDailyRateMinor: 400000,
          customRevenuePercent: 10,
          manualEarningsMinor: 777000,
        ),
        777000,
      );
    },
  );

  test(
    'Russian and English date symbols are available before rendering',
    () async {
      await initializeDateFormatting();

      expect(
        DateFormat.yMMMMEEEEd('ru_RU').format(DateTime(2026, 7, 17)),
        isNotEmpty,
      );
      expect(
        DateFormat.yMMMMEEEEd('en_US').format(DateTime(2026, 7, 17)),
        isNotEmpty,
      );
    },
  );

  test('reminders resume on the next half-hour after a completed shift', () {
    expect(
      NotificationService.nextHalfHourAfter(DateTime(2026, 7, 17, 21, 6)),
      DateTime(2026, 7, 17, 21, 30),
    );
    expect(
      NotificationService.nextHalfHourAfter(DateTime(2026, 7, 17, 21, 42)),
      DateTime(2026, 7, 17, 22),
    );
  });

  test('recommendation uses history and flags a higher weekday pattern', () {
    final shifts = [
      _shift(DateTime(2026, 7, 3), 2000000),
      _shift(DateTime(2026, 7, 6), 1000000),
      _shift(DateTime(2026, 7, 10), 2200000),
      _shift(DateTime(2026, 7, 13), 1100000),
      _shift(DateTime(2026, 7, 17), 2400000),
      _shift(DateTime(2026, 7, 20), 1100000),
    ];
    final recommendation = const RevenueRecommendationService().recommend(
      shifts: shifts,
      targetDate: DateTime(2026, 7, 24),
    );

    expect(recommendation, isNotNull);
    expect(recommendation!.hasEnoughData, isTrue);
    expect(recommendation.referenceMinor, greaterThan(1800000));
    expect(recommendation.usuallyHigherOnThisWeekday, isTrue);
  });

  group('Payout & FinanceService calculations', () {
    const finance = FinanceService();

    test('calculates countdown and upcoming payout kind correctly', () {
      final state = AppState.initial().copyWith(
        payment: const PaymentSettings(
          dailyRateMinor: 300000,
          revenuePercent: 5,
          advanceDay: 15,
          salaryDay: 30,
        ),
      );

      // Before advance
      final statusBeforeAdv = finance.calculatePayoutStatus(
        state: state,
        now: DateTime(2026, 7, 5),
      );
      expect(statusBeforeAdv.nextKind, PayoutKind.advance);
      expect(statusBeforeAdv.daysLeft, 10);
      expect(statusBeforeAdv.nextDate, DateTime(2026, 7, 15));

      // On advance day
      final statusOnAdv = finance.calculatePayoutStatus(
        state: state,
        now: DateTime(2026, 7, 15),
      );
      expect(statusOnAdv.nextKind, PayoutKind.advance);
      expect(statusOnAdv.daysLeft, 0);

      // After advance, before salary
      final statusBeforeSal = finance.calculatePayoutStatus(
        state: state,
        now: DateTime(2026, 7, 16),
      );
      expect(statusBeforeSal.nextKind, PayoutKind.salary);
      expect(statusBeforeSal.daysLeft, 14);
      expect(statusBeforeSal.nextDate, DateTime(2026, 7, 30));

      // After salary (e.g. July 31) -> next is August 15 Advance
      final statusAfterSal = finance.calculatePayoutStatus(
        state: state,
        now: DateTime(2026, 7, 31),
      );
      expect(statusAfterSal.nextKind, PayoutKind.advance);
      expect(statusAfterSal.daysLeft, 15);
      expect(statusAfterSal.nextDate, DateTime(2026, 8, 15));
    });

    test('skips a payout already recorded for today', () {
      final todaySalary = Payout(
        id: 'salary-today',
        date: DateTime(2026, 10, 15),
        kind: PayoutKind.salary,
        amountMinor: 910000,
        comment: '',
        createdAt: DateTime(2026, 10, 15),
        updatedAt: DateTime(2026, 10, 15),
      );
      final state = AppState.initial().copyWith(
        payment: const PaymentSettings(
          dailyRateMinor: 130000,
          revenuePercent: 0,
          advanceDay: 30,
          salaryDay: 15,
          advancePercent: 40,
        ),
        payouts: [todaySalary],
      );
      final status = finance.calculatePayoutStatus(
        state: state,
        now: DateTime(2026, 10, 15),
      );
      expect(status.nextKind, PayoutKind.advance);
      expect(status.nextDate, DateTime(2026, 10, 30));
    });

    test(
      'calculates earned since last payout and next expected salary correctly',
      () {
        final shifts = [
          _shiftWithEarnings(DateTime(2026, 7, 5), 500000),
          _shiftWithEarnings(DateTime(2026, 7, 10), 500000),
          _shiftWithEarnings(DateTime(2026, 7, 18), 500000),
          _shiftWithEarnings(DateTime(2026, 7, 22), 500000),
        ];

        final advancePayout = Payout(
          id: 'payout-1',
          date: DateTime(2026, 7, 15),
          kind: PayoutKind.advance,
          amountMinor: 1000000,
          comment: 'Advance',
          createdAt: DateTime(2026, 7, 15),
          updatedAt: DateTime(2026, 7, 15),
        );

        final state = AppState.initial().copyWith(
          payment: const PaymentSettings(
            dailyRateMinor: 300000,
            revenuePercent: 5,
            advanceDay: 15,
            salaryDay: 30,
          ),
          shifts: shifts,
          payouts: [advancePayout],
        );

        final status = finance.calculatePayoutStatus(
          state: state,
          now: DateTime(2026, 7, 25),
        );

        expect(status.lastPayout?.id, 'payout-1');
        // Shifts on July 18 and July 22 are after July 15 payout: 500000 + 500000 = 1000000
        expect(status.earnedSinceLastPayoutMinor, 1000000);
        // Next is Salary (July 30). Total earned in July = 2000000. Advance paid = 1000000.
        // Expected remaining salary = 2000000 - 1000000 = 1000000.
        expect(status.nextKind, PayoutKind.salary);
        expect(status.estimatedNextPayoutMinor, 1000000);
      },
    );

    test('includes a shift recorded on the last payout day', () {
      final payoutDate = DateTime(2026, 7, 15);
      final payout = Payout(
        id: 'same-day-payout',
        date: payoutDate,
        kind: PayoutKind.advance,
        amountMinor: 390000,
        comment: '',
        createdAt: payoutDate,
        updatedAt: payoutDate,
      );
      final sameDayShift = _shiftWithEarnings(payoutDate, 130000);
      final state = AppState.initial().copyWith(
        payment: const PaymentSettings(
          dailyRateMinor: 130000,
          revenuePercent: 0,
          advanceDay: 30,
          salaryDay: 15,
        ),
        shifts: [sameDayShift],
        payouts: [payout],
      );

      final status = finance.calculatePayoutStatus(
        state: state,
        now: DateTime(2026, 7, 16),
      );

      expect(status.earnedSinceLastPayoutMinor, 130000);
    });

    test('Payout JSON serialization and AppState roundtrip', () {
      final payout = Payout(
        id: 'p-1',
        date: DateTime(2026, 7, 15),
        kind: PayoutKind.salary,
        amountMinor: 4500000,
        comment: 'Salary for July',
        createdAt: DateTime(2026, 7, 15, 10, 0),
        updatedAt: DateTime(2026, 7, 15, 10, 0),
      );

      final json = payout.toJson();
      final parsed = Payout.fromJson(json);
      expect(parsed.id, 'p-1');
      expect(parsed.kind, PayoutKind.salary);
      expect(parsed.amountMinor, 4500000);
      expect(parsed.comment, 'Salary for July');

      final state = AppState.initial().copyWith(payouts: [payout]);
      final stateJson = state.toJson();
      final restored = AppState.fromJson(stateJson);
      expect(restored.payouts.length, 1);
      expect(restored.payouts.first.id, 'p-1');
      expect(restored.payouts.first.amountMinor, 4500000);
    });

    test(
      'late-month advance and mid-month salary use the monthly 30/70 cycle',
      () {
        final shifts = <Shift>[
          for (var day = 1; day <= 10; day++)
            _shiftWithEarnings(DateTime(2026, 9, day), 130000),
          _shiftWithEarnings(DateTime(2026, 10, 2), 130000),
          _shiftWithEarnings(DateTime(2026, 10, 3), 130000),
          _shiftWithEarnings(DateTime(2026, 10, 18), 130000),
          _shiftWithEarnings(DateTime(2026, 10, 25), 130000),
        ];
        final advance = Payout(
          id: 'september-advance',
          date: DateTime(2026, 10, 1), // recorded late; belongs to September
          kind: PayoutKind.advance,
          amountMinor: 390000,
          comment: '',
          createdAt: DateTime(2026, 10, 1),
          updatedAt: DateTime(2026, 10, 1),
        );
        final state = AppState.initial().copyWith(
          payment: const PaymentSettings(
            dailyRateMinor: 130000,
            revenuePercent: 0,
            advanceDay: 30,
            salaryDay: 15,
          ),
          shifts: shifts,
          payouts: [advance],
        );

        final salaryStatus = finance.calculatePayoutStatus(
          state: state,
          now: DateTime(2026, 10, 5),
        );
        expect(salaryStatus.nextKind, PayoutKind.salary);
        // September remaining 70% (1,300,000 - 390,000) + Oct 1-15 shifts.
        expect(salaryStatus.estimatedNextPayoutMinor, 1170000);

        final advanceStatus = finance.calculatePayoutStatus(
          state: state.copyWith(
            payment: const PaymentSettings(
              dailyRateMinor: 130000,
              revenuePercent: 0,
              advanceDay: 30,
              salaryDay: 15,
              advancePercent: 40,
            ),
            payouts: [advance.copyWith(date: DateTime(2026, 9, 30))],
          ),
          now: DateTime(2026, 10, 20),
        );
        expect(advanceStatus.nextKind, PayoutKind.advance);
        // 40% of the three October shifts completed by Oct 20, excluding Oct 25.
        expect(advanceStatus.estimatedNextPayoutMinor, 156000);
      },
    );
  });
}

Shift _shiftWithEarnings(DateTime date, int earningsMinor) => Shift(
  id: date.toIso8601String(),
  date: date,
  kind: ShiftKind.scheduled,
  actualStart: date.add(const Duration(hours: 9)),
  actualEnd: date.add(const Duration(hours: 21)),
  colleagueIds: const [],
  revenueMinor: 0,
  earningsMinor: earningsMinor,
  comment: '',
  createdAt: date,
  updatedAt: date,
);

Shift _shift(DateTime date, int revenueMinor) => Shift(
  id: date.toIso8601String(),
  date: date,
  kind: ShiftKind.scheduled,
  actualStart: date.add(const Duration(hours: 9)),
  actualEnd: date.add(const Duration(hours: 21)),
  colleagueIds: const [],
  revenueMinor: revenueMinor,
  earningsMinor: 0,
  comment: '',
  createdAt: date,
  updatedAt: date,
);
