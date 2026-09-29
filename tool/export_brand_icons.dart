// Regenerates the Android launcher icon PNGs from the wind mark geometry.
//
// Run it with:
//
//     flutter test tool/export_brand_icons.dart
//
// Why `flutter test` and not a plain `dart run`: the icon is rasterised with
// `dart:ui` (`PictureRecorder` -> `Canvas` -> `Picture.toImage` -> PNG), the
// same path golden tests use. That keeps the export dependency-free (no
// browser, no inkscape/ImageMagick, no new pub package) and deterministic.
//
// The brand SVGs are inputs, never outputs. `brand/logo/icon.svg` is the source
// of truth for the geometry; `windRibbons` below repeats its three `d` strings
// verbatim and `test/brand/launcher_icon_test.dart` fails if the two diverge.
//
// Before replacing a committed PNG the exporter re-decodes the bytes it is
// about to write and asserts the pixel dimensions and three sample colours, so
// a renderer regression cannot ship a blank or mis-sized launcher icon. Writes
// go to a temporary file in the same directory and are then renamed into place,
// so an aborted run leaves the previous icon untouched.
//
// Two environment knobs exist only to demonstrate that refusal, because a
// failure path nobody has run is a claim, not a guard. Both abort with a
// non-zero exit and leave every committed PNG byte-identical, since the check
// runs before the rename:
//
//     ICON_EXPORT_FORCE_SIZE=100 flutter test tool/export_brand_icons.dart
//     ICON_EXPORT_FORCE_BLANK=1  flutter test tool/export_brand_icons.dart
//
// The first renders the wrong pixel size, the second renders nothing at all (a
// fully transparent PNG). Neither may ever be used to produce real icons.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// The wind mark is drawn on a 64-unit grid (`viewBox="0 0 64 64"`).
const int brandGrid = 64;

/// Corner radius of the legacy tile, in brand-grid units (`rx="14"`).
const double tileCornerRadius = 14;

/// Warm black, the theme `surface` (and `--bg` in `brand/preview.html`).
const int tileColorArgb = 0xFF0E0D0C;

/// One of the three windswept ribbons. [argb] uses the same palette as the
/// theme; [pathData] is the SVG `d` attribute copied verbatim from
/// `brand/logo/icon.svg`.
class WindRibbon {
  const WindRibbon(this.pathData, this.argb);

  final String pathData;
  final int argb;
}

/// The three ribbons, top to bottom, exactly as they appear in
/// `brand/logo/icon.svg`.
const List<WindRibbon> windRibbons = <WindRibbon>[
  WindRibbon('M8 36Q32 24 56 17L56 22Q32 30 8 51Z', 0xFFC9A86A),
  WindRibbon('M14 46Q36 36 58 30L58 35Q36 42 14 58Z', 0xFFEDE6DA),
  WindRibbon('M26 52Q42 46 56 43L56 47Q42 51 26 60Z', 0xFF8B8680),
];

/// One legacy density bucket: a 48dp icon at the bucket scale.
class IconBucket {
  const IconBucket(this.directory, this.size);

  /// Resource directory name under `android/app/src/main/res`.
  final String directory;

  /// Edge length in pixels.
  final int size;
}

/// 48dp at mdpi/hdpi/xhdpi/xxhdpi/xxxhdpi.
const List<IconBucket> iconBuckets = <IconBucket>[
  IconBucket('mipmap-mdpi', 48),
  IconBucket('mipmap-hdpi', 72),
  IconBucket('mipmap-xhdpi', 96),
  IconBucket('mipmap-xxhdpi', 144),
  IconBucket('mipmap-xxxhdpi', 192),
];

/// Resource root, relative to the project root.
const String resourceRoot = 'android/app/src/main/res';

/// A pixel the exporter and the guard test both require to have [argb].
///
/// [argb] `0x00000000` means "fully transparent" (the rounded tile corner).
class IconSample {
  const IconSample(this.x, this.y, this.argb, this.label);

  final int x;
  final int y;
  final int argb;
  final String label;
}

