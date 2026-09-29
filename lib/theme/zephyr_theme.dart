/// The single source of truth for colour, radius, and type in Zephyr Comics.
///
/// Visual reference: `designs/zephyr-comics-explore/` (the "暖黑静读" prototype,
/// see `index.html`'s `.sa{}` block and `style-a-quiet.jsx`). Widgets must take
/// every colour, radius, and text style from the resulting `ThemeData` instead
/// of writing literals — `test/theme/zephyr_theme_test.dart` guards the mapping.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Prototype font roles. The prototype itself says it relies on the system
/// stack ("中文字体走系统栈"), so these are the two generic families Flutter maps
/// onto them rather than bundled assets.
const String _serif = 'serif';
const String _mono = 'monospace';

/// Corner radii, taken from the prototype's `--r` / `--r-lg` plus the reader
/// drawer and segmented-control values.
abstract final class ZephyrRadius {
  /// Covers and cards (`--r`, 14px).
  static const double card = 14;

  /// The reader drawer's floating panel (22px).
  static const double panel = 22;

  /// Buttons, the search field, and dropdown surfaces (`--r-lg`, 20px).
  static const double control = 20;

  /// The segmented reader-mode track (11px).
  static const double segment = 11;

  /// The settings pill's compact track, a step smaller than the reader
  /// drawer's [segment] because the settings rows are denser.
  static const double segmentCompact = 9;

  /// Thumbnails and inline banners (8px).
  static const double small = 8;

  /// Fully rounded 1–2px bars, such as the drawer grip.
  static const double hairline = 1;

  /// Material's chip corner. The prototype has no chips to copy, so this stays
  /// at the framework default rather than the app's card radius.
  static const double chip = 4;
}

/// The spacing ladder. Every margin, padding, and gap takes a step from here.
/// The steps are multiples of 4, so surfaces that share a rhythm keep it; a
/// value outside the ladder is a deliberate exception and must say why in a
/// comment next to it.
abstract final class ZephyrSpacing {
  /// Inside a control: icon-to-label, a segmented track's inner padding.
  static const double xs = 4;

  /// Tightly related items: a label and the control beneath it.
  static const double sm = 8;

  /// Sibling rows; a list's default vertical rhythm.
  static const double md = 12;

  /// Standard horizontal page padding; a grouped block's inner gap.
  static const double lg = 16;

  /// Between blocks: a header and the content it introduces.
  static const double xl = 24;

  /// Around a whole state (empty / error); outermost page padding.
  static const double xxl = 32;
}

/// Alpha levels for surfaces that sit on top of the reader canvas.
abstract final class ZephyrSurfaces {
  /// The reader drawer and its collapsed page-number handle.
  static const double paneAlpha = 0.86;

  /// Top of the reader's top-bar scrim.
  static const double scrimAlpha = 0.94;
}

/// The reader background values are a product setting, not theme-derived:
/// PRD V2 §9 requires black / dark gray as *fixed* colours. They live here so
/// no Widget needs a colour literal.
abstract final class ZephyrReaderBackground {
  static const Color black = Color(0xFF000000);

  /// The prototype's `--reader` gray (`#141210`), not a neutral `#151515`.
  static const Color dark = Color(0xFF141210);

  /// The prototype's page paper (`#F4EFE6`).
  static const Color paper = Color(0xFFF4EFE6);
}

// ── palette ─────────────────────────────────────────────────────────────────

/// The prototype's palette, dark. Every value is taken from the prototype
/// verbatim; the alphas are composited onto the surface they sit on so M3's
/// opaque slots can carry them.
abstract final class _Dark {
  static const Color surface = Color(0xFF0E0D0C); // --bg
  static const Color surfaceLow = Color(0xFF161513); // --s1
  static const Color surfaceHigh = Color(0xFF1A1815);
  static const Color surfaceHigher = Color(0xFF1C1A17);
  static const Color surfaceHighest = Color(0xFF1E1C19); // --s2
  static const Color surfaceLowest = Color(0xFF0A0908);

  static const Color onSurface = Color(0xFFEDE6DA); // --tx
  static const Color onSurfaceVariant = Color(0xFF8B8680); // --tx2 @56%
  static const Color outline = Color(0xFF514E4A); // --tx3 @30%
  static const Color outlineVariant = Color(0xFF262421); // --line @7.5%

  static const Color primary = Color(0xFFC9A86A); // --accent
  static const Color onPrimary = Color(0xFF141210);
  static const Color primaryContainer = Color(0xFF3A2F1D);
  static const Color onPrimaryContainer = Color(0xFFF0DFBE);

  static const Color secondaryContainer = Color(0xFF262421);
  static const Color error = Color(0xFFE05A4A); // prototype's --danger
  static const Color onError = Color(0xFF141210);
}

