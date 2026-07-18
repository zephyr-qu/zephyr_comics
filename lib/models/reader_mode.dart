enum ReaderMode {
  vertical,
  ltr,
  rtl,
  verticalContinuous,
  webtoon;

  String get label {
    return switch (this) {
      ReaderMode.vertical => '单页垂直',
      ReaderMode.ltr => '从左到右',
      ReaderMode.rtl => '从右到左',
      ReaderMode.verticalContinuous => '连续滚动',
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
