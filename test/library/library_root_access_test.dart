import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr_comics/library/library_root_access.dart';

void main() {
  test('already granted access goes directly to directory selection', () async {
    final permission = _PermissionAdapter(granted: true);
    final picker = _DirectoryPicker('/storage/emulated/0/Comics');
    final access = LibraryRootAccess(permission: permission, picker: picker);
    var rationaleCalls = 0;

    final result = await access.choose(
      confirmPermission: () async {
        rationaleCalls += 1;
        return true;
      },
    );

    expect(result.status, LibraryRootChoiceStatus.selected);
    expect(result.path, '/storage/emulated/0/Comics');
    expect(rationaleCalls, 0);
    expect(permission.requestCalls, 0);
    expect(picker.calls, 1);
  });

  test('cancelling the rationale does not request or pick', () async {
    final permission = _PermissionAdapter(granted: false);
    final picker = _DirectoryPicker('/should/not/be/used');
    final access = LibraryRootAccess(permission: permission, picker: picker);

    final result = await access.choose(confirmPermission: () async => false);

    expect(result.status, LibraryRootChoiceStatus.rationaleCancelled);
    expect(permission.requestCalls, 0);
    expect(picker.calls, 0);
  });

  test('denied authorization does not open the picker', () async {
    final permission = _PermissionAdapter(
      granted: false,
      grantedAfterRequest: false,
    );
    final picker = _DirectoryPicker('/should/not/be/used');
    final access = LibraryRootAccess(permission: permission, picker: picker);

    final result = await access.choose(confirmPermission: () async => true);

    expect(result.status, LibraryRootChoiceStatus.authorizationDenied);
    expect(permission.requestCalls, 1);
    expect(picker.calls, 0);
  });

  test('cancelling directory selection returns a finite outcome', () async {
    final access = LibraryRootAccess(
      permission: _PermissionAdapter(granted: true),
      picker: _DirectoryPicker(null),
    );

    final result = await access.choose(confirmPermission: () async => true);

    expect(result.status, LibraryRootChoiceStatus.pickerCancelled);
    expect(result.path, isNull);
  });

  test('granting authorization returns the selected path', () async {
    final permission = _PermissionAdapter(
      granted: false,
      grantedAfterRequest: true,
    );
    final picker = _DirectoryPicker('/storage/emulated/0/Books');
    final access = LibraryRootAccess(permission: permission, picker: picker);

    final result = await access.choose(confirmPermission: () async => true);

    expect(result.status, LibraryRootChoiceStatus.selected);
    expect(result.path, '/storage/emulated/0/Books');
    expect(permission.requestCalls, 1);
    expect(picker.calls, 1);
  });
}

class _PermissionAdapter implements AllFilesAccessAdapter {
  _PermissionAdapter({required this.granted, this.grantedAfterRequest = false});

  bool granted;
  final bool grantedAfterRequest;
  int requestCalls = 0;

  @override
  Future<bool> isGranted() async => granted;

  @override
  Future<bool> request() async {
    requestCalls += 1;
    granted = grantedAfterRequest;
    return granted;
  }
}

class _DirectoryPicker implements LibraryDirectoryPicker {
  _DirectoryPicker(this.path);

  final String? path;
  int calls = 0;

  @override
  Future<String?> pickDirectory() async {
    calls += 1;
    return path;
  }
}
