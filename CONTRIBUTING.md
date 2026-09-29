# 贡献指南

感谢你有兴趣改进 Zephyr Comics。这是一个个人自用的离线 Android 漫画阅读器；下面的约定用来保证改动可被验证，也不会悄悄破坏已有行为。

## 开始之前

1. 先读 [CONTEXT.md](CONTEXT.md)。领域术语表是需求、代码、测试与界面文案共同使用的语言，术语混用会直接导致概念混用。
2. 改代码前读 [架构 V3](docs/ARCHITECTURE_V3.md)，尤其是"深层模块"与"存储归属"两节。
3. 文档与界面文案使用简体中文。不在范围内的事项见架构文档的"明确的非目标"一节。

## 环境前置

| 依赖 | 要求 |
|------|------|
| Flutter | 3.44+（Dart 3.12+） |
| Rust | Cargo，以及 clippy 组件：`rustup component add clippy` |
| Android SDK | 需安装 API 36（`compileSdk 36`；`targetSdk 35`，最低 API 30） |
| flutter_rust_bridge_codegen | 2.12.0：`cargo install flutter_rust_bridge_codegen --version 2.12.0` |
| LLVM | 仅当 codegen 报告找不到 `libclang` 时需要：把 LLVM 的 `bin` 目录加入 `PATH` |

## 门禁

提交前必须让门禁全绿：

```powershell
pwsh -NoProfile -File tool/verify_mvp.ps1
```

各阶段及其含义：

| 阶段 | 含义 |
|------|------|
| 生成 fixture | 重新生成 `test/fixtures/` 下的 CBZ/ZIP。生成是字节可复现的：定义没改时，跑完 `git status` 必须仍然干净 |
| 生成绑定 | 先清空 `lib/src/rust/` 与 `rust/src/frb_generated.rs`，再重新生成 FRB 绑定，避免陈旧产物掩盖问题 |
| Dart 格式检查 | `dart format --output=none --set-exit-if-changed lib test integration_test` |
| Flutter analyze | `flutter analyze --no-fatal-infos` |
| Flutter 测试 | `flutter test` |
| Rust 测试 | `cargo test --manifest-path rust/Cargo.toml` |
| clippy | `cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings` |
| release APK | `flutter build apk --release`，产物在 `build/app/outputs/flutter-apk/app-release.apk` |

两类已知噪声：

- release 构建会打印一条缺少 `CupertinoIcons` 字体的 tree-shaker 警告。这是 Flutter 工具链的已知缺陷（[flutter#119074](https://github.com/flutter/flutter/issues/119074)），应用自身不渲染任何 Cupertino 图标，因此可以忽略；不要为了消除它而重新引入 `cupertino_icons` 依赖。
- 真机性能与启动证据（首屏 1.5 秒、连续 100 页、内存 300 MB 目标）只能由人在真机上采集，不属于自动化门禁。改动涉及阅读器性能时，请写明你测了什么、怎么测的。

## 提交信息

使用英文 Conventional Commits：

```text
<type>(<scope>): <summary>

<body：说明为什么这样改，而不只是改了什么>
```

常用 `<type>`：`feat`、`fix`、`docs`、`refactor`、`test`、`chore`。`<scope>` 用受影响的区域名（例如 `repo`、`android`、`tool`、`brand`）。摘要用祈使句、全部小写、不加句号。

## 代码约定

- 注释跟随所在文件的既有语言，不强制统一。
- 不提交生成产物：`lib/src/rust/` 与 `rust/src/frb_generated.rs` 已被忽略。
- 依赖固定在已验证的版本范围，`pubspec.lock` 与 `rust/Cargo.lock` 入库。
- 源漫画只读：任何情况下都不要让应用删除、重命名或改写用户的文件。
- 派生数据必须可重建；清除缓存不得影响进度、历史与书签。
- SQLite 使用显式 schema 版本与向前迁移，不得以"删除重建"作为迁移手段。
- 面向用户的文案必须与实际支持的格式和功能一致，不得宣传已推迟的格式。
- Rust 的 FFI 层（`rust/src/api/`）只做编排，业务逻辑放在领域模块里。
- 不要把 `#[allow]` 用在自家代码的告警上；生成代码除外，`rust/src/lib.rs` 已为 `frb_generated` 加了隔离属性。
