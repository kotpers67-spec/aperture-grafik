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
  String get checkUpdates => isRu ? 'Проверить обновления' : 'Check for updates';
  String get checkingUpdates => isRu ? 'Проверка обновлений...' : 'Checking for updates...';
  String get updateAvailable => isRu ? 'Доступно обновление' : 'Update available';
  String get appUpToDate => isRu ? 'У вас установлена последняя версия' : 'App is up to date';
  String get downloadAndInstall => isRu ? 'Скачать и обновить' : 'Download & update';
  String get downloadingUpdate => isRu ? 'Загрузка обновления...' : 'Downloading update...';
  String get updateFailed => isRu ? 'Не удалось загрузить обновление' : 'Failed to download update';
  String get newVersion => isRu ? 'Новая версия' : 'New version';
  String get currentVersion => isRu ? 'Текущая версия' : 'Current version';
  String get payoutNotifications => isRu ? 'Напоминания о выплатах' : 'Payout reminders';
  String get payoutNotificationsSubtitle => isRu
      ? 'В день аванса и ЗП в 10:00 и накануне в 18:00'
      : 'On advance & salary day at 10:00 and the day before at 18:00';
  String get rateApp => isRu ? 'Оценить проект' : 'Rate the project';
  String get rateAppSubtitle => isRu
      ? 'Поставить звезду на GitHub или GitLab ⭐'
      : 'Star on GitHub or GitLab ⭐';
  String get rateDialogTitle => isRu ? 'Оцените Aperture Grafik' : 'Rate Aperture Grafik';
  String get rateDialogSubtitle => isRu
      ? 'Ваша оценка и звёзды в репозиториях помогают развивать проект!'
      : 'Your rating and stars in repositories help improve the project!';
  String get starOnGitHub => isRu ? 'Поставить ⭐ на GitHub' : 'Star ⭐ on GitHub';
  String get starOnGitLab => isRu ? 'Поставить ⭐ на GitLab' : 'Star ⭐ on GitLab';
  String get feedbackOnGitHub => isRu ? 'Предложить идею / багрепорт' : 'Suggest feature / bug report';
  String get ratingHighNotice => isRu
      ? 'Спасибо за высокую оценку! Поддержите проект звёздочкой в репозитории:'
      : 'Thank you for the high rating! Support the project with a star:';
  String get ratingLowNotice => isRu
      ? 'Спасибо за честность! Расскажите, чего не хватает или напишите нам:'
      : 'Thank you for your honesty! Let us know what to improve:';
  String get workedHours => isRu ? 'Отработано часов' : 'Hours worked';
  String hoursLabel(double h) {
    final rounded = h.toStringAsFixed(1);
    return isRu ? '$rounded ч' : '${rounded}h';
  }
}
