import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr_comics/library/comic_library.dart';

ComicLibraryEntry entry(String title, {int addedAt = 0, int? lastReadAt}) =>
    ComicLibraryEntry(
      path: '/comics/$title.cbz',
      title: title,
      format: 'cbz',
      fileSize: 1,
      totalPages: 1,
      addedAt: addedAt,
      lastReadAt: lastReadAt,
    );

void main() {
  test('refresh exposes loading then content and empty states', () async {
    final adapter = InMemoryComicLibraryAdapter([entry('One')]);
    final library = ComicLibrary(adapter: adapter);

    final content = await library.refresh('/comics');
    expect(content.status, LibraryStatus.content);
    expect(content.entries.single.title, 'One');

    adapter.entries = [];
    final empty = await library.refresh('/comics');
    expect(empty.status, LibraryStatus.empty);
  });

  test(
    'scan failure is a recoverable warning and keeps previous entries',
    () async {
      final adapter = InMemoryComicLibraryAdapter([entry('One')]);
      final library = ComicLibrary(adapter: adapter);
      await library.refresh('/comics');
      adapter.error = StateError('permission revoked');

      final warning = await library.refresh('/comics');
      expect(warning.status, LibraryStatus.warning);
      expect(warning.entries.single.title, 'One');
      expect(warning.message, contains('permission revoked'));
    },
  );

  test(
    'title search and deterministic sorts use the full scanned set',
    () async {
      final adapter = InMemoryComicLibraryAdapter([
        entry('Zeta', addedAt: 2, lastReadAt: 4),
        entry('Alpha', addedAt: 3, lastReadAt: 2),
        entry('Beta', addedAt: 1, lastReadAt: 6),
      ]);
      final library = ComicLibrary(adapter: adapter);
      await library.refresh('/comics');

      expect(library.sortBy(LibrarySort.title).entries.map((e) => e.title), [
        'Alpha',
        'Beta',
        'Zeta',
      ]);
      expect(library.search('ta').entries.map((e) => e.title), [
        'Beta',
        'Zeta',
      ]);
      expect(library.search('').entries.map((e) => e.title), [
        'Alpha',
        'Beta',
        'Zeta',
      ]);
      expect(
        library.sortBy(LibrarySort.recentlyRead).entries.map((e) => e.title),
        ['Beta', 'Zeta', 'Alpha'],
      );
    },
  );
}
