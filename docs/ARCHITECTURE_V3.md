# Zephyr Comics 架构 V3

> 状态：个人 Android MVP 的权威目标架构  
> 取代：更早的 V1 需求/设计文档与 `ARCHITECTURE_V2.md`，后者已从仓库中移除；其内容已被本文档完全取代。

## 1. 架构驱动因素

- 直接读取大型本地 CBZ/ZIP 压缩包，不把它们复制进缓存。
- 让源漫画保持只读，让派生数据保持可恢复。
- 对 Widget 隐藏 FRB、SQLite、权限、压缩包、缓存与调度的细节。
- 在长时间阅读会话中让内存与并发工作保持有界。
- 让产品流程能通过与 Widget 相同的接口被测试。
- 产出适用于 Android 11+ 的离线 release APK。

## 2. 系统形态

```text
Flutter Widgets
  -> feature module interfaces
       -> Dart adapters at local seams
            -> generated FRB bindings
                 -> Rust archive, metadata, and SQLite implementations
  -> Android filesystem permission adapter
  -> SharedPreferences adapter for user settings
```

生成的 FRB 类型属于基础设施类型。它们只能出现在 Dart 适配器内部，跨越功能模块接口之前必须转换成产品类型。

## 3. 深层模块

### ComicLibrary

ComicLibrary 模块拥有漫画根目录配置、权限状态、增量扫描、去重、元数据/封面刷新、搜索、排序、缺失文件核对与书架错误归一化。

它面向 Widget 的接口暴露书架状态与用户操作，例如选择根目录、刷新、搜索与排序。Widget 不会为了完成一次刷新而调用多个 FRB 函数。

内部接缝：

- Android 文件系统权限/路径适配器。
- Rust 书架引擎适配器。
- SharedPreferences 根目录/设置适配器。
- 测试使用的内存适配器。

### ReaderSession

ReaderSession 拥有打开漫画、页数、进度恢复、页面加载、请求去重、有界的方向性预取、重试、当前页移动、进度持久化、完成，以及关闭/刷出行为。

既有的 `ReaderEngine` 接缝是真实存在的，因为生产环境使用 FRB 适配器而测试使用内存适配器。Widget 只接收产品类型与编码页面字节。

### ReadingRecords

ReadingRecords 拥有阅读历史、书签、读完状态与进度重置语义。它向详情/历史/阅读器界面呈现同一个产品接口，并把 SQLite 调用、schema 版本与迁移行为隐藏在适配器之后。

进度、历史与书签即使共用同一份数据库实现，也仍然是彼此不同的领域概念。

### AppSettings

AppSettings 拥有用户可见的偏好及其默认值：自动刷新、默认阅读模式、屏幕常亮、音量键、页码、屏幕方向、主题与阅读页背景。内部性能策略不属于它的接口。

## 4. 页面数据路径

```text
ReaderScreen requests Page N
  -> ReaderSession deduplicates and prioritizes the request
  -> ReaderEngine.loadPageEncoded
  -> Rust locates the naturally sorted archive entry
  -> original JPEG/PNG/WebP bytes cross FRB
  -> Flutter decodes to a viewport-sized image
  -> bounded prefetch prepares neighboring pages
```

产品路径不会在 Rust 中解码为 RGBA 再重新编码成 PNG。它也不要求一个已解压的源页面文件缓存。Flutter 的解码图片缓存与 ReaderSession 的编码字节缓存彼此独立、各自有界。

## 5. 书架数据路径

```text
authorized Library Root
  -> recursive path discovery for CBZ/ZIP
  -> normalized path + size + modified time comparison
  -> unchanged entries reused
  -> changed/new archives inspected by Rust
  -> ComicInfo metadata and front cover resolved
  -> aspect-preserving Derived Cover generated
  -> SQLite upsert preserves durable reading fields
  -> LibrarySnapshot published once per refresh
```

失败的扫描不会发布一个破坏性的空书架。只有在一次成功的、已授权的扫描之后，才会对源文件消失做核对。

## 6. 存储归属

- 源漫画：用户所有，只读，应用绝不删除。
- 书架数据库：应用所有的持久派生元数据与阅读记录。
- SharedPreferences：应用所有的用户偏好与漫画根目录。
- 派生缓存：应用所有、可重建，仅含封面/缩略图。

SQLite 使用显式 schema 版本与向前迁移。应用升级绝不把"删除重建"当作迁移策略。

## 7. 状态与生命周期

- 应用级全局状态仅限于跨路由使用的数据：ComicLibrary 状态与 AppSettings。
- ReaderSession 按阅读路由创建，并在该路由被销毁时关闭。
- 控制器、工具栏状态与临时对话框保持为 Widget 局部状态。
- 异步完成在发布状态之前检查模块生命周期。
- 新的可见页面工作优先于推测性预取；已过期的排队工作被取消，再次变得相关的进行中工作被共享。

## 8. 错误模型

功能模块把基础设施失败转换成有限的产品失败：

- 需要授权或授权被撤销；
- 漫画根目录缺失；
- 不支持的压缩包或页面格式；
- 损坏的压缩包或页面；
- 页码越界；
- 数据库/迁移失败；
- 派生封面失败；
- 未预期的失败。

致命打开失败、页面级失败、可恢复的书架警告与持久化警告的呈现方式各不相同。Widget 不解析 Rust 错误字符串。

## 9. 测试策略

- 领域与调度行为在功能模块接口上、用内存适配器测试。
- 压缩包、排序、元数据、缩略图与迁移行为在 Rust 中测试；每个测试在临时目录自行构造 CBZ/ZIP，仓库不存放二进制 fixture。
- Widget 测试覆盖路由状态与用户操作，而不是模块私有状态。
- 仅在真机上运行的 profile/release 检查覆盖首屏延迟、滚动与内存峰值。

真实的 Flutter -> FRB -> Rust -> 图片路径目前没有自动化覆盖：集成测试只做应用启动的冒烟检查，端到端读取只在真机上的 profile/release 阅读流程中被验证。

当深层模块接口已经覆盖了同样的行为时，测试会替换掉过时的浅层路径测试。

## 10. Android 与发布约束

- `minSdk 30`、`targetSdk 35`，应用 ID `com.zephyr.comics`。
- "所有文件访问"是 MVP 唯一的书架访问模型；没有 SAF 兜底方案。
- 没有网络权限，也没有依赖网络的运行时行为。
- 依赖固定在已验证的版本范围，且 `pubspec.lock` 入库。
- 一条本地验证命令完成格式检查、静态分析、测试与 release APK 构建。

## 11. 明确的非目标

- 为"所有文件访问"做 Google Play 合规。
- 多根目录书架、文件修改、应用内删除源文件或编辑压缩包。
- CBR/RAR/PDF/EPUB、章节、双页拼版、在线书源、WebDAV 或云备份。
- 围绕 Rust 接口构建通用框架；接缝只在生产实现与测试替身都有价值处设立。
