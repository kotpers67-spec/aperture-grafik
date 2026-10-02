import 'package:flutter_test/flutter_test.dart';
import 'package:aperture_grafik/application/app_controller.dart';
import 'package:aperture_grafik/data/app_repository.dart';
import 'package:aperture_grafik/domain/models.dart';

void main() {
  test('save failures restore saved state and notify the UI', () async {
    final initial = _state(shifts: const [], payouts: const []);
    final repository = _FailingMemoryRepository(initial);
    final failures = <Object?>[];
    final controller = AppController(repository, onSaveError: failures.add);
    await controller.initialize();

    await controller.updateSettings(
      controller.state.requireValue.settings.copyWith(
        shiftAnimationsEnabled: false,
      ),
    );

    expect(
      controller.state.requireValue.settings.shiftAnimationsEnabled,
      isTrue,
    );
    expect(failures.whereType<StateError>(), hasLength(1));
  });

  test('a failed older save cannot roll back a newer queued save', () async {
    final initial = _state(shifts: const [], payouts: const []);
    final repository = _FirstSaveFailsRepository(initial);
    final failures = <Object?>[];
    final controller = AppController(repository, onSaveError: failures.add);
    await controller.initialize();

    final firstSave = controller.updateSettings(
      controller.state.requireValue.settings.copyWith(
        shiftAnimationsEnabled: false,
      ),
    );
    final secondSave = controller.updateSettings(
      controller.state.requireValue.settings.copyWith(
        themeMode: AppThemeMode.ocean,
      ),
    );
    await Future.wait([firstSave, secondSave]);

    final savedSettings = controller.state.requireValue.settings;
    expect(savedSettings.shiftAnimationsEnabled, isFalse);
    expect(savedSettings.themeMode, AppThemeMode.ocean);
    expect(repository.value.settings.shiftAnimationsEnabled, isFalse);
    expect(repository.value.settings.themeMode, AppThemeMode.ocean);
    expect(failures.whereType<StateError>(), isEmpty);
  });

  test(
    'advance recalculation applies payout amount and configured 30 percent share',
    () async {
      final before = _shift('before', DateTime(2026, 9, 25), 375000);
      final after = _shift('after', DateTime(2026, 10, 2), 375000);
      final payout = _payout(
        'salary',
        DateTime(2026, 10, 1),
        PayoutKind.advance,
      );
      final repository = _MemoryRepository(
        _state(shifts: [before, after], payouts: [payout]),
      );
      final controller = AppController(repository);
      await controller.initialize();

      final rate = await controller.recalculateShiftsForPayout(
        payout: payout,
        actualAmountMinor: 390000,
      );

      expect(rate, 130000);
      final shifts = controller.state.requireValue.shifts;
      expect(
        shifts.singleWhere((s) => s.id == 'before').earningsMinor,
        1300000,
      );
      expect(shifts.singleWhere((s) => s.id == 'after').earningsMinor, 375000);
    },
  );

  test('repeating a recalculation does not change the result', () async {
    final shifts = List.generate(
      4,
      (index) => _shift('shift-$index', DateTime(2026, 9, 20 + index), 375000),
    );
    final payout = _payout(
      'advance',
      DateTime(2026, 10, 1),
      PayoutKind.advance,
    );
    final repository = _MemoryRepository(
      _state(shifts: shifts, payouts: [payout]),
    );
    final controller = AppController(repository);
    await controller.initialize();

    await controller.recalculateShiftsForPayout(
      payout: payout,
      actualAmountMinor: 390000,
    );
    final firstResult = controller.state.requireValue.shifts
        .map((shift) => shift.earningsMinor)
        .toList();
    await controller.recalculateShiftsForPayout(
      payout: payout,
      actualAmountMinor: 390000,
    );

    expect(
      controller.state.requireValue.shifts
          .map((shift) => shift.earningsMinor)
          .toList(),
      firstResult,
    );
    expect(firstResult, everyElement(325000));
  });

  test(
    'late advance reconciliation uses actual payout for the full accrual month',
    () async {
      final previousDay = _shift('previous-day', DateTime(2026, 9, 17), 242667);
      final previousPayoutDay = _shift(
        'previous-payout',
        DateTime(2026, 9, 18),
        242667,
      );
      final afterPayout = _shift('after-payout', DateTime(2026, 9, 20), 375000);
      final previousPayout = _payout(
        'previous',
        DateTime(2026, 9, 18),
        PayoutKind.salary,
      );
      final payout = _payout(
        'current',
        DateTime(2026, 10, 1),
        PayoutKind.advance,
      );
      final repository = _MemoryRepository(
        _state(
          shifts: [previousDay, previousPayoutDay, afterPayout],
          payouts: [previousPayout, payout],
        ),
      );
      final controller = AppController(repository);
      await controller.initialize();

      final rate = await controller.recalculateShiftsForPayout(
        payout: payout,
        actualAmountMinor: 117000,
      );

      expect(rate, 130000);
      final shifts = controller.state.requireValue.shifts;
      expect(
        shifts.singleWhere((s) => s.id == 'previous-day').earningsMinor,
        130000,
      );
      expect(
        shifts.singleWhere((s) => s.id == 'previous-payout').earningsMinor,
        130000,
      );
      expect(
        shifts.singleWhere((s) => s.id == 'after-payout').earningsMinor,
        130000,
      );
    },
  );

  test(
    'disabling adaptive salary restores shift custom rate and revenue share',
    () async {
      final shift = _shift('adjusted', DateTime(2026, 9, 20), 375000).copyWith(
        customDailyRateMinor: 200000,
        customRevenuePercent: 10,
        revenueMinor: 50000,
      );
      final payout = _payout(
        'advance',
        DateTime(2026, 10, 1),
        PayoutKind.advance,
      );
      final repository = _MemoryRepository(
        _state(shifts: [shift], payouts: [payout]),
      );
      final controller = AppController(repository);
      await controller.initialize();
      await controller.updateSettings(
        controller.state.requireValue.settings.copyWith(
          adaptiveSalaryEnabled: false,
        ),
      );

      expect(controller.state.requireValue.shifts.single.earningsMinor, 205000);
      expect(
        controller
            .state
            .requireValue
            .shifts
            .single
            .adaptiveEarningsOriginalMinor,
        isNull,
      );
    },
  );

  test(
    'disabling adaptive salary restores configured rate after a decrease',
    () async {
      final date = DateTime(2026, 9, 20);
      final shift = _shift(
        'lowered',
        date,
        70000,
      ).copyWith(adaptiveEarningsOriginalMinor: 100000);
      final state = _state(shifts: [shift], payouts: const []);
      final repository = _MemoryRepository(
        state.copyWith(
          settings: state.settings.copyWith(adaptiveSalaryEnabled: true),
        ),
      );
      final controller = AppController(repository);
      await controller.initialize();

      await controller.updateSettings(
        controller.state.requireValue.settings.copyWith(
          adaptiveSalaryEnabled: false,
        ),
      );

      final restored = controller.state.requireValue.shifts.single;
      expect(restored.earningsMinor, 130000);
      expect(restored.adaptiveEarningsOriginalMinor, isNull);
    },
  );

  test(
    'disabling adaptive salary preserves manually entered shift earnings',
    () async {
      final date = DateTime(2026, 9, 20);
      final manual = _shift('manual', date, 210000).copyWith(
        manualEarningsMinor: 210000,
        adaptiveEarningsOriginalMinor: 100000,
      );
      final state = _state(shifts: [manual], payouts: const []);
      final controller = AppController(_MemoryRepository(state));
      await controller.initialize();

      await controller.updateSettings(
        controller.state.requireValue.settings.copyWith(
          adaptiveSalaryEnabled: false,
        ),
      );

      final restored = controller.state.requireValue.shifts.single;
      expect(restored.earningsMinor, 210000);
      expect(restored.adaptiveEarningsOriginalMinor, 100000);
    },
  );
}

