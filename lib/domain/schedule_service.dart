import 'models.dart';

class ScheduleService {
  const ScheduleService();

  DateTime day(DateTime value) => DateTime(value.year, value.month, value.day);

  int _calendarDayNumber(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;

  bool isWorkDay(Schedule schedule, DateTime date) {
    final target = day(date);
    final anchor = day(schedule.anchorDate);
    if (schedule.type == ScheduleType.weekdays) {
      return schedule.weekdays.contains(target.weekday);
    }
    final days = _calendarDayNumber(target) - _calendarDayNumber(anchor);
    final (work, rest) = switch (schedule.type) {
      ScheduleType.threeThree => (3, 3),
      ScheduleType.twoTwo => (2, 2),
      ScheduleType.fiveTwo => (5, 2),
      ScheduleType.weekdays => throw StateError('Handled above'),
    };
    return days % (work + rest) < work;
  }

  DateTime startAt(Schedule schedule, DateTime date) => DateTime(
    date.year,
    date.month,
    date.day,
    schedule.start.hour,
    schedule.start.minute,
  );

  DateTime endAt(Schedule schedule, DateTime date) {
    final end = DateTime(
      date.year,
      date.month,
      date.day,
      schedule.end.hour,
      schedule.end.minute,
    );
    return schedule.end.minutesSinceMidnight <=
            schedule.start.minutesSinceMidnight
        ? DateTime(
            date.year,
            date.month,
            date.day + 1,
            schedule.end.hour,
            schedule.end.minute,
          )
        : end;
  }

  DateTime? nextWorkDay(Schedule schedule, DateTime from) {
    for (var offset = 0; offset < 370; offset++) {
      final candidate = DateTime(from.year, from.month, from.day + offset);
      if (isWorkDay(schedule, candidate)) return candidate;
    }
    return null;
  }
}
