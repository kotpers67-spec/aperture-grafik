import 'package:flutter/material.dart';

import '../../domain/models.dart';

/// Material 3 design system built around a warm, independent coffee-shop
/// identity. Every palette uses original colours and system icons only.
class AppTheme {
  const AppTheme._();

  static ThemeData forMode(
    AppThemeMode mode, {
    AppDesignStyle designStyle = AppDesignStyle.none,
  }) {
    final palette = switch (mode) {
      AppThemeMode.standard => const _Palette(
        seed: Color(0xFF6F4E37),
        surface: Color(0xFFFFF9F2),
        brightness: Brightness.light,
      ),
      AppThemeMode.laboratory => const _Palette(
        seed: Color(0xFF8A5A3B),
        surface: Color(0xFFFFFCF7),
        brightness: Brightness.light,
      ),
      AppThemeMode.aperture => const _Palette(
        seed: Color(0xFFB85F24),
        surface: Color(0xFFFFF8F0),
        brightness: Brightness.light,
      ),
      AppThemeMode.chamber => const _Palette(
        seed: Color(0xFFD3A06C),
        surface: Color(0xFF17120F),
        brightness: Brightness.dark,
      ),
    };
    final generated = ColorScheme.fromSeed(
      seedColor: palette.seed,
      brightness: palette.brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    final styled = _applyDesignStyle(generated, palette, designStyle);
    final scheme = styled.scheme ?? generated;
    final isDark = styled.brightness == Brightness.dark;
    final textTheme = Typography.material2021(
      platform: TargetPlatform.android,
      colorScheme: scheme,
    ).black.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

    return ThemeData(
      useMaterial3: true,
      brightness: styled.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: styled.surface,
      dividerColor: scheme.outlineVariant.withValues(alpha: .62),
      visualDensity: VisualDensity.standard,
      textTheme: textTheme.copyWith(
        headlineSmall: textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -.4,
        ),
        titleLarge: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -.2,
        ),
        titleMedium: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        titleSmall: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        labelLarge: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        bodyLarge: textTheme.bodyLarge?.copyWith(height: 1.45),
        bodyMedium: textTheme.bodyMedium?.copyWith(height: 1.4),
      ),
      cardTheme: CardThemeData(
        elevation: styled.cardElevation,
        shadowColor: Colors.black.withValues(alpha: .08),
        surfaceTintColor: Colors.transparent,
        color: styled.cardColor,
        margin: const EdgeInsets.symmetric(vertical: 6),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: styled.cardBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? scheme.surfaceContainerHighest
            : scheme.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 56),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 56),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainer,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: TextStyle(color: scheme.onSurface),
        secondaryLabelStyle: TextStyle(color: scheme.onPrimaryContainer),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        shape: const StadiumBorder(),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        minVerticalPadding: 10,
        iconColor: scheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        elevation: 0,
        backgroundColor: isDark
            ? scheme.surfaceContainer
            : scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            size: 25,
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
          );
        }),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 68,
        backgroundColor: styled.surface,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleSpacing: 20,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: -.5,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w700),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  static _StyledPalette _applyDesignStyle(
    ColorScheme base,
    _Palette palette,
    AppDesignStyle style,
  ) {
    switch (style) {
      case AppDesignStyle.none:
        final dark = palette.brightness == Brightness.dark;
        return _StyledPalette(
          scheme: base.copyWith(surface: palette.surface),
          brightness: palette.brightness,
          surface: palette.surface,
          cardColor: dark
              ? base.surfaceContainerHigh
              : base.surfaceContainerLowest,
          cardBorder: base.outlineVariant.withValues(alpha: dark ? .42 : .7),
          cardElevation: dark ? 0 : 1,
        );
      case AppDesignStyle.glass:
        final seed = const Color(0xFF167A9C);
        final scheme = ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
          surface: const Color(0xFFEAF5F7),
        );
        return _StyledPalette(
          scheme: scheme,
          brightness: Brightness.light,
          surface: Color(0xFFEAF5F7),
          cardColor: Color(0xDDFBFFFF),
          cardBorder: Color(0x8875B9C7),
          cardElevation: 3,
        );
      case AppDesignStyle.neon:
        final scheme =
            ColorScheme.fromSeed(
              seedColor: const Color(0xFF68F5E5),
              brightness: Brightness.dark,
              surface: const Color(0xFF090D19),
            ).copyWith(
              primary: const Color(0xFF68F5E5),
              secondary: const Color(0xFFFF64D8),
              surface: const Color(0xFF090D19),
            );
        return _StyledPalette(
          scheme: scheme,
          brightness: Brightness.dark,
          surface: const Color(0xFF090D19),
          cardColor: const Color(0xFF151B2C),
          cardBorder: const Color(0x8868F5E5),
          cardElevation: 0,
        );
      case AppDesignStyle.minimal:
        final scheme = ColorScheme.fromSeed(
          seedColor: const Color(0xFF496B58),
          brightness: Brightness.light,
          surface: const Color(0xFFF5F5F0),
        );
        return _StyledPalette(
          scheme: scheme,
          brightness: Brightness.light,
          surface: const Color(0xFFF5F5F0),
          cardColor: const Color(0xFFFFFFFF),
          cardBorder: const Color(0xFFD9DFD8),
          cardElevation: 0,
        );
      case AppDesignStyle.neomorphic:
        final scheme = ColorScheme.fromSeed(
          seedColor: const Color(0xFF775E4C),
          brightness: Brightness.light,
          surface: const Color(0xFFEAE4DC),
        );
        return _StyledPalette(
          scheme: scheme,
          brightness: Brightness.light,
          surface: const Color(0xFFEAE4DC),
          cardColor: const Color(0xFFF0EBE4),
          cardBorder: const Color(0x00FFFFFF),
          cardElevation: 5,
        );
    }
  }
}

class _StyledPalette {
  const _StyledPalette({
    required this.scheme,
    required this.brightness,
    required this.surface,
    required this.cardColor,
    required this.cardBorder,
    required this.cardElevation,
  });

  final ColorScheme? scheme;
  final Brightness brightness;
  final Color surface;
  final Color cardColor;
  final Color cardBorder;
  final double cardElevation;
}

class _Palette {
  const _Palette({
    required this.seed,
    required this.surface,
    required this.brightness,
  });

  final Color seed;
  final Color surface;
  final Brightness brightness;
}
