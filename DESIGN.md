# Aperture Grafik design system

## Design goals

An accessible Material 3 interface for tracking shifts and pay. Color palettes and visual treatments are separate settings, so a visual style no longer replaces the selected colors.

## Color palettes

- **Coffee** (default): warm brown and cream.
- **Milky latte**: the existing light roast palette.
- **Caramel roast**: the existing orange accent palette.
- **Night espresso**: the existing dark palette.
- **Ocean**: blue-green with cool surfaces.
- **Forest**: deep green with soft botanical surfaces.
- **Sakura**: rose accents with a pale pink surface.
- **Warm sunset**: terracotta with a peach surface.
- **Slate**: blue-grey with a clean neutral surface.

The four original palette enum values remain stable so saved settings and backups continue to load. New palettes are saved by their enum name and unknown names fall back to Coffee.

## Visual styles

- **Coffee classic**: original Material 3 cards and surfaces.
- **Crystal glass**: lightly tinted surfaces, translucent-looking cards and fine borders.
- **Neon night**: dark surfaces and a vivid accent derived from the selected palette.
- **Quiet minimal**: flat cards and restrained borders.
- **Soft relief**: raised cards with low-contrast shadows.
- **Editorial**: compact paper-like cards with a subtle ink border.
- **Aurora**: rounded surfaces with a complementary secondary accent derived from the selected palette.

Visual styles adjust surfaces, card shape and elevation while preserving the user's chosen palette. All components continue to use Material 3 colors and system icons.

## Motion

The **Shift animations** setting controls navigation transitions, navigation icon emphasis, calendar movement, shift completion and value transitions. The app also disables these transitions when the operating system requests reduced motion.

## Tokens

- Spacing: 8, 12, 16, 20, 24 and 32 dp.
- Minimum interactive target: 48 dp.
- Material 3 navigation: four destinations.
- Surface, border, text and accent colors come from the selected `ColorScheme`.

## Backup before update

Before opening Android's package installer, the app writes a complete, unencrypted JSON backup to its application documents directory under `backups/`. Installation is cancelled if the backup cannot be written. The latest eight automatic copies are retained. The profile screen describes this behavior; manual export remains available for sharing a copy outside the app.
