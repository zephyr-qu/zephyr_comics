# Zephyr Comics

Zephyr Comics 是一个个人自用的离线 Android 漫画阅读器，用于阅读本地的 CBZ 与 ZIP 压缩包。Flutter 负责产品界面与功能模块，Rust 负责压缩包读取、元数据、封面缩略图与基于 SQLite 的阅读数据。

界面文案为简体中文。应用完全离线：不申请网络权限，不含分析、遥测、广告或更新检查。CBR、PDF、EPUB、WebDAV、在线书源、章节与双页拼版明确不在 MVP 范围内。

## 权威文档

- [产品需求 V2](docs/PRODUCT_REQUIREMENTS_V2.md)
- [架构 V3](docs/ARCHITECTURE_V3.md)
- [交付路线图](docs/DELIVERY_ROADMAP.md)
- [领域术语表](CONTEXT.md)
- [架构决策记录](docs/adr)

## 当前开发状态

个人 Android MVP 已功能完整：路线图的每个阶段——基线、书架、阅读记录、阅读体验、性能与 APK——都已实现并通过审查。其后的工作是品牌与启动体验打磨，因此图标、启动窗口与默认主题现在都使用应用自身浅色调色板中的黄铜印章标识。

实现可在本地构建并已提交；下方的门禁就是"绿"的定义。门禁的全部阶段当前通过：Dart 格式检查、`flutter analyze`、105 个 Flutter 测试、47 个 Rust 测试、clippy（`-D warnings`），以及 release APK 构建（约 64 MB）。

有一项明确未完成，且不属于代码缺口：真机上的性能与启动证据从未采集，它属于用户验收步骤。

## 开发

### 环境要求

- Flutter 3.44+（Dart 3.12+）。
- Rust 与 Cargo，并安装 clippy 组件：`rustup component add clippy`。
- Android SDK，需安装 API 36（`compileSdk 36`；应用 `targetSdk 35`，最低支持 API 30，即 Android 11 及以上）。
- `flutter_rust_bridge_codegen` 2.12.0：`cargo install flutter_rust_bridge_codegen --version 2.12.0`。
- LLVM：若 codegen 报告找不到 `libclang`，把 LLVM 的 `bin` 目录加入 `PATH`。

Android 应用 ID 为 `com.zephyr.comics`。release 产物是本地调试签名、用于真机测试的 APK，不用于应用商店发布。

### 生成 Flutter-Rust 绑定

FRB 绑定是生成产物、不入库：`lib/src/rust/` 与 `rust/src/frb_generated.rs` 都被忽略，而 `rust/src/lib.rs` 声明了 `mod frb_generated;`。新克隆必须先完成一次生成，否则 Rust crate 根本无法编译——在下面这条命令跑过之前，`cargo test` 会一直失败：

```powershell
flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml
```

门禁的第 2 阶段会自动完成这件事。

### 门禁

运行完整的本地门禁：

```powershell
pwsh -NoProfile -File tool/verify_mvp.ps1
```

门禁依次执行：生成绑定、`dart format` 检查、`flutter analyze`、`flutter test`、`cargo test`、`cargo clippy -D warnings`、release APK 构建。它会先重新生成绑定（这两个路径已被忽略），跑完后工作树保持干净。产物 APK 位于 `build/app/outputs/flutter-apk/app-release.apk`。

> release 构建会打印一条关于缺少 `CupertinoIcons` 字体的 tree-shaker 警告。这是 Flutter 工具链的已知缺陷（[flutter#119074](https://github.com/flutter/flutter/issues/119074)），应用自身不渲染任何 Cupertino 图标，因此可以忽略；`pubspec.yaml` 中也记录了这一点。

### 品牌资源

Android 启动器图标由 `brand/logo/icon.svg` 生成，重新导出的命令是：

```powershell
flutter test tool/export_brand_icons.dart
```

常规测试套件通过 `test/brand/launcher_icon_test.dart` 守护已提交的图标：图标缺失、尺寸错误，或不再是印章标识，都会导致测试失败。其余组合——`horizontal`、`vertical` 与独立的 mark，各有深色底与浅色底两个版本——位于 `brand/logo/`，`brand/preview.html` 可以把它们放在一起预览。

## 许可证

本项目以 MIT 许可证发布，详见 [LICENSE](LICENSE)。`rust_builder/cargokit/` 是随包分发（vendored）的第三方代码，保留其自身的许可证。

## 贡献

见 [CONTRIBUTING.md](CONTRIBUTING.md)。
