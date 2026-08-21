/// Parameters used when opening a comic reader route.
final class ReaderLaunch {
  const ReaderLaunch({
    required this.filePath,
    this.initialPage,
    this.preserveProgressOnStart = false,
  });

  final String filePath;
  final int? initialPage;
  final bool preserveProgressOnStart;
}
