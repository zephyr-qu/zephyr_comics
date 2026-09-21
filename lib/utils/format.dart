/// `42.1 MB`, `184 KB`, `0 B` — the monospace metadata file size.
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const megabyte = 1024 * 1024;
  if (bytes >= megabyte) return '${(bytes / megabyte).toStringAsFixed(1)} MB';
  return '${(bytes / 1024).toStringAsFixed(0)} KB';
}

/// The final path segment of [path]. Handles both separators because a library
/// path may have been written on either platform.
String baseName(String path) => path.split(RegExp(r'[/\\]')).last;
