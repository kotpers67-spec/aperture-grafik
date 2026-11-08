import 'dart:convert';

enum AppLanguage { russian, english }

enum Currency { rub }

enum AppThemeMode {
  standard,
  laboratory,
  aperture,
  chamber,
  ocean,
  forest,
  sakura,
  sunset,
  slate,
}

/// Experimental full design language overrides (layered on top of AppThemeMode).
enum AppDesignStyle {
  none,
  glass,
  neon,
  minimal,
  neomorphic,
  editorial,
  aurora,
}

enum ScheduleType { threeThree, twoTwo, fiveTwo, weekdays }

enum ShiftKind { scheduled, extra }

enum PayoutKind { advance, salary }

enum AdvanceCalculationMode { percent, shiftsWorked, fixedAmount, hourly }

extension SafeEnumByName<T extends Enum> on Iterable<T> {
  T byNameOr(String? name, T fallback) {
    if (name == null) return fallback;
    for (final value in this) {
      if (value.name == name) return value;
    }
    return fallback;
  }
}

class WorkTime {
  const WorkTime(this.hour, this.minute);

  final int hour;
  final int minute;

  int get minutesSinceMidnight => hour * 60 + minute;

  String format() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {'hour': hour, 'minute': minute};

  factory WorkTime.fromJson(Map<String, dynamic> json) => WorkTime(
    (json['hour'] as num?)?.toInt() ?? 9,
    (json['minute'] as num?)?.toInt() ?? 0,
  );
}

class AppSettings {
  const AppSettings({
    required this.language,
    required this.currency,
    required this.themeMode,
    required this.onboardingComplete,
    required this.notificationsEnabled,
    this.payoutNotificationsEnabled = true,
    this.hasRatedProject = false,
    this.adaptiveSalaryEnabled = true,
    this.designStyle = AppDesignStyle.none,
    this.shiftAnimationsEnabled = true,
  });

  final AppLanguage language;
  final Currency currency;
  final AppThemeMode themeMode;
  final bool onboardingComplete;
  final bool notificationsEnabled;
  final bool payoutNotificationsEnabled;
  final bool hasRatedProject;
  final bool adaptiveSalaryEnabled;
  final AppDesignStyle designStyle;
  final bool shiftAnimationsEnabled;

  AppSettings copyWith({
    AppLanguage? language,
    Currency? currency,
    AppThemeMode? themeMode,
    bool? onboardingComplete,
    bool? notificationsEnabled,
    bool? payoutNotificationsEnabled,
    bool? hasRatedProject,
    bool? adaptiveSalaryEnabled,
    AppDesignStyle? designStyle,
    bool? shiftAnimationsEnabled,
  }) => AppSettings(
    language: language ?? this.language,
    currency: currency ?? this.currency,
    themeMode: themeMode ?? this.themeMode,
    onboardingComplete: onboardingComplete ?? this.onboardingComplete,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    payoutNotificationsEnabled:
        payoutNotificationsEnabled ?? this.payoutNotificationsEnabled,
    hasRatedProject: hasRatedProject ?? this.hasRatedProject,
    adaptiveSalaryEnabled: adaptiveSalaryEnabled ?? this.adaptiveSalaryEnabled,
    designStyle: designStyle ?? this.designStyle,
    shiftAnimationsEnabled:
        shiftAnimationsEnabled ?? this.shiftAnimationsEnabled,
  );

  Map<String, dynamic> toJson() => {
    'language': language.name,
    'currency': currency.name,
    'themeMode': themeMode.name,
    'onboardingComplete': onboardingComplete,
    'notificationsEnabled': notificationsEnabled,
    'payoutNotificationsEnabled': payoutNotificationsEnabled,
    'hasRatedProject': hasRatedProject,
    'adaptiveSalaryEnabled': adaptiveSalaryEnabled,
    'designStyle': designStyle.name,
    'shiftAnimationsEnabled': shiftAnimationsEnabled,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      language: AppLanguage.values.byNameOr(
        json['language'] as String?,
        AppLanguage.russian,
      ),
      // Backups created before RUB-only mode may contain "usd". Keep them
      // readable while normalising all monetary values to the supported currency.
      currency: Currency.rub,
      themeMode: AppThemeMode.values.byNameOr(
        json['themeMode'] as String?,
        AppThemeMode.standard,
      ),
      onboardingComplete: json['onboardingComplete'] as bool? ?? false,
      notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
      payoutNotificationsEnabled:
          json['payoutNotificationsEnabled'] as bool? ?? true,
      hasRatedProject: json['hasRatedProject'] as bool? ?? false,
      adaptiveSalaryEnabled: json['adaptiveSalaryEnabled'] as bool? ?? true,
      designStyle: AppDesignStyle.values.byNameOr(
        json['designStyle'] as String?,
        AppDesignStyle.none,
      ),
      shiftAnimationsEnabled: json['shiftAnimationsEnabled'] as bool? ?? true,
    );
  }
}

