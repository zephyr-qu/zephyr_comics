import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr_comics/theme/zephyr_theme.dart';

/// WCAG relative luminance, for the contrast assertions below.
double _luminance(Color color) {
  double channel(double value) => value <= 0.04045
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

double _contrast(Color a, Color b) {
  final high = math.max(_luminance(a), _luminance(b));
  final low = math.min(_luminance(a), _luminance(b));
  return (high + 0.05) / (low + 0.05);
}

void main() {
  group('the dark palette is the prototype verbatim', () {
    final theme = zephyrDarkTheme();
    final scheme = theme.colorScheme;

    test('base surfaces map to the prototype background scale', () {
      expect(scheme.brightness, Brightness.dark);
      expect(scheme.surface, const Color(0xFF0E0D0C)); // --bg
      expect(scheme.surfaceContainerLow, const Color(0xFF161513)); // --s1
      expect(scheme.surfaceContainerHighest, const Color(0xFF1E1C19)); // --s2
    });

    test('text ramp maps to the prototype opacity levels', () {
      expect(scheme.onSurface, const Color(0xFFEDE6DA)); // --tx
      expect(scheme.onSurfaceVariant, const Color(0xFF8B8680)); // --tx2 @56%
      expect(scheme.outline, const Color(0xFF514E4A)); // --tx3 @30%
      expect(scheme.outlineVariant, const Color(0xFF262421)); // --line @7.5%
    });

    test('brass accent and its on-colour', () {
      expect(scheme.primary, const Color(0xFFC9A86A)); // --accent
      expect(scheme.onPrimary, const Color(0xFF141210));
      expect(scheme.error, const Color(0xFFE05A4A)); // --danger
    });

    test('scaffold background is the surface, not a Material default', () {
      expect(theme.scaffoldBackgroundColor, scheme.surface);
      expect(theme.useMaterial3, isTrue);
    });
  });

  group('the light palette is derived from the prototype light surfaces', () {
    final theme = zephyrLightTheme();
    final scheme = theme.colorScheme;

    test('paper base and ink come from the prototype', () {
      expect(scheme.brightness, Brightness.light);
      expect(scheme.surface, const Color(0xFFF4EFE6)); // .zc-page paper
      expect(
        scheme.surfaceContainerLow,
        const Color(0xFFFBF8F3),
      ); // .brief sheet
      expect(scheme.onSurface, const Color(0xFF241F1A)); // .brief ink
    });

    test('brass is deepened so body text clears WCAG AA', () {
      expect(scheme.primary, const Color(0xFF7E6128));
      expect(scheme.error, const Color(0xFFA8462F));
    });
  });

  group('contrast', () {
    test('dark accent on the dark surface clears AA', () {
      final scheme = zephyrDarkTheme().colorScheme;
      final ratio = _contrast(scheme.primary, scheme.surface);
      expect(ratio, greaterThanOrEqualTo(4.5));
      // The prototype value measures ~8.6:1.
      expect(ratio, closeTo(8.6, 0.2));
    });

    test('light accent on the light surface clears AA', () {
      final scheme = zephyrLightTheme().colorScheme;
      final ratio = _contrast(scheme.primary, scheme.surface);
      expect(ratio, greaterThanOrEqualTo(4.5));
      // 5.05:1 — the prototype's own #C9A86A would only reach 3.10:1 here.
      expect(ratio, closeTo(5.05, 0.2));
    });

    test('body text clears AAA on the base surface in both themes', () {
      for (final theme in [zephyrDarkTheme(), zephyrLightTheme()]) {
        expect(
          _contrast(theme.colorScheme.onSurface, theme.colorScheme.surface),
          greaterThanOrEqualTo(7),
        );
      }
    });
  });

  group('type roles mirror the prototype', () {
    test('display and titles are serif, metadata is monospace', () {
      for (final theme in [zephyrDarkTheme(), zephyrLightTheme()]) {
        final text = theme.textTheme;
        expect(text.displayLarge?.fontFamily, 'serif');
        expect(text.headlineSmall?.fontFamily, 'serif');
        expect(text.titleLarge?.fontFamily, 'serif');
        // Body copy and button labels stay on the platform sans.
        expect(text.bodyLarge?.fontFamily, isNot('monospace'));
        expect(text.labelLarge?.fontFamily, isNot('monospace'));
        // Metadata, section heads, and page numbers are monospace.
        expect(text.bodySmall?.fontFamily, 'monospace');
        expect(text.labelSmall?.fontFamily, 'monospace');
        expect(text.labelMedium?.fontFamily, 'monospace');
      }
    });

    test('text colours come from the scheme, not Material defaults', () {
      final scheme = zephyrDarkTheme().colorScheme;
      final text = zephyrDarkTheme().textTheme;
      expect(text.titleLarge?.color, scheme.onSurface);
      expect(text.bodyMedium?.color, scheme.onSurface);
      // `--tx3` carries section labels, counts, and metadata lines.
      expect(text.labelSmall?.color, scheme.outline);
      // `--tx2` carries progress readouts and the reader counter.
      expect(text.labelMedium?.color, scheme.onSurfaceVariant);
    });

    test('serif titles take the prototype weight and no tracking', () {
      for (final theme in [zephyrDarkTheme(), zephyrLightTheme()]) {
        final text = theme.textTheme;
        expect(text.headlineMedium?.fontSize, 27);
        expect(text.headlineMedium?.fontWeight, FontWeight.w600);
        expect(text.headlineSmall?.fontSize, 20);
        // Square glyphs are never pulled apart — `.sa-*{letter-spacing:normal}`.
        for (final style in [
          text.headlineMedium,
          text.bodyLarge,
          text.labelSmall,
          text.labelMedium,
        ]) {
          expect(style?.letterSpacing, 0, reason: '${style?.fontSize}');
        }
      }
    });
  });

  group('reader background values', () {
    test('are the three fixed product colours', () {
      expect(ZephyrReaderBackground.black, const Color(0xFF000000));
      expect(ZephyrReaderBackground.dark, const Color(0xFF141210));
      expect(ZephyrReaderBackground.paper, const Color(0xFFF4EFE6));
    });

    test('paper matches the light surface and dark is not neutral grey', () {
      expect(
        ZephyrReaderBackground.paper,
        zephyrLightTheme().colorScheme.surface,
      );
      // 0xFF141210 keeps the warm cast; a neutral #151515 would be colder.
      expect(
        ZephyrReaderBackground.dark.r,
        greaterThan(ZephyrReaderBackground.dark.b),
      );
    });
  });

  group('shared radius and surface constants', () {
    test('match the prototype values', () {
      expect(ZephyrRadius.card, 14);
      expect(ZephyrRadius.panel, 22);
      expect(ZephyrRadius.control, 20);
      expect(ZephyrRadius.segment, 11);
      expect(ZephyrSurfaces.paneAlpha, 0.86);
      expect(ZephyrSurfaces.scrimAlpha, 0.94);
    });

    test('cards and buttons pick the radius up from the theme', () {
      final theme = zephyrDarkTheme();
      final cardShape = theme.cardTheme.shape! as RoundedRectangleBorder;
      expect(cardShape.borderRadius, BorderRadius.circular(ZephyrRadius.card));
    });
  });

  group('component themes stay flat and on-palette', () {
    final theme = zephyrDarkTheme();

    test('no elevation tinting anywhere', () {
      expect(theme.appBarTheme.surfaceTintColor, const Color(0x00000000));
      expect(theme.colorScheme.surfaceTint, const Color(0x00000000));
      expect(theme.appBarTheme.elevation, 0);
    });

    test('dividers and sliders use the palette hairlines', () {
      expect(theme.dividerTheme.color, theme.colorScheme.outlineVariant);
      expect(theme.sliderTheme.trackHeight, 1);
      expect(theme.sliderTheme.activeTrackColor, theme.colorScheme.primary);
      // The scrubber thumb is a rotated square, not Material's disc.
      expect(theme.sliderTheme.thumbShape, isNot(isA<RoundSliderThumbShape>()));
    });

    test('the primary button is ink on page, not a brass fill', () {
      final style = theme.filledButtonTheme.style!;
      expect(style.backgroundColor?.resolve({}), theme.colorScheme.onSurface);
      expect(style.foregroundColor?.resolve({}), theme.colorScheme.surface);
    });
  });
}
