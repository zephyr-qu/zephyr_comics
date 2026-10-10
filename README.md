<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="brand/logo/vertical.svg">
    <img src="brand/logo/vertical-light.svg" alt="Zephyr Comics" width="240">
  </picture>
</p>

# Zephyr Comics

简体中文 | [English](README.en.md)

Zephyr Comics 是一个离线 Android 漫画阅读器：整理并阅读你设备本地的 CBZ 与 ZIP 压缩包。Flutter 负责界面、路由、设置与阅读会话调度，Rust 负责压缩包读取、元数据解析、封面缩略图与基于 SQLite 的阅读数据持久化。界面文案为简体中文。release 产物完全离线——不申请网络权限，不含分析、遥测、广告、更新检查或后台上传。

这是一个由单人开发、现已公开的个人项目：功能按 MVP 范围完成并通过本地门禁，公开时按原样提供，没有商业支持承诺。

## 特性

- **书架**：选择漫画根目录后递归扫描，响应式封面网格，标题搜索，按最近阅读 / 最近加入 / 标题排序，下拉刷新与扫描状态反馈，重复刷新下稳定的去重。
- **漫画详情**：封面、标题、压缩包格式、页数、当前进度与读完状态，继续阅读与从头阅读，书签列表，带确认的重置进度操作。
- **阅读器**：五种阅读模式——单页、左开、右开、连续、条漫；页码滑块直接跳转；为当前页添加或移除书签；全屏切换。切换模式保留当前页与阅读会话。
- **阅读记录**：按最后阅读时间排序的历史，记录每本漫画的最后当前页，重新打开时恢复合法页码；移除历史条目不影响进度与书签。
- **设置**：漫画根目录、启动自动刷新、默认阅读模式、阅读时屏幕常亮、音量键翻页、显示页码、屏幕方向、主题、阅读页背景，以及派生缓存大小显示与清除。
- **隐私与权限**：release 产物完全离线，唯一的 Android 权限是「所有文件访问」（`MANAGE_EXTERNAL_STORAGE`），用于直接读取你选择的漫画根目录；debug/profile 构建会按 Flutter 工具链的默认行为额外带上 `INTERNET` 以供热重载，该权限不进入 release 产物。漫画内容、路径与阅读记录永远不会离开设备。派生封面与缩略图可随时清除，且不影响进度、历史与书签。
- **源文件只读**：应用从不删除、重命名、移动或改写你的漫画文件。

## 支持与不支持的内容

**包含**

- 压缩包格式：CBZ 与 ZIP。
- 页面图片格式：JPEG、PNG 与 WebP。
- 一个压缩包即一本漫画，即一条连续的页面序列。
- 页面在压缩包内被递归发现；隐藏条目与系统资源条目（如 `.` 开头的条目、`__MACOSX`）被忽略；页面按完整路径自然排序。

**不支持（推迟）**

- CBR/RAR、PDF、EPUB、AVIF、动图 GIF、BMP 与 TIFF。
- 章节、双页拼版、自动跨页识别与跨设备同步。
- WebDAV、在线书源、账号、遥测、更新检查与云端备份。

不受支持的格式会被诚实地拒绝并给出清晰提示，不会作为可用功能宣传。

## 当前状态

2026-10-10 使用 Flutter 3.47.2 / Dart 3.13.2 实测，以下命令全部通过：

```text
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze --no-fatal-infos
flutter test                 # 105 通过
cargo test --manifest-path rust/Cargo.toml          # 49 通过
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
flutter build apk --release  # 成功
```

上表由 `tool/verify_mvp.ps1` 一次性完成；测试数量会随提交变化，此处记录的是上述日期实测值，不是长期承诺。release APK 体积随工具链浮动，因此不在此写死。

这些数字只出现在本节；其余小节不重复。

两项已知缺口，都不属于代码缺陷：

- 真机性能与启动证据从未采集（首个可见页面 1.5 秒、连续阅读 100 页、内存 300 MB 目标）——只能由人在真机上采集，属于用户验收步骤。
- 真实的 Flutter → FRB → Rust → 图片路径不在默认门禁的覆盖范围内：`integration_test/reader_performance_test.dart` 走这条路径并断言首屏 1.5 秒预算，但必须手工提供 CBZ（`READER_BENCHMARK_CBZ`）才启用，否则整个测试被跳过；端到端读取在真机阅读流程中被验证。

本仓库不发布预编译 APK，也没有应用商店页面：阅读器请按下一节在本地构建。

## 构建与运行

### 环境要求

| 依赖 | 要求 |
|------|------|
| Flutter | 3.44+（Dart 3.12+）；本仓库 `pubspec.yaml` 强制最低 Dart `^3.10.9`，本机实测 Flutter 3.47.2 / Dart 3.13.2 |
| Rust | Cargo，以及 clippy 组件：`rustup component add clippy` |
| Android SDK | 需安装 API 36（`compileSdk 36`；`targetSdk 35`，最低 API 30，即 Android 11 及以上） |
| flutter_rust_bridge_codegen | 2.12.0：`cargo install flutter_rust_bridge_codegen --version 2.12.0` |
| LLVM | 仅当 codegen 报告找不到 `libclang` 时需要：把 LLVM 的 `bin` 目录加入 `PATH` |