class Schedule {
  const Schedule({
    required this.type,
    required this.anchorDate,
    required this.weekdays,
    required this.start,
    required this.end,
  });

  final ScheduleType type;
  final DateTime anchorDate;
  final Set<int> weekdays;
  final WorkTime start;
  final WorkTime end;

  Schedule copyWith({
    ScheduleType? type,
    DateTime? anchorDate,
    Set<int>? weekdays,
    WorkTime? start,
    WorkTime? end,
  }) => Schedule(
    type: type ?? this.type,
    anchorDate: anchorDate ?? this.anchorDate,
    weekdays: weekdays ?? this.weekdays,
    start: start ?? this.start,
    end: end ?? this.end,
  );

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'anchorDate': anchorDate.toIso8601String(),
    'weekdays': weekdays.toList(),
    'start': start.toJson(),
    'end': end.toJson(),
  };

  factory Schedule.fromJson(Map<String, dynamic> json) => Schedule(
    type: ScheduleType.values.byNameOr(
      json['type'] as String?,
      ScheduleType.twoTwo,
    ),
    anchorDate:
        DateTime.tryParse(json['anchorDate'] as String? ?? '') ??
        DateTime.now(),
    weekdays: ((json['weekdays'] as List<dynamic>?) ?? const <dynamic>[])
        .map((value) => (value as num).toInt())
        .toSet(),
    start: WorkTime.fromJson(
      Map<String, dynamic>.from(json['start'] as Map? ?? const {}),
    ),
    end: WorkTime.fromJson(
      Map<String, dynamic>.from(json['end'] as Map? ?? const {}),
    ),
  );
}

class PaymentSettings {
  const PaymentSettings({
    required this.dailyRateMinor,
    required this.revenuePercent,
    required this.advanceDay,
    required this.salaryDay,
    this.advancePercent = 30,
    this.trackRevenue = true,
    this.advanceMode = AdvanceCalculationMode.percent,
    this.fixedAdvanceMinor = 0,
    this.hourlyRateMinor = 0,
  });

  final int dailyRateMinor;
  final double revenuePercent;
  final int advanceDay;
  final int salaryDay;
  final int advancePercent;
  final bool trackRevenue;
  final AdvanceCalculationMode advanceMode;
  final int fixedAdvanceMinor;
  final int hourlyRateMinor;

  int get salaryPercent => 100 - advancePercent;

  PaymentSettings copyWith({
    int? dailyRateMinor,
    double? revenuePercent,
    int? advanceDay,
    int? salaryDay,
    int? advancePercent,
    bool? trackRevenue,
    AdvanceCalculationMode? advanceMode,
    int? fixedAdvanceMinor,
    int? hourlyRateMinor,
  }) => PaymentSettings(
    dailyRateMinor: dailyRateMinor ?? this.dailyRateMinor,
    revenuePercent: revenuePercent ?? this.revenuePercent,
    advanceDay: advanceDay ?? this.advanceDay,
    salaryDay: salaryDay ?? this.salaryDay,
    advancePercent: advancePercent ?? this.advancePercent,
    trackRevenue: trackRevenue ?? this.trackRevenue,
    advanceMode: advanceMode ?? this.advanceMode,
    fixedAdvanceMinor: fixedAdvanceMinor ?? this.fixedAdvanceMinor,
    hourlyRateMinor: hourlyRateMinor ?? this.hourlyRateMinor,
  );

  Map<String, dynamic> toJson() => {
    'dailyRateMinor': dailyRateMinor,
    'revenuePercent': revenuePercent,
    'advanceDay': advanceDay,
    'salaryDay': salaryDay,
    'advancePercent': advancePercent,
    'trackRevenue': trackRevenue,
    'advanceMode': advanceMode.name,
    'fixedAdvanceMinor': fixedAdvanceMinor,
    'hourlyRateMinor': hourlyRateMinor,
  };

  factory PaymentSettings.fromJson(Map<String, dynamic> json) =>
      PaymentSettings(
        dailyRateMinor: (json['dailyRateMinor'] as num?)?.toInt() ?? 300000,
        revenuePercent: (json['revenuePercent'] as num?)?.toDouble() ?? 5,
        advanceDay: (json['advanceDay'] as num?)?.toInt() ?? 15,
        salaryDay: (json['salaryDay'] as num?)?.toInt() ?? 30,
        advancePercent: ((json['advancePercent'] as num?)?.toInt() ?? 30).clamp(
          0,
          100,
        ),
        trackRevenue: json['trackRevenue'] as bool? ?? true,
        advanceMode: AdvanceCalculationMode.values.byNameOr(
          json['advanceMode'] as String?,
          AdvanceCalculationMode.percent,
        ),
        fixedAdvanceMinor: (json['fixedAdvanceMinor'] as num?)?.toInt() ?? 0,
        hourlyRateMinor: (json['hourlyRateMinor'] as num?)?.toInt() ?? 0,
      );
}

