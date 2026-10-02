import 'package:flutter_test/flutter_test.dart';
import 'package:aperture_grafik/application/app_controller.dart';
import 'package:aperture_grafik/data/app_repository.dart';
import 'package:aperture_grafik/domain/models.dart';

void main() {
  test(
    'first payout recalculation only touches shifts before that payout',
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
        actualAmountMinor: 450000,
      );

      expect(rate, 450000);
      final shifts = controller.state.requireValue.shifts;
      expect(shifts.singleWhere((s) => s.id == 'before').earningsMinor, 130000);
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
      actualAmountMinor: 450000,
    );
    final firstResult = controller.state.requireValue.shifts
        .map((shift) => shift.earningsMinor)
        .toList();
    await controller.recalculateShiftsForPayout(
      payout: payout,
      actualAmountMinor: 450000,
    );

    expect(
      controller.state.requireValue.shifts
          .map((shift) => shift.earningsMinor)
          .toList(),
      firstResult,
    );
    expect(firstResult, everyElement(112500));
  });

  test(
    'last salary period recalculation excludes the previous payout date',
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
        actualAmountMinor: 450000,
      );

      expect(rate, 450000);
      final shifts = controller.state.requireValue.shifts;
      expect(
        shifts.singleWhere((s) => s.id == 'previous-day').earningsMinor,
        242667,
      );
      expect(
        shifts.singleWhere((s) => s.id == 'previous-payout').earningsMinor,
        242667,
      );
      expect(
        shifts.singleWhere((s) => s.id == 'after-payout').earningsMinor,
        130000,
      );
    },
  );

  test('disabling adaptive salary restores original shift earnings', () async {
    final shift = _shift('adjusted', DateTime(2026, 9, 20), 375000);
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
    await controller.recalculateShiftsForPayout(
      payout: payout,
      actualAmountMinor: 130000,
    );

    expect(controller.state.requireValue.shifts.single.earningsMinor, 130000);
    expect(
      controller.state.requireValue.shifts.single.adaptiveEarningsOriginalMinor,
      375000,
    );

    await controller.updateSettings(
      controller.state.requireValue.settings.copyWith(
        adaptiveSalaryEnabled: false,
      ),
    );

    expect(controller.state.requireValue.shifts.single.earningsMinor, 130000);
    expect(
      controller.state.requireValue.shifts.single.adaptiveEarningsOriginalMinor,
      isNull,
    );
  });
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
