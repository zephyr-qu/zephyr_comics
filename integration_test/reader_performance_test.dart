import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zephyr_comics/src/rust/api/reader.dart' as rust;
import 'package:zephyr_comics/src/rust/frb_generated.dart';

const benchmarkCbz = String.fromEnvironment('READER_BENCHMARK_CBZ');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(RustLib.init);

  testWidgets(
    'encoded page path stays within the first-page performance budget',
    (_) async {
      final stopwatch = Stopwatch()..start();
      final page = await rust.getPageImageEncoded(
        filePath: benchmarkCbz,
        pageIndex: 0,
      );
      stopwatch.stop();

      final elapsed = stopwatch.elapsedMilliseconds;
      // Kept machine-readable so the same device/fixture can compare before
      // and after without relying on visual stopwatch timing.
      // ignore: avoid_print
      print('READER_PERF encoded_page_ms=$elapsed bytes=${page.length}');

      expect(page, isNotEmpty);
      expect(
        elapsed,
        lessThan(1500),
        reason: 'First-page spinner exceeded the 1.5 second device budget.',
      );
    },
    skip: benchmarkCbz.isEmpty,
  );
}