/// The pixels checked for every rendered size, on the 64-unit brand grid.
///
/// - the top-left pixel is outside the rounded corner, so it must stay
///   transparent (the stock Flutter icon fails this);
/// - one interior pixel per ribbon, so all three fills are checked;
/// - the lower-middle pixel sits on the warm-black tile below the ribbons.
///
/// The samples are deliberately interior rather than at the exact geometric
/// centre: the brass ribbon's lower edge passes within half a pixel of the
/// centre at 48px, so a centre sample would measure antialiasing, not colour.
List<IconSample> iconSamples(int size) {
  IconSample at(int gridX, int gridY, int argb, String label) => IconSample(
    (size * gridX) ~/ brandGrid,
    (size * gridY) ~/ brandGrid,
    argb,
    label,
  );
  return <IconSample>[
    const IconSample(0, 0, 0x00000000, 'top-left corner (transparent)'),
    at(12, 40, windRibbons[0].argb, 'brass ribbon'),
    at(24, 46, windRibbons[1].argb, 'ink ribbon'),
    at(27, 55, windRibbons[2].argb, 'grey ribbon'),
    at(32, 60, tileColorArgb, 'tile below the ribbons (warm black)'),
  ];
}

/// Parses the absolute `M`/`L`/`Q`/`Z` subset of SVG path data used by the
/// wind mark into a [ui.Path]. Deriving the path from the same string the
/// drift guard checks keeps the exporter and `brand/logo/icon.svg` in step.
ui.Path parseSvgPath(String d) {
  final List<String> tokens = RegExp(
    r'[MLQZ]|-?\d+(?:\.\d+)?',
  ).allMatches(d).map((RegExpMatch match) => match.group(0)!).toList();
  final ui.Path path = ui.Path();
  int cursor = 0;
  double number() {
    if (cursor >= tokens.length) {
      throw FormatException('Truncated path data: $d');
    }
    return double.parse(tokens[cursor++]);
  }

  while (cursor < tokens.length) {
    final String command = tokens[cursor++];
    switch (command) {
      case 'M':
        path.moveTo(number(), number());
      case 'L':
        path.lineTo(number(), number());
      case 'Q':
        path.quadraticBezierTo(number(), number(), number(), number());
      case 'Z':
        path.close();
      default:
        throw FormatException('Unsupported path command "$command" in $d');
    }
  }
  return path;
}

/// Rasterises the rounded-tile legacy artwork at [size] x [size] and returns
/// the PNG bytes.
///
/// [ribbons] defaults to [windRibbons]; it is a parameter so a caller can
/// render deliberately wrong artwork when exercising the guard. [blank] skips
/// drawing entirely, which yields a fully transparent PNG — the shape a broken
/// renderer would produce and the one [verifyRenderedIcon] must refuse.
Future<Uint8List> renderLegacyTile(
  int size, {
  List<WindRibbon>? ribbons,
  bool blank = false,
}) async {
  final List<WindRibbon> usedRibbons = ribbons ?? windRibbons;
  final double scale = size / brandGrid;
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  if (!blank) {
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
        ui.Radius.circular(tileCornerRadius * scale),
      ),
      ui.Paint()..color = const ui.Color(tileColorArgb),
    );
    canvas.save();
    canvas.scale(scale);
    for (final WindRibbon ribbon in usedRibbons) {
      canvas.drawPath(
        parseSvgPath(ribbon.pathData),
        ui.Paint()..color = ui.Color(ribbon.argb),
      );
    }
    canvas.restore();
  }

  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(size, size);
  final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  if (data == null) {
    throw StateError('dart:ui returned no PNG bytes for a ${size}x$size icon');
  }
  return data.buffer.asUint8List();
}

/// A decoded RGBA buffer, for re-reading what was just rendered.
class DecodedIcon {
  DecodedIcon(this.width, this.height, this._bytes);

  final int width;
  final int height;
  final ByteData _bytes;

  /// Straight (unpremultiplied) RGBA at [x], [y] as `0xAARRGGBB`.
  int argbAt(int x, int y) {
    final int offset = (y * width + x) * 4;
    final int r = _bytes.getUint8(offset);
    final int g = _bytes.getUint8(offset + 1);
    final int b = _bytes.getUint8(offset + 2);
    final int a = _bytes.getUint8(offset + 3);
    return (a << 24) | (r << 16) | (g << 8) | b;
  }
}

