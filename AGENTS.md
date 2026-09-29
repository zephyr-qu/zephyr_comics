# Zephyr Comics — 开发者与 AI 助手指引

本文件说明本仓库的职责分层、目录结构、验证方式与代码约定。产品需求、架构设计与领域术语以 `docs/` 与 `CONTEXT.md` 为准，本文件不复述它们。

## 分层职责

| 层 | 职责 | 不做 |
|----|------|------|
| Flutter（`lib/`） | 产品 UI、路由、设置、阅读会话调度、图片解码与缓存 | 不直接解析压缩包、不直接读写 SQLite |
| Rust（`rust/`） | 压缩包读取、元数据解析、封面缩略图、SQLite 持久化 | 不做页面像素解码（交给 Flutter 图片管线） |
| FRB 生成绑定 | `lib/src/rust/` 与 `rust/src/frb_generated.rs` 之间的桥 | 生成产物不入库，见 `.gitignore` |

生成的 FRB 类型属于基础设施类型，只能出现在 Dart 适配器内部；跨越功能模块接口前必须转换成产品类型。Widget 不得解析 Rust 错误字符串，功能模块负责把基础设施失败转换成有限的产品失败集合。

## 目录结构

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

rust_builder/        cargokit 打包工程（含 vendored 第三方代码，勿逐个改动）
tool/                本地脚本：品牌图标导出、门禁
test/ integration_test/ test_driver/    测试
brand/logo/          品牌矢量资源
docs/                PRD、架构、路线图、ADR
```

Rust 侧按域组织：小而稳定的模块保持 `rust/src/` 下单文件，成组的实现关注点放入带 `mod.rs` 的目录。不要在 `api/` 里堆业务逻辑。`lib.rs` 中 `archive_cache`、`library_db`、`library_scanner`、`reading_progress` 四个兼容别名模块服务于生成的绑定，除非重新生成并验证集成，否则必须保持可解析。

## 验证

唯一门禁命令（依次执行：生成绑定 → `dart format` 检查 → `flutter analyze` → `flutter test` → `cargo test` → `cargo clippy -D warnings` → release APK 构建）：

```powershell
pwsh -NoProfile -File tool/verify_mvp.ps1
```

门禁通过后 `git status --porcelain` 必须为空：门禁只重新生成被忽略的绑定产物，不应该弄脏任何受跟踪文件。

前置依赖：Flutter 3.44+（Dart 3.12+）、Rust/Cargo 及 `clippy` 组件（`rustup component add clippy`）、Android SDK（API 36）、`flutter_rust_bridge_codegen` 可执行文件、LLVM（`llvm-config` 需在 `PATH` 上）。详见 `CONTRIBUTING.md`。

`lib/src/rust/` 与 `rust/src/frb_generated.rs` 不入库，新克隆在 `cargo test` 前必须先跑一次绑定生成（门禁的第 1 阶段会做）。

## 代码约定

- 提交信息使用英文 Conventional Commits。
- 新增注释跟随所在文件的既有语言（现有 Rust 与 Dart 源码注释为中文），不强制统一。
- 依赖固定在已验证的版本范围，`pubspec.lock` 与 `rust/Cargo.lock` 入库。
- SQLite 使用显式 schema 版本与向前迁移；升级不得以「删除重建」作为迁移手段。
- 源漫画文件只读：应用永不删除、重命名、移动或改写用户的源文件。
- 派生数据（封面、缩略图）必须可重建，可随时清除而不影响进度、历史与书签。
- 面向用户的文案为简体中文，且必须与实际支持的格式和功能一致，不得宣传已推迟的格式。
- 不为尚未到来的需求过度设计：接缝只在生产实现与测试替身都有价值处设立。

## 关于 Trellis

本仓库历史上由 Trellis 工作流管理；本地 AI 工具目录（`.trellis/`、`.agents/`、`.pi/`、`.codex/`）已从版本控制中移出（仅保留在本地磁盘），相关指引不再属于本仓库。若再次运行 `trellis update`，它会把托管的指引块写回本文件，请重写为纯项目指引后再提交。
