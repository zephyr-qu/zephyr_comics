import 'package:flutter/services.dart';

final class AndroidScreenAwakeAdapter {
  const AndroidScreenAwakeAdapter();

  static const _channel = MethodChannel('com.zephyr.comics/settings');

  Future<void> setEnabled(bool enabled) async {
    await _channel.invokeMethod<void>('setKeepScreenAwake', {
      'enabled': enabled,
    });
  }
}
