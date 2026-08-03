import 'package:flutter/material.dart';
import '../../library/library_root_access.dart';
import '../../signals/app_signals.dart';

Future<void> chooseLibraryRootFrom(BuildContext context) async {
  final result = await chooseAndSetLibraryRoot(
    confirmPermission: () => _showPermissionRationale(context),
  );
  if (!context.mounted) return;

  switch (result.status) {
    case LibraryRootChoiceStatus.authorizationDenied:
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('未授予所有文件访问权限，无法扫描漫画目录。')));
      break;
    case LibraryRootChoiceStatus.failed:
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开目录选择器，请稍后重试。')));
      break;
    case LibraryRootChoiceStatus.selected:
    case LibraryRootChoiceStatus.rationaleCancelled:
    case LibraryRootChoiceStatus.pickerCancelled:
      break;
  }
}

Future<bool> _showPermissionRationale(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('需要访问漫画文件'),
          content: const Text(
            'Zephyr Comics 需要“所有文件访问”权限，才能直接读取你选择目录中的 CBZ/ZIP。'
            '应用完全离线，只读取漫画，不会修改、移动或删除源文件。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('暂不授权'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('去授权'),
            ),
          ],
        ),
      ) ??
      false;
}