Shift _shift(String id, DateTime date, int earningsMinor) => Shift(
  id: id,
  date: date,
  kind: ShiftKind.extra,
  actualStart: date.add(const Duration(hours: 9)),
  actualEnd: date.add(const Duration(hours: 18)),
  colleagueIds: const [],
  revenueMinor: 0,
  earningsMinor: earningsMinor,
  comment: '',
  createdAt: date,
  updatedAt: date,
);

Payout _payout(String id, DateTime date, PayoutKind kind) => Payout(
  id: id,
  date: date,
  kind: kind,
  amountMinor: 450000,
  comment: '',
  createdAt: date,
  updatedAt: date,
);

AppState _state({required List<Shift> shifts, required List<Payout> payouts}) =>
    AppState.initial().copyWith(
      payment: const PaymentSettings(
        dailyRateMinor: 130000,
        revenuePercent: 0,
        advanceDay: 30,
        salaryDay: 15,
      ),
      shifts: shifts,
      payouts: payouts,
    );

class _MemoryRepository implements AppRepository {
  _MemoryRepository(this.value);

  AppState value;

  @override
  Future<AppState> load() async => value;

  @override
  Future<void> save(AppState state) async => value = state;

  @override
  Future<void> replace(AppState state) async => value = state;
}

class _FailingMemoryRepository extends _MemoryRepository {
  _FailingMemoryRepository(super.value);

  @override
  Future<void> save(AppState state) async => throw StateError('storage full');
}

class _FirstSaveFailsRepository extends _MemoryRepository {
  _FirstSaveFailsRepository(super.value);

  var _saveCount = 0;

  @override
  Future<void> save(AppState state) async {
    _saveCount++;
    if (_saveCount == 1) throw StateError('temporary storage failure');
    value = state;
  }
}
