import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import '../library/library_root_access.dart';

class AndroidAllFilesAccessAdapter implements AllFilesAccessAdapter {
  const AndroidAllFilesAccessAdapter();

  static const _channel = MethodChannel('com.zephyr.comics/storage');

  @override
  Future<bool> isGranted() async {
    return await _channel.invokeMethod<bool>('isAllFilesAccessGranted') ??
        false;
  }

  @override
  Future<bool> request() async {
    return await _channel.invokeMethod<bool>('requestAllFilesAccess') ?? false;
  }
}

class FilePickerLibraryDirectoryPicker implements LibraryDirectoryPicker {
  const FilePickerLibraryDirectoryPicker();

  @override
  Future<String?> pickDirectory() => FilePicker.getDirectoryPath();
}
