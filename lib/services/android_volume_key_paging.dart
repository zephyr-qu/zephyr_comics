import 'package:flutter/services.dart';

final class AndroidVolumeKeyPagingAdapter {
  const AndroidVolumeKeyPagingAdapter();

  static const channel = MethodChannel('com.zephyr.comics/volume_keys');

  Future<void> setEnabled(bool enabled) async {
    await channel.invokeMethod<void>('setVolumeKeyPaging', {
      'enabled': enabled,
    });
  }

  Future<void> setReaderActive(bool active) async {
    await channel.invokeMethod<void>('setReaderActive', {'active': active});
  }
}
