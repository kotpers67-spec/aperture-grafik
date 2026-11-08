import 'package:flutter/material.dart';

import '../../domain/models.dart';

/// Material 3 design system with independent color palettes and visual styles.
class AppTheme {
  const AppTheme._();

  static ThemeData forMode(
    AppThemeMode mode, {
    AppDesignStyle designStyle = AppDesignStyle.none,
  }) {
    final palette = switch (mode) {
      AppThemeMode.standard => const _Palette(
        seed: Color(0xFF334155),
        surface: Color(0xFFF8FAFC),
        brightness: Brightness.light,
      ),
      AppThemeMode.laboratory => const _Palette(
        seed: Color(0xFF8D6E63),
        surface: Color(0xFFFAF8F5),
        brightness: Brightness.light,
      ),
      AppThemeMode.aperture => const _Palette(
        seed: Color(0xFFD97706),
        surface: Color(0xFFFFFBEB),
        brightness: Brightness.light,
      ),
      AppThemeMode.chamber => const _Palette(
        seed: Color(0xFF94A3B8),
        surface: Color(0xFF0F172A),
        brightness: Brightness.dark,
      ),
      AppThemeMode.ocean => const _Palette(
        seed: Color(0xFF0284C7),
        surface: Color(0xFFF0F9FF),
        brightness: Brightness.light,
      ),
      AppThemeMode.forest => const _Palette(
        seed: Color(0xFF059669),
        surface: Color(0xFFF0FDF4),
        brightness: Brightness.light,
      ),
      AppThemeMode.sakura => const _Palette(
        seed: Color(0xFFE11D48),
        surface: Color(0xFFFFF1F2),
        brightness: Brightness.light,
      ),
      AppThemeMode.sunset => const _Palette(
        seed: Color(0xFFEA580C),
        surface: Color(0xFFFFF7ED),
        brightness: Brightness.light,
      ),
      AppThemeMode.slate => const _Palette(
        seed: Color(0xFF4F46E5),
        surface: Color(0xFFEEF2FF),
        brightness: Brightness.light,
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
          borderRadius: BorderRadius.circular(styled.cardRadius),
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
    final dark = palette.brightness == Brightness.dark;
    final tintedSurface = Color.alphaBlend(
      base.primary.withValues(alpha: dark ? .07 : .035),
      palette.surface,
    );
    switch (style) {
      case AppDesignStyle.none:
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
        return _StyledPalette(
          scheme: base.copyWith(surface: tintedSurface),
          brightness: palette.brightness,
          surface: tintedSurface,
          cardColor: Color.alphaBlend(
            Colors.white.withValues(alpha: dark ? .045 : .64),
            dark ? base.surfaceContainerHigh : tintedSurface,
          ),
          cardBorder: base.primary.withValues(alpha: dark ? .3 : .24),
          cardElevation: dark ? 1 : 3,
        );
      case AppDesignStyle.neon:
        const surface = Color(0xFF0D1220);
        final neonScheme = ColorScheme.fromSeed(
          seedColor: palette.seed,
          brightness: Brightness.dark,
          surface: surface,
          dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
        );
        return _StyledPalette(
          scheme: neonScheme.copyWith(
            surface: surface,
            secondary: neonScheme.secondary,
          ),
          brightness: Brightness.dark,
          surface: surface,
          cardColor: const Color(0xFF151D2D),
          cardBorder: neonScheme.primary.withValues(alpha: .52),
          cardElevation: 0,
        );
      case AppDesignStyle.minimal:
        final minimalSurface = dark
            ? palette.surface
            : Color.alphaBlend(
                const Color(0xFF667085).withValues(alpha: .035),
                palette.surface,
              );
        return _StyledPalette(
          scheme: base.copyWith(surface: minimalSurface),
          brightness: palette.brightness,
          surface: minimalSurface,
          cardColor: dark ? base.surfaceContainerLow : Colors.white,
          cardBorder: base.outlineVariant.withValues(alpha: dark ? .22 : .42),
          cardElevation: 0,
        );
      case AppDesignStyle.neomorphic:
        final reliefSurface = dark
            ? Color.alphaBlend(
                Colors.white.withValues(alpha: .035),
                palette.surface,
              )
            : Color.alphaBlend(
                const Color(0xFF8E7966).withValues(alpha: .055),
                palette.surface,
              );
        return _StyledPalette(
          scheme: base.copyWith(surface: reliefSurface),
          brightness: palette.brightness,
          surface: reliefSurface,
          cardColor: dark
              ? Color.alphaBlend(
                  Colors.white.withValues(alpha: .055),
                  reliefSurface,
                )
              : Color.alphaBlend(
                  Colors.white.withValues(alpha: .62),
                  reliefSurface,
                ),
          cardBorder: Colors.transparent,
          cardElevation: dark ? 2 : 5,
        );
      case AppDesignStyle.editorial:
        final paperSurface = dark
            ? tintedSurface
            : Color.alphaBlend(
                const Color(0xFFF1E6D4).withValues(alpha: .28),
                palette.surface,
              );
        return _StyledPalette(
          scheme: base.copyWith(surface: paperSurface),
          brightness: palette.brightness,
          surface: paperSurface,
          cardColor: dark ? base.surfaceContainerLow : const Color(0xFFFFFEFC),
          cardBorder: base.primary.withValues(alpha: dark ? .28 : .2),
          cardElevation: 0,
          cardRadius: 14,
        );
      case AppDesignStyle.aurora:
        final hsl = HSLColor.fromColor(base.secondary);
        final complementary = hsl
            .withHue((hsl.hue + 86) % 360)
            .withSaturation((hsl.saturation * .88).clamp(.25, .8))
            .toColor();
        final auroraSurface = Color.alphaBlend(
          complementary.withValues(alpha: dark ? .08 : .045),
          tintedSurface,
        );
        return _StyledPalette(
          scheme: base.copyWith(
            surface: auroraSurface,
            secondary: complementary,
          ),
          brightness: palette.brightness,
          surface: auroraSurface,
          cardColor: dark ? base.surfaceContainerHigh : Colors.white,
          cardBorder: complementary.withValues(alpha: dark ? .34 : .3),
          cardElevation: dark ? 1 : 2,
          cardRadius: 28,
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
    this.cardRadius = 24,
  });

  final ColorScheme? scheme;
  final Brightness brightness;
  final Color surface;
  final Color cardColor;
  final Color cardBorder;
  final double cardElevation;
  final double cardRadius;
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
