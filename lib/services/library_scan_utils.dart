import 'dart:io' show Platform;

String normalizeLibraryPath(String path, {bool? caseInsensitive}) {
  var normalized = path.replaceAll('\\', '/');
  while (normalized.contains('//')) {
    normalized = normalized.replaceAll('//', '/');
  }
  if (normalized.length > 1 && normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  if (caseInsensitive ?? Platform.isWindows) {
    normalized = normalized.toLowerCase();
  }
  return normalized;
}

List<String> uniqueParentDirectories(
  Iterable<String> filePaths, {
  bool? caseInsensitive,
}) {
  final parents = <String>[];
  final seen = <String>{};
  for (final filePath in filePaths) {
    final slash = filePath.lastIndexOf('/');
    final backslash = filePath.lastIndexOf('\\');
    final separator = slash > backslash ? slash : backslash;
    final parent = separator > 0 ? filePath.substring(0, separator) : '.';
    final key = normalizeLibraryPath(parent, caseInsensitive: caseInsensitive);
    if (seen.add(key)) {
      parents.add(parent);
    }
  }
  return parents;
}

List<T> deduplicateByNormalizedPath<T>(
  Iterable<T> items, {
  required String Function(T item) pathOf,
  bool? caseInsensitive,
}) {
  final result = <T>[];
  final seen = <String>{};
  for (final item in items) {
    final key = normalizeLibraryPath(
      pathOf(item),
      caseInsensitive: caseInsensitive,
    );
    if (seen.add(key)) {
      result.add(item);
    }
  }
  return result;
}
