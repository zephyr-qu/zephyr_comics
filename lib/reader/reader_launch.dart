/// Parameters used when opening a comic reader route.
final class ReaderLaunch {
  const ReaderLaunch({required this.filePath, this.initialPage});

  final String filePath;
  final int? initialPage;
}
