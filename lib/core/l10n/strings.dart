import '../../domain/models.dart';

class Strings {
  const Strings(this.language);
  final AppLanguage language;

  bool get isRu => language == AppLanguage.russian;
  String get appName => 'Aperture Grafik';
  String get home => isRu ? 'Главная' : 'Home';
  String get calendar => isRu ? 'Календарь' : 'Calendar';
  String get statistics => isRu ? 'Статистика' : 'Statistics';
  String get profile => isRu ? 'Профиль' : 'Profile';
  String get completeDay => isRu ? 'Завершить смену' : 'Complete shift';
  String get revenue => isRu ? 'Выручка' : 'Revenue';
  String get earnings => isRu ? 'Заработок' : 'Earnings';
  String get save => isRu ? 'Сохранить' : 'Save';
  String get cancel => isRu ? 'Отмена' : 'Cancel';
  String get add => isRu ? 'Добавить' : 'Add';
  String get advance => isRu ? 'Аванс' : 'Advance';
  String get salary => isRu ? 'Зарплата' : 'Salary';
  String get payouts => isRu ? 'Выплаты' : 'Payouts';
  String get addPayout => isRu ? 'Внести выплату' : 'Add payout';
  String get payoutHistory => isRu ? 'История выплат' : 'Payout history';
  String get earnedSinceLastPayout => isRu ? 'Заработано с последней выплаты' : 'Earned since last payout';
  String get expectedNextPayout => isRu ? 'К следующей выплате' : 'Next payout expected';
  String get todayIsPayoutDay => isRu ? 'Сегодня день выплаты!' : 'Today is payout day!';
  String get payoutDate => isRu ? 'Дата выплаты' : 'Payout date';
  String get payoutAmount => isRu ? 'Сумма выплаты' : 'Payout amount';
  String get payoutKind => isRu ? 'Тип выплаты' : 'Payout type';
  String get noPayoutsYet => isRu ? 'Выплат пока не внесено' : 'No payouts recorded yet';
  String get advanceDayLabel => isRu ? 'День аванса' : 'Advance day';
  String get salaryDayLabel => isRu ? 'День зарплаты' : 'Salary day';
  String get additional => isRu ? 'Дополнительно' : 'Additional';
  String get customPercentLabel => isRu ? 'Коэффициент дня (%)' : 'Day coefficient (%)';
  String get customDailyRateLabel => isRu ? 'Ставка за этот день (₽)' : 'Day rate (₽)';
  String get manualEarningsLabel => isRu ? 'Любая сумма за этот день (₽)' : 'Any amount for this day (₽)';
  String get revenueRequiredForPercentNotice => isRu
      ? 'Для коэффициента обязательно укажите выручку'
      : 'Revenue is required for the coefficient';
  String get shiftTotalEarnings => isRu ? 'Итого за этот день' : 'Total for this day';
}
