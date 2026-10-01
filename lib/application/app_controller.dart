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

  Future<void> updateSettings(AppSettings settings) =>
      _save(_data.copyWith(settings: settings));

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

  /// Recalculates earningsMinor for all "normal" shifts in the payout's period
  /// based on the actual received amount. Excluded: shifts with manualEarningsMinor
  /// or customDailyRateMinor set (those are already custom).
  Future<void> recalculateShiftsForPayout({
    required Payout payout,
    required int actualAmountMinor,
  }) async {
    final allPayouts = [..._data.payouts]
      ..sort((a, b) => a.date.compareTo(b.date));

    // Period: from previous payout date (exclusive) to this payout date (inclusive)
    final idx = allPayouts.indexWhere((p) => p.id == payout.id);
    final prevPayout = idx > 0 ? allPayouts[idx - 1] : null;
    final periodStart = prevPayout != null
        ? DateTime(
            prevPayout.date.year,
            prevPayout.date.month,
            prevPayout.date.day,
          )
        : DateTime(_data.shifts.isEmpty
            ? payout.date.year
            : _data.shifts
                .map((s) => s.date)
                .reduce((a, b) => a.isBefore(b) ? a : b)
                .year,
            1, 0);
    final periodEnd = DateTime(
      payout.date.year,
      payout.date.month,
      payout.date.day,
      23, 59, 59,
    );

    final periodShifts = _data.shifts.where((s) {
      return s.date.isAfter(periodStart) && !s.date.isAfter(periodEnd);
    }).toList();

    // Split: excluded (custom) vs included (normal)
    final excluded = periodShifts
        .where((s) => s.manualEarningsMinor != null || s.customDailyRateMinor != null)
        .toList();
    final included = periodShifts
        .where((s) => s.manualEarningsMinor == null && s.customDailyRateMinor == null)
        .toList();

    if (included.isEmpty) return;

    // Revenue contribution of included shifts (they keep their % from global settings)
    final revenuePercent = _data.payment.revenuePercent;
    final totalRevenue = included.fold<int>(
      0,
      (sum, s) => sum + (s.revenueMinor * revenuePercent / 100).round(),
    );

    // Excluded shifts keep their earnings; subtract from actual to find what
    // the normal shifts must have earned together
    final excludedTotal =
        excluded.fold<int>(0, (sum, s) => sum + s.earningsMinor);
    final adjustedTotal = actualAmountMinor - excludedTotal - totalRevenue;
    if (included.isEmpty) return;
    final newDailyRateMinor = (adjustedTotal / included.length).round();

    final now = DateTime.now();
    final updatedIncluded = included.map((s) {
      final revenueContrib =
          (s.revenueMinor * revenuePercent / 100).round();
      return s.copyWith(
        earningsMinor: newDailyRateMinor + revenueContrib,
        updatedAt: now,
      );
    }).toList();

    final unchanged = _data.shifts
        .where((s) => !periodShifts.any((ps) => ps.id == s.id))
        .toList();

    await _save(
      _data.copyWith(
        shifts: [...unchanged, ...excluded, ...updatedIncluded]
          ..sort((a, b) => b.date.compareTo(a.date)),
      ),
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
