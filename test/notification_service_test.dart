import 'package:aperture_grafik/core/notifications/notification_service.dart';
import 'package:aperture_grafik/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationService - Payout Events', () {
    late AppState baseState;

    setUp(() {
      baseState = AppState(
        settings: const AppSettings(
          language: AppLanguage.russian,
          currency: Currency.rub,
          themeMode: AppThemeMode.standard,
          onboardingComplete: true,
          notificationsEnabled: true,
          payoutNotificationsEnabled: true,
        ),
        schedule: Schedule(
          type: ScheduleType.twoTwo,
          anchorDate: DateTime(2026, 1, 1),
          weekdays: const {},
          start: const WorkTime(9, 0),
          end: const WorkTime(21, 0),
        ),
        payment: const PaymentSettings(
          dailyRateMinor: 300000,
          revenuePercent: 5,
          advanceDay: 15,
          salaryDay: 30,
        ),
        colleagues: const [],
        shifts: const [],
        payouts: const [],
      );
    });

    test('resolveMonthDay clamps days correctly for leap and standard months', () {
      expect(
        NotificationService.resolveMonthDay(2026, 2, 30),
        DateTime(2026, 2, 28),
      );
      expect(
        NotificationService.resolveMonthDay(2024, 2, 30),
        DateTime(2024, 2, 29),
      );
      expect(
        NotificationService.resolveMonthDay(2026, 4, 31),
        DateTime(2026, 4, 30),
      );
      expect(
        NotificationService.resolveMonthDay(2026, 5, 15),
        DateTime(2026, 5, 15),
      );
    });

    test('generates advance eve at 18:00 and advance day at 10:00 when in future', () {
      final now = DateTime(2026, 5, 10, 12, 0);
      final events = NotificationService.computeUpcomingPayoutEvents(
        baseState,
        now,
        count: 10,
      );

      // Advance for May 2026 is on 15th
      final advEve = events.firstWhere(
        (e) =>
            e.kind == PayoutKind.advance &&
            e.type == PayoutNotificationType.eve &&
            e.payoutDate.month == 5,
      );
      expect(advEve.triggerTime, DateTime(2026, 5, 14, 18, 0));

      final advDay = events.firstWhere(
        (e) =>
            e.kind == PayoutKind.advance &&
            e.type == PayoutNotificationType.dayOf &&
            e.payoutDate.month == 5,
      );
      expect(advDay.triggerTime, DateTime(2026, 5, 15, 10, 0));
    });

    test('generates follow-up reminders at 10:00 for past unrecorded payout', () {
      // Current date is May 16 (day after May 15 advance)
      final now = DateTime(2026, 5, 16, 12, 0);
      final events = NotificationService.computeUpcomingPayoutEvents(
        baseState,
        now,
        count: 10,
      );

      // Follow-up for May 15 advance should fire on May 17, May 18, May 19 at 10:00
      final followUps = events
          .where(
            (e) =>
                e.kind == PayoutKind.advance &&
                e.type == PayoutNotificationType.followUp &&
                e.payoutDate.month == 5,
          )
          .toList();

      expect(followUps.isNotEmpty, isTrue);
      expect(followUps.first.triggerTime, DateTime(2026, 5, 17, 10, 0));
    });

    test('skips events if payout is already recorded in AppState.payouts', () {
      final recordedState = baseState.copyWith(
        payouts: [
          Payout(
            id: 'p1',
            date: DateTime(2026, 5, 15),
            kind: PayoutKind.advance,
            amountMinor: 3000000,
            comment: '',
            createdAt: DateTime(2026, 5, 15),
            updatedAt: DateTime(2026, 5, 15),
          ),
        ],
      );

      final now = DateTime(2026, 5, 10, 12, 0);
      final events = NotificationService.computeUpcomingPayoutEvents(
        recordedState,
        now,
        count: 10,
      );

      final hasMayAdvance = events.any(
        (e) => e.kind == PayoutKind.advance && e.payoutDate.month == 5,
      );
      expect(hasMayAdvance, isFalse);

      // May salary should still be present
      final hasMaySalary = events.any(
        (e) => e.kind == PayoutKind.salary && e.payoutDate.month == 5,
      );
      expect(hasMaySalary, isTrue);
    });
  });
}
