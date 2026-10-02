import 'package:aperture_grafik/core/theme/app_theme.dart';
import 'package:aperture_grafik/domain/models.dart';
import 'package:aperture_grafik/presentation/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  test('all saved theme modes resolve to the coffee design system', () {
    for (final mode in AppThemeMode.values) {
      final theme = AppTheme.forMode(mode);
      final buttonSize = theme.filledButtonTheme.style?.minimumSize?.resolve(
        const <WidgetState>{},
      );

      expect(theme.useMaterial3, isTrue);
      expect(theme.cardTheme.shape, isA<RoundedRectangleBorder>());
      expect(buttonSize?.height, greaterThanOrEqualTo(48));
      expect(theme.navigationBarTheme.height, greaterThanOrEqualTo(64));
    }

    expect(AppTheme.forMode(AppThemeMode.chamber).brightness, Brightness.dark);
    expect(
      AppTheme.forMode(AppThemeMode.standard).brightness,
      Brightness.light,
    );
  });

  test('all visual styles produce valid, distinct Material 3 themes', () {
    final themes = AppDesignStyle.values
        .map(
          (style) =>
              AppTheme.forMode(AppThemeMode.standard, designStyle: style),
        )
        .toList();

    expect(themes, hasLength(AppDesignStyle.values.length));
    expect(themes.every((theme) => theme.useMaterial3), isTrue);
    expect(
      themes.map((theme) => theme.scaffoldBackgroundColor).toSet(),
      hasLength(AppDesignStyle.values.length),
    );
    expect(
      AppTheme.forMode(
        AppThemeMode.standard,
        designStyle: AppDesignStyle.neon,
      ).brightness,
      Brightness.dark,
    );
  });

  testWidgets('coffee navigation renders on a narrow Android layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final mode in AppThemeMode.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.forMode(mode),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Scaffold(
            body: const Center(child: Text('Кофейная смена')),
            bottomNavigationBar: NavigationBar(
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.local_cafe_outlined),
                  label: 'Главная',
                ),
                NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  label: 'Календарь',
                ),
                NavigationDestination(
                  icon: Icon(Icons.insights_outlined),
                  label: 'Статистика',
                ),
                NavigationDestination(
                  icon: Icon(Icons.tune_outlined),
                  label: 'Профиль',
                ),
              ],
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull, reason: mode.name);
    }
  });

  testWidgets('onboarding remains usable with 200 percent text scaling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.forMode(AppThemeMode.standard),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const OnboardingScreen(),
        ),
      ),
    );

    for (var step = 0; step < 5; step++) {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'onboarding step $step');
      if (step < 4) {
        await tester.tap(find.text('Далее'));
      }
    }
  });

  testWidgets(
    'calendar month switching stays stable across all visual styles',
    (tester) async {
      await initializeDateFormatting();
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final data = AppState.initial().copyWith(
        settings: AppState.initial().settings.copyWith(
          onboardingComplete: true,
          shiftAnimationsEnabled: true,
        ),
      );

      for (final style in AppDesignStyle.values) {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.forMode(AppThemeMode.standard, designStyle: style),
              home: CalendarPage(data: data),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.chevron_right));
        await tester.pump(const Duration(milliseconds: 120));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull, reason: style.name);
      }
    },
  );
}