/// The prototype has no light palette. These values are derived from light
/// surfaces the prototype *does* contain: the comic page (`#F4EFE6`) and the
/// brief sheet's paper/ink pair (`#FBF8F3` / `#241F1A`).
abstract final class _Light {
  static const Color surface = Color(0xFFF4EFE6);
  static const Color surfaceLow = Color(0xFFFBF8F3);
  static const Color surfaceHigh = Color(0xFFF1ECE1);
  static const Color surfaceHigher = Color(0xFFEEE8DC);
  static const Color surfaceHighest = Color(0xFFEAE4D8);
  static const Color surfaceLowest = Color(0xFFFDFBF7);

  static const Color onSurface = Color(0xFF241F1A);
  static const Color onSurfaceVariant = Color(0xFF6B6259);
  static const Color outline = Color(0xFF9A9188);
  static const Color outlineVariant = Color(0xFFDCD5C7);

  /// Deepened brass. The prototype's `#C9A86A` sits at 3.10:1 on `#F4EFE6`
  /// (below WCAG AA for body text); this reaches 5.05:1.
  static const Color primary = Color(0xFF7E6128);
  static const Color onPrimary = Color(0xFFFBF8F3);
  static const Color primaryContainer = Color(0xFFEFE1BE);
  static const Color onPrimaryContainer = Color(0xFF3A2F1D);

  static const Color secondaryContainer = Color(0xFFE7DFC9);
  static const Color error = Color(0xFFA8462F);
  static const Color onError = Color(0xFFFBF8F3);
}

ColorScheme _darkScheme() => const ColorScheme(
  brightness: Brightness.dark,
  primary: _Dark.primary,
  onPrimary: _Dark.onPrimary,
  primaryContainer: _Dark.primaryContainer,
  onPrimaryContainer: _Dark.onPrimaryContainer,
  secondary: _Dark.primary,
  onSecondary: _Dark.onPrimary,
  secondaryContainer: _Dark.secondaryContainer,
  onSecondaryContainer: _Dark.onSurface,
  tertiary: _Dark.primary,
  onTertiary: _Dark.onPrimary,
  tertiaryContainer: _Dark.primaryContainer,
  onTertiaryContainer: _Dark.onPrimaryContainer,
  error: _Dark.error,
  onError: _Dark.onError,
  errorContainer: _Dark.primaryContainer,
  onErrorContainer: _Dark.onPrimaryContainer,
  surface: _Dark.surface,
  onSurface: _Dark.onSurface,
  surfaceContainerLowest: _Dark.surfaceLowest,
  surfaceContainerLow: _Dark.surfaceLow,
  surfaceContainer: _Dark.surfaceHigh,
  surfaceContainerHigh: _Dark.surfaceHigher,
  surfaceContainerHighest: _Dark.surfaceHighest,
  onSurfaceVariant: _Dark.onSurfaceVariant,
  outline: _Dark.outline,
  outlineVariant: _Dark.outlineVariant,
  inverseSurface: _Dark.onSurface,
  onInverseSurface: _Dark.surface,
  inversePrimary: _Dark.primaryContainer,
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  // Flat surfaces: the prototype has no elevation tinting.
  surfaceTint: Color(0x00000000),
);

ColorScheme _lightScheme() => const ColorScheme(
  brightness: Brightness.light,
  primary: _Light.primary,
  onPrimary: _Light.onPrimary,
  primaryContainer: _Light.primaryContainer,
  onPrimaryContainer: _Light.onPrimaryContainer,
  secondary: _Light.primary,
  onSecondary: _Light.onPrimary,
  secondaryContainer: _Light.secondaryContainer,
  onSecondaryContainer: _Light.onSurface,
  tertiary: _Light.primary,
  onTertiary: _Light.onPrimary,
  tertiaryContainer: _Light.primaryContainer,
  onTertiaryContainer: _Light.onPrimaryContainer,
  error: _Light.error,
  onError: _Light.onError,
  errorContainer: _Light.primaryContainer,
  onErrorContainer: _Light.onPrimaryContainer,
  surface: _Light.surface,
  onSurface: _Light.onSurface,
  surfaceContainerLowest: _Light.surfaceLowest,
  surfaceContainerLow: _Light.surfaceLow,
  surfaceContainer: _Light.surfaceHigh,
  surfaceContainerHigh: _Light.surfaceHigher,
  surfaceContainerHighest: _Light.surfaceHighest,
  onSurfaceVariant: _Light.onSurfaceVariant,
  outline: _Light.outline,
  outlineVariant: _Light.outlineVariant,
  inverseSurface: _Light.onSurface,
  onInverseSurface: _Light.surface,
  inversePrimary: _Light.primaryContainer,
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  surfaceTint: Color(0x00000000),
);

// ── type ────────────────────────────────────────────────────────────────────

