import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:uuid/uuid.dart';

import '../data/app_repository.dart';
import '../data/sqlite_app_repository.dart';
import '../domain/finance_service.dart';
import '../domain/models.dart';

final appRepositoryProvider = Provider<AppRepository>(
  (ref) => SqliteAppRepository(),
);

final appControllerProvider =
    StateNotifierProvider<AppController, AsyncValue<AppState>>(
      (ref) => AppController(ref.read(appRepositoryProvider)),
    );

class AppController extends StateNotifier<AsyncValue<AppState>> {
  AppController(this._repository) : super(const AsyncValue.loading()) {
    initialize();
  }

  final AppRepository _repository;
  final _uuid = const Uuid();
  final _finance = const FinanceService();

  Future<void> initialize() async {
    try {
      state = AsyncValue.data(await _repository.load());
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  AppState get _data => state.requireValue;

  Future<void> _save(AppState value) async {
    final previousState = state;
    state = AsyncValue.data(value);
    try {
      await _repository.save(value);
    } catch (_) {
      state = previousState;
    }
  }

  Future<void> completeOnboarding({
    required AppLanguage language,
    required Schedule schedule,
    required PaymentSettings payment,
    required List<String> colleagueNames,
  }) async {
    final now = DateTime.now();
    final colors = <int>[
      0xFF2F80ED,
      0xFF9B51E0,
      0xFFF2994A,
      0xFF27AE60,
      0xFFEB5757,
    ];
    final colleagues = colleagueNames
        .where((name) => name.trim().isNotEmpty)
        .toList()
        .asMap()
        .entries
        .map((entry) {
          return Colleague(
            id: _uuid.v4(),
            name: entry.value.trim(),
            colorValue: colors[entry.key % colors.length],
            createdAt: now,
            updatedAt: now,
          );
        })
        .toList();
    await _save(
      _data.copyWith(
        settings: _data.settings.copyWith(
          language: language,
          onboardingComplete: true,
        ),
        schedule: schedule,
        payment: payment,
        colleagues: colleagues,
      ),
    );
  }

  Future<void> updateSettings(AppSettings settings) async {
    final restoreAdaptiveEarnings =
        _data.settings.adaptiveSalaryEnabled && !settings.adaptiveSalaryEnabled;
    if (!restoreAdaptiveEarnings) {
      await _save(_data.copyWith(settings: settings));
      return;
    }

    final now = DateTime.now();
    final restoredShifts = _data.shifts.map((shift) {
      final original = shift.adaptiveEarningsOriginalMinor;
      final revenue =
          (shift.revenueMinor *
                  (shift.customRevenuePercent ?? _data.payment.revenuePercent) /
                  100)
              .round();
      final normalEarnings = _data.payment.dailyRateMinor + revenue;
      if (original == null) {
        // Older app versions did not retain pre-adjustment values. Recover
        // regular shifts from the configured rate so legacy inflated amounts
        // are removed as adaptive salary is switched off.
        if (shift.manualEarningsMinor != null ||
            shift.customDailyRateMinor != null) {
          return shift;
        }
        if (shift.earningsMinor <= normalEarnings) return shift;
        return shift.copyWith(earningsMinor: normalEarnings, updatedAt: now);
      }
      return shift.copyWith(
        earningsMinor: original > normalEarnings ? normalEarnings : original,
        updatedAt: now,
        clearAdaptiveEarningsOriginal: true,
      );
    }).toList();
    await _save(_data.copyWith(settings: settings, shifts: restoredShifts));
  }

  Future<void> updateSchedule(Schedule schedule) =>
      _save(_data.copyWith(schedule: schedule));

  Future<void> updatePayment(PaymentSettings payment) =>
      _save(_data.copyWith(payment: payment));

  Future<void> addColleague(String name) async {
    if (name.trim().isEmpty) return;
    final now = DateTime.now();
    const colors = <int>[
      0xFF2F80ED,
      0xFF9B51E0,
      0xFFF2994A,
      0xFF27AE60,
      0xFFEB5757,
    ];
    final colleague = Colleague(
      id: _uuid.v4(),
      name: name.trim(),
      colorValue: colors[_data.colleagues.length % colors.length],
      createdAt: now,
      updatedAt: now,
    );
    await _save(_data.copyWith(colleagues: [..._data.colleagues, colleague]));
  }

  Future<void> deleteColleague(String id) async {
    await _save(
      _data.copyWith(
        colleagues: _data.colleagues.where((item) => item.id != id).toList(),
        shifts: _data.shifts
            .map(
              (shift) => shift.copyWith(
                colleagueIds: shift.colleagueIds
                    .where((colleagueId) => colleagueId != id)
                    .toList(),
              ),
            )
            .toList(),
      ),
    );
  }

  Future<void> saveShift({
    String? id,
    required DateTime date,
    required ShiftKind kind,
    required DateTime start,
    required DateTime end,
    required List<String> colleagueIds,
    required int revenueMinor,
    required String comment,
    double? customRevenuePercent,
    int? customDailyRateMinor,
    int? manualEarningsMinor,
  }) async {
    final now = DateTime.now();
    final shift = Shift(
      id: id ?? _uuid.v4(),
      date: DateTime(date.year, date.month, date.day),
      kind: kind,
      actualStart: start,
      actualEnd: end.isBefore(start) ? end.add(const Duration(days: 1)) : end,
      colleagueIds: colleagueIds,
      revenueMinor: revenueMinor,
      earningsMinor: _finance.earnings(
        revenueMinor: revenueMinor,
        payment: _data.payment,
        customRevenuePercent: customRevenuePercent,
        customDailyRateMinor: customDailyRateMinor,
        manualEarningsMinor: manualEarningsMinor,
      ),
      comment: comment.trim(),
      customRevenuePercent: customRevenuePercent,
      customDailyRateMinor: customDailyRateMinor,
      manualEarningsMinor: manualEarningsMinor,
      createdAt: id == null
          ? now
          : _data.shifts
                .firstWhere(
                  (item) => item.id == id,
                  orElse: () => Shift(
                    id: '',
                    date: now,
                    kind: ShiftKind.scheduled,
                    actualStart: now,
                    actualEnd: now,
                    colleagueIds: const [],
                    revenueMinor: 0,
                    earningsMinor: 0,
                    comment: '',
                    createdAt: now,
                    updatedAt: now,
                  ),
                )
                .createdAt,
      updatedAt: now,
    );
    final others = _data.shifts.where((item) => item.id != shift.id).toList();
    await _save(
      _data.copyWith(
        shifts: [...others, shift]..sort((a, b) => b.date.compareTo(a.date)),
      ),
    );
  }

  Future<void> deleteShift(String id) => _save(
    _data.copyWith(
      shifts: _data.shifts.where((item) => item.id != id).toList(),
    ),
  );

  Future<void> savePayout({
    String? id,
    required DateTime date,
    required PayoutKind kind,
    required int amountMinor,
    required String comment,
  }) async {
    final now = DateTime.now();
    final payout = Payout(
      id: id ?? _uuid.v4(),
      date: DateTime(date.year, date.month, date.day),
      kind: kind,
      amountMinor: amountMinor,
      comment: comment.trim(),
      createdAt: id == null
          ? now
          : _data.payouts
                .firstWhere(
                  (item) => item.id == id,
                  orElse: () => Payout(
                    id: '',
                    date: now,
                    kind: PayoutKind.advance,
                    amountMinor: 0,
                    comment: '',
                    createdAt: now,
                    updatedAt: now,
                  ),
                )
                .createdAt,
      updatedAt: now,
    );
    final others = _data.payouts.where((item) => item.id != payout.id).toList();
    await _save(
      _data.copyWith(
        payouts: [...others, payout]..sort((a, b) => b.date.compareTo(a.date)),
      ),
    );
  }

  /// Reconciles regular shifts in the period ending at [payout] to the
  /// earnings implied by the actual payout. Repeating the operation is safe:
  /// the target earnings and period membership do not depend on the current
  /// calculated shift amounts.
  /// Returns the new base rate (minor units) for UI display.
  Future<int> recalculateShiftsForPayout({
    required Payout payout,
    required int actualAmountMinor,
  }) async {
    final allPayouts = [..._data.payouts]
      ..sort((a, b) => a.date.compareTo(b.date));
    final idx = allPayouts.indexWhere((p) => p.id == payout.id);
    final prevPayout = idx > 0 ? allPayouts[idx - 1] : null;
    final periodMonth = payout.kind == PayoutKind.advance
        ? _finance.advanceAccrualMonth(
            payout.date,
            advanceDay: _data.payment.advanceDay,
            salaryDay: _data.payment.salaryDay,
          )
        : (prevPayout == null
              ? DateTime(payout.date.year, payout.date.month, 1)
              : DateTime(
                  prevPayout.date.year,
                  prevPayout.date.month,
                  prevPayout.date.day,
                ));
    final periodStart = payout.kind == PayoutKind.advance
        ? DateTime(
            periodMonth.year,
            periodMonth.month,
            1,
          ).subtract(const Duration(days: 1))
        : periodMonth;
    final periodEnd = payout.kind == PayoutKind.advance
        ? DateTime(periodMonth.year, periodMonth.month + 1, 0)
        : DateTime(payout.date.year, payout.date.month, payout.date.day);

    final periodShifts = _data.shifts.where((s) {
      final shiftDate = DateTime(s.date.year, s.date.month, s.date.day);
      return shiftDate.isAfter(periodStart) && !shiftDate.isAfter(periodEnd);
    }).toList();
    final excluded = periodShifts
        .where(
          (s) =>
              s.manualEarningsMinor != null || s.customDailyRateMinor != null,
        )
        .toList();
    final included = periodShifts
        .where(
          (s) =>
              s.manualEarningsMinor == null && s.customDailyRateMinor == null,
        )
        .toList();

    if (included.isEmpty) return 0;

    final revenuePercent = _data.payment.revenuePercent;
    final totalRevenue = included.fold<int>(
      0,
      (sum, s) => sum + (s.revenueMinor * revenuePercent / 100).round(),
    );
    final excludedTotal = excluded.fold<int>(
      0,
      (sum, s) => sum + s.earningsMinor,
    );

    // Implied total period earnings based on payout type
    final int impliedTotalMinor;
    if (payout.kind == PayoutKind.advance) {
      // The entered advance amount represents the configured share of the
      // month's total earnings.
      final share = _data.payment.advancePercent / 100;
      impliedTotalMinor = share <= 0
          ? 0
          : (actualAmountMinor / share).round();
    } else {
      // Salary = total − advances → total = salary + advances in period
      final advancesInPeriod = _data.payouts
          .where((p) {
            if (p.kind != PayoutKind.advance || p.id == payout.id) return false;
            final d = DateTime(p.date.year, p.date.month, p.date.day);
            return d.isAfter(periodStart) && !d.isAfter(periodEnd);
          })
          .fold<int>(0, (sum, p) => sum + p.amountMinor);
      impliedTotalMinor = actualAmountMinor + advancesInPeriod;
    }

    final adjustedTotal = impliedTotalMinor - excludedTotal - totalRevenue;
    if (adjustedTotal <= 0) return 0;
    final reconciledPeriodRate = (adjustedTotal / included.length).round();
    final now = DateTime.now();
    final updatedIncluded = included.map((s) {
      final rev = (s.revenueMinor * revenuePercent / 100).round();
      // A reconciliation may lower an erroneous historical rate, but must
      // never inflate shifts beyond the configured daily rate.
      final configuredRate =
          s.customDailyRateMinor ?? _data.payment.dailyRateMinor;
      final reconciledRate = reconciledPeriodRate.clamp(0, configuredRate);
      return s.copyWith(
        earningsMinor: reconciledRate + rev,
        updatedAt: now,
        adaptiveEarningsOriginalMinor:
            s.adaptiveEarningsOriginalMinor ?? s.earningsMinor,
      );
    }).toList();
    final updatedById = {for (final shift in updatedIncluded) shift.id: shift};
    final updatedShifts = _data.shifts
        .map((shift) => updatedById[shift.id] ?? shift)
        .toList();
    await _save(
      _data.copyWith(
        shifts: updatedShifts..sort((a, b) => b.date.compareTo(a.date)),
      ),
    );
    return (adjustedTotal / included.length).round().clamp(
      0,
      _data.payment.dailyRateMinor,
    );
  }

  Future<void> deletePayout(String id) => _save(
    _data.copyWith(
      payouts: _data.payouts.where((item) => item.id != id).toList(),
    ),
  );

  Future<void> importBackup(String source) async {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Backup must contain an object.');
    }
    final parsed = AppState.fromJson(decoded);
    await _repository.replace(parsed);
    state = AsyncValue.data(parsed);
  }

  String exportBackup() => _data.toBackupJson();
}
