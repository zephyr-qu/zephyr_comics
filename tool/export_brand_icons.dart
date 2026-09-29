// Regenerates the Android launcher icon PNGs from the seal mark geometry.
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
// of truth for the geometry; `sealPathData` and `bookPages` below repeat its `d`
// strings verbatim and `test/brand/launcher_icon_test.dart` fails if the two
// diverge.
//
// Before replacing a committed PNG the exporter re-decodes the bytes it is
// about to write and asserts the pixel dimensions and sample colours, so
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

/// The mark is drawn on a 64-unit grid (`viewBox="0 0 64 64"`).
const int brandGrid = 64;

/// The legacy tile's corner radius in brand-grid units (`rx="13.5"`), on a tile
/// inset by half a unit so its hairline edge is not clipped.
const double tileCornerRadius = 13.5;

/// Paper, the light theme's `surface` (and the tile in `brand/logo/icon.svg`).
const int tileColorArgb = 0xFFF4EFE6;

/// The hairline that keeps a paper tile from melting into a white home screen.
const int tileEdgeColorArgb = 0xFFDCD5C7;

/// The deeper brass the light theme uses: the prototype's `#C9A86A` is only
/// 3.10:1 on paper, this is 5.05:1.
const int sealColorArgb = 0xFF7E6128;

/// The seal's disc in brand-grid units (`<circle cx="32" cy="32" r="23">`).
const double sealCenter = 32;
const double sealRadius = 23;

/// The same disc as path data. The adaptive foreground needs it because a
/// VectorDrawable has no `<circle>` element, so the drawable spells the disc out
/// and the guard test compares the two.
const String sealPathData = 'M9 32a23 23 0 1 0 46 0a23 23 0 0 0-46 0Z';

/// The open book knocked out of the seal: two page quadrilaterals with a gap
/// between them for the spine. Copied verbatim from `brand/logo/icon.svg`.
const List<String> bookPages = <String>[
  'M18 25L31 19.5L31 35L18 39.5Z',
  'M33 19.5L46 25L46 39.5L33 35Z',
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
/// The pixels checked for every rendered size, on the 64-unit brand grid.
///
/// - the top-left pixel is outside the rounded tile corner, so it must stay
///   transparent (the stock Flutter icon fails this);
/// - a pixel on the seal's brass, beside the book;
/// - a pixel inside the left page, which must be the paper the book is cut in;
/// - a pixel on the seal's brass below the book, clear of both pages;
/// - a pixel on the tile outside the seal, which must be paper too.
///
/// The samples are deliberately interior rather than on an edge: a boundary
/// pixel would measure antialiasing rather than a palette colour.
List<IconSample> iconSamples(int size) {
  IconSample at(int gridX, int gridY, int argb, String label) => IconSample(
    (size * gridX) ~/ brandGrid,
    (size * gridY) ~/ brandGrid,
    argb,
    label,
  );
  return <IconSample>[
    const IconSample(0, 0, 0x00000000, 'top-left corner (transparent)'),
    at(12, 32, sealColorArgb, 'seal brass beside the book'),
    at(24, 32, tileColorArgb, 'left page (paper)'),
    at(32, 47, sealColorArgb, 'seal brass below the book'),
    at(4, 32, tileColorArgb, 'tile outside the seal (paper)'),
  ];
}

/// Parses the absolute `M`/`L`/`Q`/`Z` subset of SVG path data used by the book
/// pages into a [ui.Path]. Deriving the path from the same string the drift guard
/// checks keeps the exporter and `brand/logo/icon.svg` in step.
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

/// Rasterises the rounded-tile legacy artwork at [size] x [size] and returns the
/// PNG bytes: paper tile, hairline edge, brass seal, book knocked out of it.
///
/// [pages] defaults to [bookPages]; it is a parameter so a caller can render
/// deliberately wrong artwork when exercising the guard. [blank] skips drawing
/// entirely, which yields a fully transparent PNG — the shape a broken renderer
/// would produce and the one [verifyRenderedIcon] must refuse.
Future<Uint8List> renderLegacyTile(
  int size, {
  List<String>? pages,
  bool blank = false,
}) async {
  final List<String> usedPages = pages ?? bookPages;
  final double scale = size / brandGrid;
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  if (!blank) {
    final ui.RRect tile = ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(0.5 * scale, 0.5 * scale, size - scale, size - scale),
      ui.Radius.circular(tileCornerRadius * scale),
    );
    canvas.drawRRect(tile, ui.Paint()..color = const ui.Color(tileColorArgb));
    canvas.drawRRect(
      tile,
      ui.Paint()
        ..color = const ui.Color(tileEdgeColorArgb)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = scale,
    );
    canvas.save();
    canvas.scale(scale);
    canvas.drawCircle(
      const ui.Offset(sealCenter, sealCenter),
      sealRadius,
      ui.Paint()..color = const ui.Color(sealColorArgb),
    );
    for (final String page in usedPages) {
      canvas.drawPath(
        parseSvgPath(page),
        ui.Paint()..color = const ui.Color(tileColorArgb),
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

  test('exports the Android launcher icons from the seal mark', () async {
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
