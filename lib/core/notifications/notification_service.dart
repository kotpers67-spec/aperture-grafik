import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../domain/models.dart';
import '../../domain/schedule_service.dart';

enum PayoutNotificationType {
  eve, // 18:00 on the day before
  dayOf, // 10:00 on the payout day
  followUp, // 10:00 on subsequent days if unrecorded
}

class PayoutNotificationEvent {
  const PayoutNotificationEvent({
    required this.kind,
    required this.type,
    required this.payoutDate,
    required this.triggerTime,
    this.daysOverdue = 0,
  });

  final PayoutKind kind;
  final PayoutNotificationType type;
  final DateTime payoutDate;
  final DateTime triggerTime;
  final int daysOverdue;
}

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();
  static const _endNotificationId = 1000;
  static const _firstRepeatNotificationId = 1001;
  static const _repeatReminderCount = 96;

  static const _firstPayoutNotificationId = 2000;
  static const _maxPayoutReminderCount = 48;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final ScheduleService _schedule = const ScheduleService();

  Future<void> initialize() async {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Moscow'));
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
  }

  Future<void> scheduleAll(AppState state) async {
    await scheduleNextEndReminder(state);
    await schedulePayoutReminders(state);
  }

  /// Schedules the end notification and 30-minute reminders for the next two
  /// days. Saving a shift updates [AppState], which cancels the batch; opening
  /// the app with an unfinished shift refreshes the two-day reminder window.
  Future<void> scheduleNextEndReminder(AppState state) async {
    await _cancelShiftReminders();
    if (!state.settings.notificationsEnabled) return;

    final now = DateTime.now();
    final target = _nextIncompleteShiftEnd(state, now);
    if (target == null) return;

    final isRussian = state.settings.language == AppLanguage.russian;
    if (target.isAfter(now)) {
      await _plugin.zonedSchedule(
        _endNotificationId,
        isRussian ? 'Смена закончилась' : 'Shift has ended',
        isRussian
            ? 'Заполните коллег, выручку и комментарий за смену.'
            : 'Add colleagues, revenue, and an optional comment.',
        tz.TZDateTime.from(target, tz.local),
        _notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }

    final firstReminder = target.isAfter(now)
        ? target.add(const Duration(minutes: 30))
        : nextHalfHourAfter(now);
    for (var index = 0; index < _repeatReminderCount; index++) {
      await _plugin.zonedSchedule(
        _firstRepeatNotificationId + index,
        isRussian ? 'Заполните данные о смене' : 'Complete shift details',
        isRussian
            ? 'Напоминание: укажите коллег и выручку за завершённую смену.'
            : 'Reminder: add colleagues and revenue for the finished shift.',
        tz.TZDateTime.from(
          firstReminder.add(Duration(minutes: 30 * index)),
          tz.local,
        ),
        _notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  /// Schedules advance and salary payout notifications for upcoming months.
  /// Fires at 18:00 the day before, 10:00 on the payout day, and subsequent days
  /// at 10:00 until the user records the payout in the app.
  Future<void> schedulePayoutReminders(AppState state) async {
    await _cancelPayoutReminders();
    if (!state.settings.notificationsEnabled ||
        !state.settings.payoutNotificationsEnabled) {
      return;
    }

    final now = DateTime.now();
    final isRussian = state.settings.language == AppLanguage.russian;
    final events = computeUpcomingPayoutEvents(state, now, count: 24);

    for (var i = 0; i < events.length && i < _maxPayoutReminderCount; i++) {
      final event = events[i];
      final title = _eventTitle(event, isRussian);
      final body = _eventBody(event, isRussian, i);

      await _plugin.zonedSchedule(
        _firstPayoutNotificationId + i,
        title,
        body,
        tz.TZDateTime.from(event.triggerTime, tz.local),
        _payoutNotificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  static bool hasRecordedPayout(
    AppState state,
    PayoutKind kind,
    int year,
    int month,
  ) {
    return state.payouts.any(
      (p) =>
          p.kind == kind &&
          p.date.year == year &&
          p.date.month == month,
    );
  }

  static List<PayoutNotificationEvent> computeUpcomingPayoutEvents(
    AppState state,
    DateTime now, {
    int count = 24,
  }) {
    final results = <PayoutNotificationEvent>[];
    final today = DateTime(now.year, now.month, now.day);

    // Look at past 1 month and next 5 months to catch unrecorded past payouts + future ones
    for (var mOffset = -1; mOffset <= 5; mOffset++) {
      var year = now.year;
      var month = now.month + mOffset;
      while (month < 1) {
        year--;
        month += 12;
      }
      while (month > 12) {
        year++;
        month -= 12;
      }

      for (final kind in [PayoutKind.advance, PayoutKind.salary]) {
        // If user already recorded this payout, skip completely!
        if (hasRecordedPayout(state, kind, year, month)) {
          continue;
        }

        final targetDay = kind == PayoutKind.advance
            ? state.payment.advanceDay
            : state.payment.salaryDay;
        final payoutDate = resolveMonthDay(year, month, targetDay);

        // 1. Eve reminder (18:00 day before)
        final eveTrigger = DateTime(
          payoutDate.year,
          payoutDate.month,
          payoutDate.day - 1,
          18,
          0,
        );
        if (eveTrigger.isAfter(now)) {
          results.add(PayoutNotificationEvent(
            kind: kind,
            type: PayoutNotificationType.eve,
            payoutDate: payoutDate,
            triggerTime: eveTrigger,
          ));
        }

        // 2. Day-of reminder (10:00 on payout day)
        final dayOfTrigger = DateTime(
          payoutDate.year,
          payoutDate.month,
          payoutDate.day,
          10,
          0,
        );
        if (dayOfTrigger.isAfter(now)) {
          results.add(PayoutNotificationEvent(
            kind: kind,
            type: PayoutNotificationType.dayOf,
            payoutDate: payoutDate,
            triggerTime: dayOfTrigger,
          ));
        }

        // 3. Follow-up reminders for subsequent days at 10:00 (up to 4 days after)
        for (var dayOffset = 1; dayOffset <= 4; dayOffset++) {
          final followUpDate = payoutDate.add(Duration(days: dayOffset));
          final followUpTrigger = DateTime(
            followUpDate.year,
            followUpDate.month,
            followUpDate.day,
            10,
            0,
          );

          // Only schedule if it's in the future and not unreasonably far
          if (followUpTrigger.isAfter(now) &&
              followUpTrigger.difference(today).inDays <= 180) {
            results.add(PayoutNotificationEvent(
              kind: kind,
              type: PayoutNotificationType.followUp,
              payoutDate: payoutDate,
              triggerTime: followUpTrigger,
              daysOverdue: dayOffset,
            ));
          }
        }
      }
    }

    results.sort((a, b) => a.triggerTime.compareTo(b.triggerTime));
    return results.take(count).toList();
  }

  static DateTime resolveMonthDay(int year, int month, int targetDay) {
    final lastDay = DateTime(year, month + 1, 0).day;
    final clampedDay = targetDay.clamp(1, lastDay);
    return DateTime(year, month, clampedDay);
  }

  static String _eventTitle(PayoutNotificationEvent event, bool isRussian) {
    switch (event.type) {
      case PayoutNotificationType.eve:
        if (event.kind == PayoutKind.advance) {
          return isRussian ? 'Завтра аванс! ⏳' : 'Advance tomorrow! ⏳';
        } else {
          return isRussian ? 'Завтра зарплата! ⏳' : 'Payday tomorrow! ⏳';
        }
      case PayoutNotificationType.dayOf:
        if (event.kind == PayoutKind.advance) {
          return isRussian ? 'День аванса! 💸' : 'Advance payout day! 💸';
        } else {
          return isRussian ? 'День зарплаты! 💰' : 'Salary payout day! 💰';
        }
      case PayoutNotificationType.followUp:
        if (event.kind == PayoutKind.advance) {
          return isRussian
              ? 'Напоминание об авансе ☕'
              : 'Advance reminder ☕';
        } else {
          return isRussian
              ? 'Напоминание о зарплате 💳'
              : 'Salary reminder 💳';
        }
    }
  }

  static String _eventBody(
    PayoutNotificationEvent event,
    bool isRussian,
    int seed,
  ) {
    if (isRussian) {
      switch (event.type) {
        case PayoutNotificationType.eve:
          if (event.kind == PayoutKind.advance) {
            const options = [
              'Завтра день аванса! Скоро пополнение карты, готовься отмечать ☕💸',
              'Завтра аванс! Финансы уже на подходе, проверь свои смены в приложении ✨',
              'Завтра шекели на базе! Приготовься встречать аванс и вкусный кофе ☕',
            ];
            return options[seed % options.length];
          } else {
            const options = [
              'Завтра день зарплаты! Проверь свои смены и готовься к выплате 💳✨',
              'Завтра зарплата! Расчётный период закрывается, скоро шекели на карте ☕💰',
              'Завтра день получки! Загляни в статистику и готовься принимать кэш ✨',
            ];
            return options[seed % options.length];
          }
        case PayoutNotificationType.dayOf:
          if (event.kind == PayoutKind.advance) {
            const options = [
              'Проверь деньги на карте и отметь получение аванса в приложении ☕',
              'Аванс на базе! Карта пополнена? Не забудь зафиксировать аванс в графике ☕✨',
              'Ура, день аванса! Проверь банковский счёт и внеси выплату в приложение 💳',
              'Аванс подъехал! Время проверить баланс и зафиксировать кэш в приложении! ☕💸',
            ];
            return options[seed % options.length];
          } else {
            const options = [
              'Проверь баланс на карте и отметь выплату в приложении 💳✨',
              'Зарплата прилетела! Бариста заслужил свой кэш — проверь счёт и отметь в приложении ☕💸',
              'Финал месяца закрыт! Проверь поступление зарплаты и зафиксируй её в графике 🪙',
              'Деньги на карте! Загляни в баланс и не забудь внести зарплату в приложение! 💳🔥',
            ];
            return options[seed % options.length];
          }
        case PayoutNotificationType.followUp:
          if (event.kind == PayoutKind.advance) {
            const options = [
              'Аванс ещё не отмечен в приложении! Проверь карту и внеси выплату ☕💳',
              'Не забудь зафиксировать получение аванса в Aperture Grafik ✨💸',
              'Напоминание: внеси полученный аванс в график для точной статистики! 📊☕',
            ];
            return options[seed % options.length];
          } else {
            const options = [
              'Зарплата ещё не внесена в приложение! Проверь карту и отметь выплату 💳✨',
              'Не забудь зафиксировать зарплату в Aperture Grafik для верного баланса ☕💰',
              'Напоминание: отметь выплату зарплаты в приложении, чтобы закрыть период! 📊🪙',
            ];
            return options[seed % options.length];
          }
      }
    } else {
      switch (event.type) {
        case PayoutNotificationType.eve:
          if (event.kind == PayoutKind.advance) {
            return 'Advance payout tomorrow! Get ready for the balance boost ☕💸';
          } else {
            return 'Salary payout tomorrow! End of the pay period, get ready 💳✨';
          }
        case PayoutNotificationType.dayOf:
          if (event.kind == PayoutKind.advance) {
            return 'Check your bank card and log the advance in the app ☕';
          } else {
            return 'Check your bank balance and mark the salary in the app 💳✨';
          }
        case PayoutNotificationType.followUp:
          if (event.kind == PayoutKind.advance) {
            return 'Advance not recorded yet! Check your card and log it in the app ☕';
          } else {
            return 'Salary not recorded yet! Check your card and log it in the app 💳';
          }
      }
    }
  }

  Future<void> _cancelShiftReminders() async {
    for (
      var id = _endNotificationId;
      id < _firstRepeatNotificationId + _repeatReminderCount;
      id++
    ) {
      await _plugin.cancel(id);
    }
  }

  Future<void> _cancelPayoutReminders() async {
    for (
      var id = _firstPayoutNotificationId;
      id < _firstPayoutNotificationId + _maxPayoutReminderCount;
      id++
    ) {
      await _plugin.cancel(id);
    }
  }

  DateTime? _nextIncompleteShiftEnd(AppState state, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    for (final day in <DateTime>[
      today,
      today.subtract(const Duration(days: 1)),
    ]) {
      if (_schedule.isWorkDay(state.schedule, day) &&
          !_hasCompletedShift(state, day)) {
        final end = _schedule.endAt(state.schedule, day);
        if (!end.isAfter(now)) return end;
      }
    }

    for (var offset = 0; offset < 370; offset++) {
      final day = today.add(Duration(days: offset));
      if (_schedule.isWorkDay(state.schedule, day) &&
          !_hasCompletedShift(state, day)) {
        return _schedule.endAt(state.schedule, day);
      }
    }
    return null;
  }

  bool _hasCompletedShift(AppState state, DateTime day) => state.shifts.any(
    (shift) =>
        shift.date.year == day.year &&
        shift.date.month == day.month &&
        shift.date.day == day.day,
  );

  static DateTime nextHalfHourAfter(DateTime value) {
    final minute = value.minute < 30 ? 30 : 60;
    return DateTime(value.year, value.month, value.day, value.hour, minute);
  }

  static const _notificationDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'shift_end',
      'Shift end reminders',
      channelDescription: 'Reminders to complete a finished shift',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  static const _payoutNotificationDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'payout_reminders',
      'Payout reminders',
      channelDescription: 'Reminders on advance and salary payout days',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );
}
