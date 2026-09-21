import 'dart:async';

import '../services/android_volume_key_paging.dart';

abstract interface class ReaderVolumeKeys {
  void start(void Function(bool next) onPressed);

  void stop();
}

final class AndroidReaderVolumeKeys implements ReaderVolumeKeys {
  const AndroidReaderVolumeKeys();

  @override
  void start(void Function(bool next) onPressed) {
    AndroidVolumeKeyPagingAdapter.channel.setMethodCallHandler((call) async {
      if (call.method != 'volumeKeyPressed') return;
      switch (call.arguments) {
        case 'up':
          onPressed(true);
        case 'down':
          onPressed(false);
      }
    });
    unawaited(const AndroidVolumeKeyPagingAdapter().setReaderActive(true));
  }

  @override
  void stop() {
    AndroidVolumeKeyPagingAdapter.channel.setMethodCallHandler(null);
    unawaited(const AndroidVolumeKeyPagingAdapter().setReaderActive(false));
  }
}