Android 应用 ID 为 `com.zephyr.comics`。release 产物使用本地调试签名，用于真机测试，不用于应用商店发布。

### 生成 Flutter-Rust 绑定

FRB 绑定是生成产物、不入库：`lib/src/rust/` 与 `rust/src/frb_generated.rs` 都被忽略，而 `rust/src/lib.rs` 声明了 `mod frb_generated;`。新克隆必须先完成一次生成，否则 Rust crate 无法编译——在下面这条命令跑过之前，`cargo test` 会一直失败：

```powershell
flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml
```

### 门禁

运行完整本地门禁：

```powershell
pwsh -NoProfile -File tool/verify_mvp.ps1
```

门禁依次执行七个阶段：生成绑定、`dart format` 检查、`flutter analyze`、`flutter test`、`cargo test`、`cargo clippy -D warnings`、release APK 构建。它先重新生成被忽略的绑定，跑完后工作树保持干净。产物 APK 位于 `build/app/outputs/flutter-apk/app-release.apk`。

> release 构建会打印一条关于缺少 `CupertinoIcons` 字体的 tree-shaker 警告。这是 Flutter 工具链的已知缺陷（[flutter#119074](https://github.com/flutter/flutter/issues/119074)），应用自身不渲染任何 Cupertino 图标，因此可以忽略；不要为了消除它而重新引入 `cupertino_icons` 依赖，`pubspec.yaml` 中也记录了这一点。

### 品牌资源

Android 启动器图标由 `brand/logo/icon.svg` 生成，重新导出的命令是：

```powershell
flutter test tool/export_brand_icons.dart
```

`test/brand/launcher_icon_test.dart` 守护已提交的图标：图标缺失、尺寸错误或不再是印章标识都会导致测试失败。其余组合——`horizontal`、`vertical` 与独立的 mark，各有深色底与浅色底版本——位于 `brand/logo/`。

## 项目结构

```text
lib/                 Flutter 应用
├── models/          产品数据模型
├── library/         ComicLibrary：根目录、扫描、去重、搜索排序
├── reader/          ReaderSession / ReaderEngine：打开、翻页、进度、预取
├── reading/         ReadingRecords：历史、书签、完成状态
├── settings/        AppSettings：用户可见偏好与默认值
├── services/        Android 平台适配（权限、音量键、屏幕常亮、偏好存储）
├── views/           路由页面与 Widget
├── router/ theme/ utils/ signals/
└── main.dart app.dart

rust/src/            Rust 后端
├── api/             FFI 入口（flutter_rust_bridge），仅编排
├── archive.rs       CBZ/ZIP 读取
├── cache/           已打开 ZIP 句柄 + 页表缓存
├── library/         db.rs / scanner.rs / progress.rs
├── metadata.rs      ComicInfo.xml 与封面缩略图
├── sort.rs types.rs error.rs lib.rs

rust_builder/        cargokit 打包工程（含 vendored 第三方代码）
tool/                本地脚本：品牌图标导出、门禁
test/ integration_test/ test_driver/    测试
brand/logo/          品牌矢量资源
docs/                PRD、架构、路线图、ADR
```

`lib/` 与 `rust/` 的职责边界：Flutter 不直接解析压缩包、不直接读写 SQLite；Rust 不做页面像素解码，页面以压缩包内的原始编码字节交给 Flutter，在显示尺寸上解码。

## 文档

- [产品需求 V2](docs/PRODUCT_REQUIREMENTS_V2.md) —— 权威 MVP 需求与验收定义
- [架构 V3](docs/ARCHITECTURE_V3.md) —— 分层、数据路径、存储归属、测试策略与明确的非目标
- [交付路线图](docs/DELIVERY_ROADMAP.md) —— 阶段划分与当前进展
- [领域术语表](CONTEXT.md) —— 需求、代码、测试与界面文案共用的语言
- [架构决策记录](docs/adr) —— 逐条决策及其背景
- [贡献指南](CONTRIBUTING.md) —— 环境、门禁、提交信息与代码约定

## 许可证

本项目以 MIT 许可证发布，详见 [LICENSE](LICENSE)，Copyright (c) 2026 Zephyr。

`rust_builder/cargokit/` 是随包分发（vendored）的第三方代码（Flutter Rust Bridge 官方的集成方式），Copyright 2022 Matej Knopp，采用 MIT OR Apache-2.0 双许可证，许可证原文保留在 [rust_builder/cargokit/LICENSE](rust_builder/cargokit/LICENSE)。Dart 与 Rust 依赖各自的许可证随其包分发，此处不逐一罗列。

## 贡献

见 [CONTRIBUTING.md](CONTRIBUTING.md)。提交前请让 `pwsh -NoProfile -File tool/verify_mvp.ps1` 全绿，并使用英文 Conventional Commits。
