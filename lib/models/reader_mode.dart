enum ReaderMode {
  vertical,
  ltr,
  rtl,
  verticalContinuous,
  webtoon;

  /// The prototype's own five labels (`SA_MODES`), shared by the settings row
  /// and the reader drawer so the two controls name the same thing the same way.
  String get label {
    return switch (this) {
      ReaderMode.vertical => '单页',
      ReaderMode.ltr => '左开',
      ReaderMode.rtl => '右开',
      ReaderMode.verticalContinuous => '连续',
      ReaderMode.webtoon => '条漫',
    };
  }

  String get storageValue => name;
  static ReaderMode fromStorage(String value) {
    return ReaderMode.values.firstWhere(
      (m) => m.name == value,
      orElse: () => ReaderMode.vertical,
    );
  }
}