class Colleague {
  const Colleague({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final int colorValue;
  final DateTime createdAt;
  final DateTime updatedAt;

  Colleague copyWith({String? name, int? colorValue, DateTime? updatedAt}) =>
      Colleague(
        id: id,
        name: name ?? this.name,
        colorValue: colorValue ?? this.colorValue,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'colorValue': colorValue,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Colleague.fromJson(Map<String, dynamic> json) => Colleague(
    id: json['id'] as String,
    name: json['name'] as String,
    colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFF2F80ED,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );
}

class Shift {
  const Shift({
    required this.id,
    required this.date,
    required this.kind,
    required this.actualStart,
    required this.actualEnd,
    required this.colleagueIds,
    required this.revenueMinor,
    required this.earningsMinor,
    required this.comment,
    required this.createdAt,
    required this.updatedAt,
    this.customRevenuePercent,
    this.customDailyRateMinor,
    this.manualEarningsMinor,
    this.adaptiveEarningsOriginalMinor,
  });

  final String id;
  final DateTime date;
  final ShiftKind kind;
  final DateTime actualStart;
  final DateTime actualEnd;
  final List<String> colleagueIds;
  final int revenueMinor;
  final int earningsMinor;
  final String comment;
  final DateTime createdAt;
  final DateTime updatedAt;
  final double? customRevenuePercent;
  final int? customDailyRateMinor;
  final int? manualEarningsMinor;

  /// Original earnings captured before an adaptive payout recalculation.
  final int? adaptiveEarningsOriginalMinor;

  double get durationHours {
    final minutes = actualEnd.difference(actualStart).inMinutes;
    return minutes < 0 ? 0.0 : minutes / 60.0;
  }

  Shift copyWith({
    DateTime? date,
    ShiftKind? kind,
    DateTime? actualStart,
    DateTime? actualEnd,
    List<String>? colleagueIds,
    int? revenueMinor,
    int? earningsMinor,
    String? comment,
    DateTime? updatedAt,
    double? customRevenuePercent,
    int? customDailyRateMinor,
    int? manualEarningsMinor,
    bool clearAdaptiveEarningsOriginal = false,
    int? adaptiveEarningsOriginalMinor,
  }) => Shift(
    id: id,
    date: date ?? this.date,
    kind: kind ?? this.kind,
    actualStart: actualStart ?? this.actualStart,
    actualEnd: actualEnd ?? this.actualEnd,
    colleagueIds: colleagueIds ?? this.colleagueIds,
    revenueMinor: revenueMinor ?? this.revenueMinor,
    earningsMinor: earningsMinor ?? this.earningsMinor,
    comment: comment ?? this.comment,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    customRevenuePercent: customRevenuePercent ?? this.customRevenuePercent,
    customDailyRateMinor: customDailyRateMinor ?? this.customDailyRateMinor,
    manualEarningsMinor: manualEarningsMinor ?? this.manualEarningsMinor,
    adaptiveEarningsOriginalMinor: clearAdaptiveEarningsOriginal
        ? null
        : adaptiveEarningsOriginalMinor ?? this.adaptiveEarningsOriginalMinor,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'kind': kind.name,
    'actualStart': actualStart.toIso8601String(),
    'actualEnd': actualEnd.toIso8601String(),
    'colleagueIds': colleagueIds,
    'revenueMinor': revenueMinor,
    'earningsMinor': earningsMinor,
    'comment': comment,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    if (customRevenuePercent != null)
      'customRevenuePercent': customRevenuePercent,
    if (customDailyRateMinor != null)
      'customDailyRateMinor': customDailyRateMinor,
    if (manualEarningsMinor != null) 'manualEarningsMinor': manualEarningsMinor,
    if (adaptiveEarningsOriginalMinor != null)
      'adaptiveEarningsOriginalMinor': adaptiveEarningsOriginalMinor,
  };

  factory Shift.fromJson(Map<String, dynamic> json) => Shift(
    id: json['id'] as String,
    date: DateTime.parse(json['date'] as String),
    kind: ShiftKind.values.byNameOr(
      json['kind'] as String?,
      ShiftKind.scheduled,
    ),
    actualStart: DateTime.parse(json['actualStart'] as String),
    actualEnd: DateTime.parse(json['actualEnd'] as String),
    colleagueIds: List<String>.from(
      json['colleagueIds'] as List<dynamic>? ?? const [],
    ),
    revenueMinor: (json['revenueMinor'] as num?)?.toInt() ?? 0,
    earningsMinor: (json['earningsMinor'] as num?)?.toInt() ?? 0,
    comment: json['comment'] as String? ?? '',
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    customRevenuePercent: (json['customRevenuePercent'] as num?)?.toDouble(),
    customDailyRateMinor: (json['customDailyRateMinor'] as num?)?.toInt(),
    manualEarningsMinor: (json['manualEarningsMinor'] as num?)?.toInt(),
    adaptiveEarningsOriginalMinor:
        (json['adaptiveEarningsOriginalMinor'] as num?)?.toInt(),
  );
}

class Payout {
  const Payout({
    required this.id,
    required this.date,
    required this.kind,
    required this.amountMinor,
    required this.comment,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final DateTime date;
  final PayoutKind kind;
  final int amountMinor;
  final String comment;
  final DateTime createdAt;
  final DateTime updatedAt;

  Payout copyWith({
    DateTime? date,
    PayoutKind? kind,
    int? amountMinor,
    String? comment,
    DateTime? updatedAt,
  }) => Payout(
    id: id,
    date: date ?? this.date,
    kind: kind ?? this.kind,
    amountMinor: amountMinor ?? this.amountMinor,
    comment: comment ?? this.comment,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'kind': kind.name,
    'amountMinor': amountMinor,
    'comment': comment,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Payout.fromJson(Map<String, dynamic> json) => Payout(
    id: json['id'] as String,
    date: DateTime.parse(json['date'] as String),
    kind: PayoutKind.values.byNameOr(
      json['kind'] as String?,
      PayoutKind.advance,
    ),
    amountMinor: (json['amountMinor'] as num?)?.toInt() ?? 0,
    comment: json['comment'] as String? ?? '',
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );
}

class AppState {
  const AppState({
    required this.settings,
    required this.schedule,
    required this.payment,
    required this.colleagues,
    required this.shifts,
    this.payouts = const [],
  });

  final AppSettings settings;
  final Schedule schedule;
  final PaymentSettings payment;
  final List<Colleague> colleagues;
  final List<Shift> shifts;
  final List<Payout> payouts;

  factory AppState.initial() {
    final now = DateTime.now();
    return AppState(
      settings: AppSettings(
        language: AppLanguage.russian,
        currency: Currency.rub,
        themeMode: AppThemeMode.standard,
        onboardingComplete: false,
        notificationsEnabled: true,
      ),
      schedule: Schedule(
        type: ScheduleType.twoTwo,
        anchorDate: DateTime(now.year, now.month, now.day),
        weekdays: const {
          DateTime.monday,
          DateTime.tuesday,
          DateTime.wednesday,
          DateTime.thursday,
          DateTime.friday,
        },
        start: const WorkTime(9, 0),
        end: const WorkTime(21, 0),
      ),
      payment: const PaymentSettings(
        dailyRateMinor: 300000,
        revenuePercent: 5,
        advanceDay: 30,
        salaryDay: 15,
        advancePercent: 30,
      ),
      colleagues: const [],
      shifts: const [],
      payouts: const [],
    );
  }

  AppState copyWith({
    AppSettings? settings,
    Schedule? schedule,
    PaymentSettings? payment,
    List<Colleague>? colleagues,
    List<Shift>? shifts,
    List<Payout>? payouts,
  }) => AppState(
    settings: settings ?? this.settings,
    schedule: schedule ?? this.schedule,
    payment: payment ?? this.payment,
    colleagues: colleagues ?? this.colleagues,
    shifts: shifts ?? this.shifts,
    payouts: payouts ?? this.payouts,
  );

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'settings': settings.toJson(),
    'schedule': schedule.toJson(),
    'payment': payment.toJson(),
    'colleagues': colleagues.map((item) => item.toJson()).toList(),
    'shifts': shifts.map((item) => item.toJson()).toList(),
    'payouts': payouts.map((item) => item.toJson()).toList(),
  };

  String toBackupJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory AppState.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported backup version.');
    }
    return AppState(
      settings: AppSettings.fromJson(
        Map<String, dynamic>.from(json['settings'] as Map),
      ),
      schedule: Schedule.fromJson(
        Map<String, dynamic>.from(json['schedule'] as Map),
      ),
      payment: PaymentSettings.fromJson(
        Map<String, dynamic>.from(json['payment'] as Map),
      ),
      colleagues: (json['colleagues'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                Colleague.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
      shifts: (json['shifts'] as List<dynamic>? ?? const [])
          .map((item) => Shift.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
      payouts: (json['payouts'] as List<dynamic>? ?? const [])
          .map(
            (item) => Payout.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
    );
  }
}
