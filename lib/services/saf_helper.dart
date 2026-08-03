import 'package:flutter/services.dart';

/// SAF (Storage Access Framework) 辅助工具
///
/// 用于在 Android 11+ 上通过 SAF content URI 扫描和读取文件目录。
class SAFHelper {
  static const _channel = MethodChannel('com.example.zephyr_comics/saf');

  /// 使用 SAF 打开系统目录选择器
  ///
  /// 返回 { treeUri, path }，其中 treeUri 是 SAF content URI（用于后续文件操作），
  /// path 是对应的文件系统路径（仅供参考，不可直接读写）。
  ///
  /// 返回 null 表示用户取消了选择。
  static Future<Map<String, String>?> pickDirectory() async {
    try {
      final result = await _channel.invokeMethod<Map>('pickDirectory');
      if (result == null) return null;
      return {
        'treeUri': result['treeUri'] as String,
        'path': result['path'] as String,
      };
    } on MissingPluginException {
      print('[SAF] MethodChannel 未注册（非 Android 平台）');
      return null;
    } catch (e) {
      print('[SAF] pickDirectory 失败: $e');
      return null;
    }
  }

  /// 列出 SAF 目录中的所有 .cbz/.cbr/.zip 文件
  static Future<List<String>> listCbzFiles(String uri) async {
    try {
      final result = await _channel.invokeMethod<List>('listCbzFiles', {
        'uri': uri,
      });
      return result?.cast<String>() ?? [];
    } on MissingPluginException {
      print('[SAF] MethodChannel 未注册（非 Android 平台）');
      return [];
    } catch (e) {
      print('[SAF] 列出文件失败: $e');
      return [];
    }
  }

  /// 将 SAF 文件复制到应用缓存目录
  static Future<String?> copyToCache(String uri) async {
    try {
      return await _channel.invokeMethod<String>('copyToCache', {'uri': uri});
    } on MissingPluginException {
      print('[SAF] MethodChannel 未注册（非 Android 平台）');
      return null;
    } catch (e) {
      print('[SAF] 复制到缓存失败: $e');
      return null;
    }
  }

  /// 检查路径是否为 SAF content URI
  static bool isContentUri(String path) {
    return path.startsWith('content://');
  }

  /// 通过 SAF 扫描目录，找到所有漫画文件并复制到缓存
  ///
  /// [treeUri] 是 pickDirectory() 返回的 content URI
  /// 返回本地缓存文件路径列表
  static Future<List<String>> scanAndCacheDirectory(String treeUri) async {
    if (!isContentUri(treeUri)) return [];

    print('[SAF] 开始通过 SAF 扫描: $treeUri');
    final cbzUris = await listCbzFiles(treeUri);
    if (cbzUris.isEmpty) {
      print('[SAF] 未找到漫画文件');
      return [];
    }

    print('[SAF] 找到 ${cbzUris.length} 个文件，开始复制到缓存...');
    final localPaths = <String>[];
    for (int i = 0; i < cbzUris.length; i++) {
      print('[SAF] 复制 ${i + 1}/${cbzUris.length}...');
      final localPath = await copyToCache(cbzUris[i]);
      if (localPath != null) {
        localPaths.add(localPath);
      }
    }

    return localPaths;
  }
}