/// Three roles, mirroring the prototype: serif for display and titles,
/// monospace for metadata and page numbers, the platform sans for everything
/// else (body copy and button labels).
///
/// Chinese text never takes tracking. The prototype sets every `.sa-*` label
/// back to `letter-spacing: normal` on purpose — pulling square glyphs apart
/// reads as broken spacing, not as a typographic style — and reintroduces
/// tracking only on page numbers and counters. So each role here is zeroed and
/// the counters add their own spacing at the call site.
TextTheme _textTheme(ColorScheme scheme, Brightness brightness) {
  final base = brightness == Brightness.dark
      ? Typography.material2021().white
      : Typography.material2021().black;

  TextStyle? display(TextStyle? style, {double? fontSize}) => style?.copyWith(
    fontFamily: _serif,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    fontSize: fontSize,
    color: scheme.onSurface,
  );
  TextStyle? body(TextStyle? style) =>
      style?.copyWith(letterSpacing: 0, color: scheme.onSurface);
  TextStyle? meta(TextStyle? style, {Color? color}) => style?.copyWith(
    fontFamily: _mono,
    letterSpacing: 0,
    color: color ?? scheme.outline,
  );

  return base.copyWith(
    displayLarge: display(base.displayLarge),
    displayMedium: display(base.displayMedium),
    displaySmall: display(base.displaySmall),
    headlineLarge: display(base.headlineLarge),
    // The shelf and settings h1s are 27px, an empty state's h3 is 20px.
    headlineMedium: display(base.headlineMedium, fontSize: 27),
    headlineSmall: display(base.headlineSmall, fontSize: 20),
    titleLarge: display(base.titleLarge),
    titleMedium: body(base.titleMedium),
    titleSmall: body(base.titleSmall),
    bodyLarge: body(base.bodyLarge),
    bodyMedium: body(base.bodyMedium),
    bodySmall: meta(base.bodySmall),
    labelLarge: body(base.labelLarge),
    // `--tx2`: progress readouts, the reader counter, tool labels.
    labelMedium: meta(base.labelMedium, color: scheme.onSurfaceVariant),
    // `--tx3`: section labels, counts, and every metadata line.
    labelSmall: meta(base.labelSmall),
  );
}

// ── themes ──────────────────────────────────────────────────────────────────

ThemeData _theme(ColorScheme scheme, Brightness brightness) {
  final text = _textTheme(scheme, brightness);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    textTheme: text,
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: const Color(0x00000000),
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      surfaceTintColor: const Color(0x00000000),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZephyrRadius.card),
      ),
    ),
    // `.sa-btn-pri` is the ink colour on the page colour — cream with dark
    // text — not a brass fill. Brass is spent on the accent hairline only.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.onSurface,
        foregroundColor: scheme.surface,
        minimumSize: const Size(0, 46),
        textStyle: text.labelLarge?.copyWith(
          fontSize: 13.5,
          letterSpacing: 0.8,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZephyrRadius.control),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurfaceVariant,
        minimumSize: const Size(0, 46),
        textStyle: text.labelLarge?.copyWith(
          fontSize: 13.5,
          letterSpacing: 0.8,
        ),
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZephyrRadius.control),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        textStyle: text.labelLarge,
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      textColor: scheme.onSurface,
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 1,
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.2),
      thumbColor: scheme.primary,
      overlayColor: scheme.primary.withValues(alpha: 0.12),
      // The prototype rotates a small square 45°: a diamond, not a disc.
      thumbShape: const _DiamondThumbShape(),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.outlineVariant,
      linearMinHeight: 3,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: const Color(0x00000000),
      titleTextStyle: text.titleLarge?.copyWith(fontSize: 18),
      contentTextStyle: text.bodyMedium?.copyWith(
        fontSize: 12.5,
        height: 1.85,
        color: scheme.onSurfaceVariant,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZephyrRadius.card),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerHighest,
      surfaceTintColor: const Color(0x00000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZephyrRadius.card),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      side: BorderSide(color: scheme.outlineVariant),
      labelStyle: text.labelSmall,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZephyrRadius.chip),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: text.bodyMedium?.copyWith(
        color: scheme.onInverseSurface,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZephyrRadius.small),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      hintStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ZephyrRadius.control),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ZephyrRadius.control),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ZephyrRadius.control),
        borderSide: BorderSide(color: scheme.primary.withValues(alpha: 0.34)),
      ),
    ),
  );
}

/// The "暖黑静读" palette as a Material 3 theme.
ThemeData zephyrDarkTheme() => _theme(_darkScheme(), Brightness.dark);

/// The derived light counterpart. See [_Light] for its provenance.
ThemeData zephyrLightTheme() => _theme(_lightScheme(), Brightness.light);

/// The prototype's scrubber thumb: a square rotated 45° (`.sa-range`'s
/// `transform: rotate(45deg)`), so the reader slider reads as a diamond rather
/// than Material's disc. One step slimmer than the prototype's 11px because the
/// drawer row is deliberately compact.
class _DiamondThumbShape extends SliderComponentShape {
  const _DiamondThumbShape();

  static const double _side = 9;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.square(_side);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final paint = Paint()
      ..color = sliderTheme.thumbColor ?? const Color(0xFF000000);
    final canvas = context.canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..rotate(math.pi / 4);
    canvas.drawRect(
      Rect.fromCenter(center: Offset.zero, width: _side, height: _side),
      paint,
    );
    canvas.restore();
  }
}