/// Decodes PNG [bytes] to straight RGBA pixels.
Future<DecodedIcon> decodePng(Uint8List bytes) async {
  final ui.Codec codec = await ui.instantiateImageCodec(bytes);
  final ui.FrameInfo frame = await codec.getNextFrame();
  final ui.Image image = frame.image;
  final ByteData? data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  final int width = image.width;
  final int height = image.height;
  image.dispose();
  codec.dispose();
  if (data == null) {
    throw StateError('Could not decode the rendered PNG back to pixels');
  }
  return DecodedIcon(width, height, data);
}

/// Throws unless [icon] is [expectedSize] pixels square and every sample pixel
/// carries the expected colour. This is what refuses to write a blank icon.
void verifyRenderedIcon(DecodedIcon icon, int expectedSize, String label) {
  if (icon.width != expectedSize || icon.height != expectedSize) {
    throw StateError(
      '$label: rendered ${icon.width}x${icon.height}, '
      'expected ${expectedSize}x$expectedSize — refusing to write it',
    );
  }
  for (final IconSample sample in iconSamples(expectedSize)) {
    final int actual = icon.argbAt(sample.x, sample.y);
    if (actual != sample.argb) {
      throw StateError(
        '$label: ${sample.label} at (${sample.x}, ${sample.y}) is '
        '0x${actual.toRadixString(16).padLeft(8, '0')}, expected '
        '0x${sample.argb.toRadixString(16).padLeft(8, '0')} — '
        'refusing to write a blank or wrong icon',
      );
    }
  }
}

/// Renders every density, verifies it, then renames it into place.
///
/// [forceSize] overrides the rendered edge length while the verification still
/// expects the bucket's real size, and [forceBlank] renders nothing at all;
/// both exist so the refusal path can be demonstrated on purpose:
///
///     ICON_EXPORT_FORCE_SIZE=100 flutter test tool/export_brand_icons.dart
///     ICON_EXPORT_FORCE_BLANK=1  flutter test tool/export_brand_icons.dart
Future<List<String>> exportLauncherIcons({
  int? forceSize,
  bool forceBlank = false,
}) async {
  final List<String> written = <String>[];
  for (final IconBucket bucket in iconBuckets) {
    final int size = forceSize ?? bucket.size;
    final String relative = '$resourceRoot/${bucket.directory}/ic_launcher.png';
    final Uint8List bytes = await renderLegacyTile(size, blank: forceBlank);
    final DecodedIcon icon = await decodePng(bytes);
    verifyRenderedIcon(icon, bucket.size, relative);

    final File target = File(relative);
    target.parent.createSync(recursive: true);
    // Same-directory temp file, so an abort cannot leave a half-written icon.
    final File staging = File('$relative.tmp');
    staging.writeAsBytesSync(bytes, flush: true);
    staging.renameSync(target.path);
    written.add('$relative (${bucket.size}x${bucket.size})');
  }
  return written;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('exports the Android launcher icons from the wind mark', () async {
    final String? forced = Platform.environment['ICON_EXPORT_FORCE_SIZE'];
    final String? forcedBlank = Platform.environment['ICON_EXPORT_FORCE_BLANK'];
    final List<String> written = await exportLauncherIcons(
      forceSize: forced == null ? null : int.parse(forced),
      forceBlank: _isTruthy(forcedBlank),
    );
    for (final String line in written) {
      // Visible in `flutter test` output; the exporter is a tool, not a suite.
      // ignore: avoid_print
      print('wrote $line');
    }
  });
}

/// Reads an environment knob the way a shell user means it: set and not one of
/// the handful of spellings that read as "off".
bool _isTruthy(String? value) {
  if (value == null) {
    return false;
  }
  switch (value.trim().toLowerCase()) {
    case '':
    case '0':
    case 'false':
    case 'no':
    case 'off':
      return false;
    default:
      return true;
  }
}
