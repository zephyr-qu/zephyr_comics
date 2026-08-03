import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr_comics/services/library_scan_utils.dart';

void main() {
  test(
    'uniqueParentDirectories does not scan one cache directory repeatedly',
    () {
      expect(
        uniqueParentDirectories([
          '/cache/saf_imports/a/one.cbz',
          '/cache/saf_imports/a/two.cbz',
          '/cache/saf_imports/a/one.cbz',
        ]),
        ['/cache/saf_imports/a'],
      );
    },
  );

  test('deduplicateByNormalizedPath keeps the first item for each path', () {
    final items = [
      (path: r'C:\cache\book.cbz', value: 'first'),
      (path: 'C:/cache/book.cbz', value: 'second'),
      (path: '/cache/other.cbz', value: 'other'),
    ];

    expect(
      deduplicateByNormalizedPath(
        items,
        pathOf: (item) => item.path,
        caseInsensitive: true,
      ).map((item) => item.value),
      ['first', 'other'],
    );
  });
}
