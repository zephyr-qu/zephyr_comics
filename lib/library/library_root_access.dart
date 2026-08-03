abstract interface class AllFilesAccessAdapter {
  Future<bool> isGranted();

  Future<bool> request();
}

abstract interface class LibraryDirectoryPicker {
  Future<String?> pickDirectory();
}

enum LibraryRootChoiceStatus {
  selected,
  rationaleCancelled,
  authorizationDenied,
  pickerCancelled,
  failed,
}

class LibraryRootChoice {
  const LibraryRootChoice._({required this.status, this.path, this.cause});

  const LibraryRootChoice.selected(String path)
    : this._(status: LibraryRootChoiceStatus.selected, path: path);

  const LibraryRootChoice.rationaleCancelled()
    : this._(status: LibraryRootChoiceStatus.rationaleCancelled);

  const LibraryRootChoice.authorizationDenied({Object? cause})
    : this._(status: LibraryRootChoiceStatus.authorizationDenied, cause: cause);

  const LibraryRootChoice.pickerCancelled()
    : this._(status: LibraryRootChoiceStatus.pickerCancelled);

  const LibraryRootChoice.failed(Object cause)
    : this._(status: LibraryRootChoiceStatus.failed, cause: cause);

  final LibraryRootChoiceStatus status;
  final String? path;
  final Object? cause;
}

class LibraryRootAccess {
  const LibraryRootAccess({required this.permission, required this.picker});

  final AllFilesAccessAdapter permission;
  final LibraryDirectoryPicker picker;

  Future<LibraryRootChoice> choose({
    required Future<bool> Function() confirmPermission,
  }) async {
    try {
      if (!await permission.isGranted()) {
        if (!await confirmPermission()) {
          return const LibraryRootChoice.rationaleCancelled();
        }
        if (!await permission.request()) {
          return const LibraryRootChoice.authorizationDenied();
        }
      }
    } catch (error) {
      return LibraryRootChoice.authorizationDenied(cause: error);
    }

    try {
      final path = (await picker.pickDirectory())?.trim();
      if (path == null || path.isEmpty) {
        return const LibraryRootChoice.pickerCancelled();
      }
      return LibraryRootChoice.selected(path);
    } catch (error) {
      return LibraryRootChoice.failed(error);
    }
  }
}
