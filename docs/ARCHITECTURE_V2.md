> **Historical document — superseded by [ARCHITECTURE_V3.md](./ARCHITECTURE_V3.md). “最终版” no longer describes the implemented reader path.**

# 🏗️ Zephyr Comics — 架构设计文档 V2 (历史版)

| 项目 | 内容 |
| :--- | :--- |
| **项目名** | Zephyr Comics (zephyr_comics) |
| **架构** | Flutter (UI) + Rust (图像引擎) + Flutter Rust Bridge |
| **状态管理** | signals_flutter（信号驱动） |
| **图片渲染** | extended_image + 缓存文件 (Rust解码→写缓存→ExtendedImage.file)
| **路由** | GoRouter |
| **文件权限** | MANAGE_EXTERNAL_STORAGE |
| **存储** | Hive（偏好/设置）+ Rust SQLite（书架/进度/书签） |
| **主题** | 阅读器深色 + 书架自适应系统 |
| **双页** | 手机单页，平板横屏自动双页 |
| **格式** | CBZ (ZIP) |

---

## 1. 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter UI Layer                          │
│  ┌─────────────────────────────────────────────────────────┐│
│  │  状态管理: signals_flutter (信号驱动，无需 code gen)     ││
│  │  路由:     GoRouter (ShellRoute 嵌套)                   ││
│  │  存储:     Hive (阅读模式/主题/扫描路径 等轻量偏好)      ││
│  │  图片:     ExtendedImage.file / ExtendedImage.memory     ││
│  └──────────────────────┬──────────────────────────────────┘│
│                         │ flutter_rust_bridge (async/sync)   │
│  ┌──────────────────────▼──────────────────────────────────┐│
│  │                  Rust 图像引擎                           ││
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌───────────┐  ││
│  │  │ Archive  │ │ Decoder  │ │  Cache   │ │ SQLite DB │  ││
│  │  │ (CBZ解压)│ │ (jpg/png)│ │(LRU缓存) │ │(进度/书架)│  ││
│  │  └──────────┘ └──────────┘ └──────────┘ └───────────┘  ││
│  └──────────────────────┬──────────────────────────────────┘│
│                         │ File I/O                           │
│  ┌──────────────────────▼──────────────────────────────────┐│
│  │             Android 文件系统                             ││
│  │  /sdcard/Comics/*.cbz        ← 用户漫画库              ││
│  │  app_data/cache/             ← 解压缓存 + 缩略图       ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

---

## 2. 状态管理架构 (signals_flutter)

### 2.1 信号体系

```dart
// ─── 全局信号（App 级） ───

/// 漫画目录扫描路径
final scanDirectoryPath = signal('');

/// 当前阅读模式
final readerMode = signal(ReaderMode.vertical);

/// 深色模式
final isDarkMode = signal(true);

/// 是否显示页码
final showPageNumbers = signal(true);

/// 预加载数量
final preloadCount = signal(5);

// ─── 阅读器信号（每次打开阅读器创建） ───

/// 当前阅读器状态
class ReaderState {
  final int currentPage;
  final int totalPages;
  final bool isToolbarVisible;
  final bool isLoading;

  ReaderState({...});
}

/// 阅读器信号
final readerState = signal(ReaderState(...));

// ─── 书架信号 ───

/// 漫画库条目列表
final libraryEntries = signal<List<LibraryEntry>>([]);

/// 搜索关键词
final searchQuery = signal('');

/// 过滤后的条目
final filteredEntries = computed(() {
  final q = searchQuery.value.toLowerCase();
  if (q.isEmpty) return libraryEntries.value;
  return libraryEntries.value
      .where((e) => e.fileName.toLowerCase().contains(q))
      .toList();
});
```

### 2.2 在 Widget 中使用

```dart
// Watch 包裹需要响应信号的 Widget 子树
Watch((context) {
  final mode = readerMode.value;
  return Text('当前模式: $mode');
});

// 或封装成方法
Widget buildPageCounter(BuildContext context) {
  return Watch((context) {
    final state = readerState.value;
    return Text('${state.currentPage} / ${state.totalPages}');
  });
}
```

### 2.3 异步操作模式 (调 Rust 接口)

```dart
// 封装异步 FRB 调用的简单模式
Future<void> loadComic(String filePath) async {
  isLoading.value = true;
  error.value = null;
  try {
    final info = await getComicInfo(filePath: filePath);  // ← FRB
    libraryEntries.value = [info, ...libraryEntries.value];
  } catch (e) {
    error.value = e.toString();
  } finally {
    isLoading.value = false;
  }
}

// 在 Widget 中触发
ElevatedButton(
  onPressed: () => loadComic(path),
  child: Watch((_) => isLoading.value
    ? CircularProgressIndicator()
    : Text('扫描目录')),
)
```

---

## 3. 页面路由 (GoRouter)

```
ShellRoute (底部导航壳 — 3 个 Tab)
├── /library     → LibraryScreen     (📚 书架)
├── /history     → HistoryScreen     (📖 阅读历史)
└── /settings    → SettingsScreen    (⚙️ 设置)

独立页面 (push 进入)
├── /comic-detail → ComicDetailScreen  (漫画详情)
└── /reader       → ComicReaderScreen  (🎨 核心阅读器)
```

路由配置：

```dart
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/library',
    routes: [
      ShellRoute(
        builder: (_, __, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/library',  builder: (_, __) => const LibraryScreen()),
          GoRoute(path: '/history',  builder: (_, __) => const HistoryScreen()),
          GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
        ],
      ),
      GoRoute(
        path: '/comic-detail',
        builder: (_, state) => ComicDetailScreen(
          filePath: state.extra as String,
        ),
      ),
      GoRoute(
        path: '/reader',
        builder: (_, state) => ComicReaderScreen(
          filePath: state.extra as String,
        ),
      ),
    ],
  );
});
```

---

## 4. 阅读器核心设计 (参考 Mangayomi)

### 4.1 5 种阅读模式

| 模式 | 滚动方式 | 渲染组件 |
|------|---------|---------|
| `vertical` (单页垂直) | ExtendedImageGesturePageView + Axis.vertical | ImageViewVertical |
| `ltr` (从左到右) | ExtendedImageGesturePageView + Axis.horizontal | ImageViewHorizontal |
| `rtl` (从右到左) | ExtendedImageGesturePageView + Axis.horizontal + reverse | ImageViewHorizontal |
| `verticalContinuous` (连续) | ScrollablePositionedList | ImageViewVertical |
| `webtoon` (条漫) | ScrollablePositionedList + 间距 0 | ImageViewVertical |

### 4.2 阅读器 UI 结构

```
ComicReaderScreen (Stack)
│
├── 渲染区域 (根据模式切换)
│   ├── [连续模式] ScrollablePositionedList
│   │   └── ImageViewVertical (用 ExtendedImage.memory)
│   └── [翻页模式] ExtendedImageGesturePageView
│       └── ImageViewHorizontal (用 ExtendedImage.file 缓存文件)
│
├── 三区手势层 GestureDetector (透明覆盖层)
│   ├── [翻页模式]
│   │   ├── 左 1/3 → 上一页
│   │   ├── 中 1/3 → 切换工具栏
│   │   └── 右 1/3 → 下一页
│   └── [连续模式]
│       ├── 上 1/5 → 上一页
│       ├── 中 3/5 → 切换工具栏
│       └── 下 1/5 → 下一页
│
├── 顶部工具栏 (AnimatedContainer, 高度 0 ↔ 90)
│   ├── 返回按钮
│   └── 文件名 + 页码
│
├── 底部工具栏 (AnimatedContainer, 高度 0 ↔ 108)
│   ├── 上/下一章 按钮
│   ├── 页码滑块 (Slider) + 数字
│   ├── 阅读模式切换 (PopupMenuButton)
│   └── 设置入口
│
└── 页码浮层 (底部中央, 半透明)
    └── "当前页 / 总页数"
```

### 4.3 图片加载 (关键改动：Mangayomi 的 network → 本地)

```dart
// Mangayomi:   ExtendedImage.network(url, headers: headers(source))
// Zephyr:      ExtendedImage.file(cacheFile)

// 工作流：
// 用户翻到第 N 页
//   ↓
// Rust: extract & decode (压缩包 → 像素数据)
//   ↓
// Flutter: 保存为临时缓存文件
//   ↓
// ExtendedImage.file(cachePath)  ← extended_image 管理缩放/手势
//   ↓
// Rust LRU Cache 管理内存，重复翻页直接命中
### 4.3 图片加载管道 (Rust解码 → 缓存文件 → ExtendedImage.file)

```
用户翻到第 N 页
  ↓
检查缓存文件是否存在
  ├── 存在 → ExtendedImage.file(cachePath)  ← 直接显示 (手势/缩放全支持)
  └── 不存在
       ↓
      FRB: getPageImage(filePath, pageIndex, maxW, maxH)
       ↓
      Rust: 解压CBZ → 读取图片 → 解码 → 降采样 → 返回 RGBA Vec<u8>
       ↓
      Flutter: 保存缓存文件 (cacheDir/page_N.jpg)
       ↓
      ExtendedImage.file(cachePath)  ← 显示
```

#### 为什么走缓存文件而不是直接内存？

- extended_image 的 file 模式最成熟，缩放/手势/缓存全部可用
- 翻页时如果文件已在磁盘，跳过 Rust 解码（零延迟）
- 磁盘缓存由 Rust 的 disk_cache 管理，自动淘汰旧文件
- 避免 RGBA 大数据在 Dart 堆中滞留，文件由 OS 管理

```dart
Future<Widget> loadPage(int index) async {
  final cacheFile = File('$cacheDir/page_$index.jpg');
  if (await cacheFile.exists()) {
    return ExtendedImage.file(cacheFile, mode: ExtendedImageMode.gesture, ...);
  }
  // Rust 解码
  final imageData = await getPageImage(
    filePath: filePath,
    pageIndex: index,
    maxWidth: screenWidth.toInt(),
    maxHeight: screenHeight.toInt(),
  );
  // 写缓存文件
  await cacheFile.writeAsBytes(imageData.data);
  return ExtendedImage.file(cacheFile, mode: ExtendedImageMode.gesture, ...);
}
```

### 4.4 平板双页模式

```
检测到屏幕宽度 > 600dp (典型平板横屏)
  ↓
渲染模式切换为双页
  ↓
第 1-2 页并排: [左页|右页]
第 3-4 页并排: [左页|右页]
...
翻页时一次跳过两页
```

#### 双页实现要点

- 使用 LayoutBuilder 或 MediaQuery 检测屏幕宽度
- 双页时 pageIndex 以 2 为步进 (0,2,4,6...)
- 单页时 pageIndex 步进 1
- 部分漫画有跨页图 (两页合成一张)，需要额外标记不拆分
- 暂不实现跨页图自动检测 (P1 后优化)

### 4.4 阅读器信号 (signals_flutter)

```dart
// 阅读器打开时创建
class ComicReaderNotifier {
  // 状态信号
  final currentPage = signal(0);
  final totalPages = signal(0);
  final isToolbarVisible = signal(false);
  final isLoading = signal(true);
  final errorMsg = signal<String?>(null);

  // 依赖
  final String filePath;
  ComicInfo? _info;

  ComicReaderNotifier(this.filePath);

  Future<void> init() async {
    isLoading.value = true;
    try {
      _info = await getComicInfo(filePath: filePath);  // FRB
      totalPages.value = _info!.totalImages;
      // 恢复上次阅读进度
      final progress = await getReadingProgress(filePath: filePath);  // FRB
      currentPage.value = progress?.pageIndex ?? 0;
    } catch (e) {
      errorMsg.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> goToPage(int index) async {
    currentPage.value = index;
    // 异步保存进度到 Rust SQLite
    saveReadingProgress(
      ReadingProgress(filePath: filePath, pageIndex: index, ...),
    );
}
```

### 4.6 错误处理 (单页加载失败)

```
加载第 N 页时 Rust 解码失败
  ↓
catch ComicError
  ↓
显示: [图标: broken_image] [文字: 第N页加载失败] [重试按钮]
  ↓
用户点重试 → 重新调 getPageImage
  ↓
连续失败 3 次 → 显示 "无法加载此页" 灰底占位
```

```dart
Widget buildErrorPage(int index) {
  return Container(
    color: Colors.grey[900],
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.broken_image, color: Colors.grey, size: 64),
        const SizedBox(height: 8),
        Text('第 ${index+1} 页加载失败', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () => retryLoadPage(index),
          child: const Text('重试'),
        ),
      ],
    ),
  );
}
```

  Future<Uint8List> getPageImage(int index, int w, int h) async {
    // Rust: 从压缩包提取 → 解码 → 降采样 → 返回 RGBA
    final data = await getPageImage(filePath: filePath, pageIndex: index, maxWidth: w, maxHeight: h);
    return Uint8List.fromList(data.data);
  }
}
### 4.5 阅读器信号 (signals_flutter)

---

## 5. 书架 + 漫画详情

### 5.1 书架 LibraryScreen

```
┌──────────────────────────────────┐
│  AppBar: "Zephyr"  [🔍] [➕]     │
├──────────────────────────────────┤
│  ┌────┐ ┌────┐ ┌────┐ ┌────┐   │
│  │ 📚 │ │ 📚 │ │ 📚 │ │ 📚 │   │  GridView 封面网格
│  │    │ │    │ │    │ │    │   │
│  └────┘ └────┘ └────┘ └────┘   │
│  ┌────┐ ┌────┐                  │
│  │ 📚 │ │ 📚 │                  │
│  └────┘ └────┘                  │
├──────────────────────────────────┤
│  [书架]  [历史]  [设置]          │
└──────────────────────────────────┘
```

## 5. 书架 + 漫画详情 + 空状态

### 5.0 首次启动空状态

```
检测到 scanPath 为空 (首次启动)
  ↓
LibraryScreen 显示空状态:
┌──────────────────────────┐
│                          │
│      📚                  │
│  还没有漫画              │
│                          │
│  ┌──────────────────┐   │
│  │  选择漫画目录     │   │  ← 大按钮
│  └──────────────────┘   │
│                          │
└──────────────────────────┘
  ↓
点击按钮 → 系统文件选择器 或 手动输入路径
  ↓
保存路径到 Hive: scanPath
  ↓
调 FRB: scanDirectory(path) → 填充书架
```

### 5.1 书架 LibraryScreen
- 长按 → 从书架移除
- 点击 → 跳转 ComicDetailScreen

### 5.2 详情 ComicDetailScreen

```
┌──────────────────────────────────┐
│  ← 返回                          │
├──────────────────────────────────┤
│  ┌────────────┐                  │
│  │   封面大图   │  文件名.cbz      │
│  │            │  大小: 158MB      │
│  │            │  页数: 198        │
│  └────────────┘  上次读到: 45页   │
│                                  │
│  ┌────────────────────────────┐  │
│  │       ▶ 继续阅读           │  │
│  └────────────────────────────┘  │
│                                  │
│  [从书架移除]  [标记已读]         │
└──────────────────────────────────┘
```

### 5.3 书架数据流

```
App 启动 / 用户点"扫描"
  ↓
用户设置路径: /sdcard/Comics/
  ↓ (保存到 Hive)
Flutter 调 FRB: scanDirectory(path: "/sdcard/Comics/")
  ↓
Rust 遍历目录下所有 *.cbz
  ↓  逐个文件调用 getComicInfo (页数/文件名)
Rust SQLite: 写入 library_entries
  ↓
Flutter: libraryEntries.value = 结果
  ↓ 显示封面网格
Gridview → 每个卡片调 generateThumbnail(filePath, 200)
  ↓
Rust: 解压第一页 → 缩放到 200px → 返回 PNG
Flutter: Image.memory(pngData)
```

---

## 6. 存储分工

### Hive (Flutter 侧) — 轻量偏好

| Key | 类型 | 说明 |
|-----|------|------|
| `scanPath` | String | 漫画目录路径 |
| `readerMode` | String | 全局阅读模式 |
| `isDarkMode` | bool | 深色模式 |
| `showPageNumbers` | bool | 显示页码 |
| `preloadCount` | int | 预加载页数 |
| `firstRun` | bool | 首次运行标记 |

### Rust SQLite — 核心数据

| 表 | 字段 | 说明 |
|----|------|------|
| `library_entries` | filePath, fileName, fileSize, pageCount, dateAdded, lastOpened | 书架条目 |
| `reading_progress` | filePath, chapterIndex, pageIndex, timestamp | 阅读进度 |
| `bookmarks` | filePath, pageIndex, note, createdAt | 书签 |

---

## 7. 目录结构

```
zephyr_comics/
│
├── lib/                              # Flutter 代码
│   ├── main.dart                     # 入口 + RustLib.init()
│   ├── app.dart                      # MaterialApp.router + 主题
│   │
│   ├── src/
│   │   └── rust/                     # FRB 生成的 Dart (自动)
│   │
│   ├── router/
│   │   └── router.dart               # GoRouter 配置
│   │
│   ├── signals/                      # 全局信号定义
│   │   ├── app_signals.dart          # 全局信号 (readerMode, scanPath...)
│   │   └── reader_signals.dart       # 阅读器信号 (currentPage...)
│   │
│   ├── models/
│   │   └── reader_mode.dart          # ReaderMode 枚举
│   │
│   ├── views/
│   │   ├── library/
│   │   │   ├── library_screen.dart   # 书架
│   │   │   └── widgets/
│   │   │       └── comic_card.dart   # 封面卡片
│   │   │
│   │   ├── detail/
│   │   │   └── comic_detail_screen.dart  # 漫画详情
│   │   │
│   │   ├── reader/
│   │   │   ├── comic_reader_screen.dart  # 阅读器主容器 (Stack)
│   │   │   ├── image_view_vertical.dart  # 垂直模式单页
│   │   │   ├── image_view_horizontal.dart # 水平模式单页
│   │   │   ├── reader_toolbar.dart       # 底部工具栏
│   │   │   └── reader_gesture.dart       # 三区手势
│   │   │
│   │   ├── history/
│   │   │   └── history_screen.dart
│   │   │
│   │   └── settings/
│   │       └── settings_screen.dart      # 设置 + 目录选择
│   │
│   └── utils/
│       └── constants.dart
│
├── rust/                              # Rust 图像引擎
│   ├── Cargo.toml
│   └── src/
│       ├── lib.rs
│       ├── api/comic.rs              # FRB 导出 (已实现)
│       ├── archive.rs                # CBZ 解压
│       ├── decoder.rs                # 图片解码
│       ├── cache.rs                  # LRU 内存缓存
│       ├── disk_cache.rs             # 磁盘缓存
│       ├── sort.rs                   # 自然排序
│       ├── types.rs                  # 数据类型
│       ├── error.rs                  # 错误类型
│       ├── library_db.rs             # SQLite 书架/进度
│       ├── library_scanner.rs        # 目录扫描
│       ├── reading_progress.rs       # 阅读进度
│       ├── preload_strategy.rs       # 预加载策略
│       └── archive_cache.rs          # 压缩包句柄缓存
│
├── rust_builder/                      # FRB 构建
├── docs/
│   ├── 需求规格说明书 V1.0.md
│   ├── 开发设计文档 V1.0.md
│   ├── ARCHITECTURE_V2.md            # ← 本文档
│   └── PDF_SETUP.md
│
├── pubspec.yaml
└── flutter_rust_bridge.yaml
```

---

## 8. 技术栈汇总

| 层面 | 技术 | 选择理由 |
|------|------|---------|
| **UI** | Flutter + Material 3 | 跨平台 |
| **状态** | signals_flutter | 简单、零代码生成、足够用 |
| **路由** | GoRouter | ShellRoute 底部导航 |
| **图片** | extended_image | 捏合缩放/手势/缓存 |
| **偏好存储** | Hive | 轻量 NoSQL，适合键值对 |
| **核心引擎** | Rust + FRB | 高性能解压/解码/内存管理 |
| **数据库** | Rust SQLite (rusqlite) | 书架/进度/书签持久化 |

---

## 9. 开发展望 (P1 阅读器任务拆分)

```
P1.1  搭 Flutter 项目壳
      ├── pubspec.yaml 加依赖 (signals_flutter, go_router, extended_image, hive)
      ├── router.dart 配置 3 个底部页面
      └── app.dart Material 3 主题 (阅读器深色 + 书架自适应)

P1.2  阅读器骨架
      ├── ComicReaderScreen (Stack 容器 + ReaderNotifier)
      ├── 对接 FRB getComicInfo → 获取总页数
      └── 对接 FRB getReadingProgress → 恢复上次位置

P1.3  渲染+手势
      ├── ImageViewVertical (单页垂直 / 连续 / webtoon)
      ├── ImageViewHorizontal (ltr / rtl)
      ├── 三区点击手势 (左中右 / 上中下)
      └── 阅读模式切换

P1.4  工具栏+进度
      ├── 底部工具栏 (章节导航/滑块/模式切换)
      ├── 页码浮层
      └── 对接 FRB saveReadingProgress → 自动保存进度

P1.5  书架基础
      ├── LibraryScreen 网格展示
      ├── 对接 FRB scanDirectory
      └── 封面缩略图 generateThumbnail
```

---

## 10. 已确定的全部设计决策

| # | 决策 | 选择 |
|---|------|------|
| 1 | 图片渲染 | **extended_image** |
| 2 | 文件导入 | **扫描目录** |
| 3 | 路由 | **GoRouter** |
| 4 | 状态管理 | **signals_flutter** |
| 5 | 文件权限 | **MANAGE_EXTERNAL_STORAGE** |
| 6 | 存储分工 | **Hive + Rust SQLite** |
| 7 | 主题 | **阅读器深色 + 书架自适应** |
| 8 | 双页 | **手机单页 + 平板横屏双页** |
| 9 | 格式 | **CBZ 优先** |
| 10 | 参考源 | **Mangayomi 阅读器 UI 模式**
| 11 | 图片通道 | **Rust解码 → 缓存文件 → ExtendedImage.file**
| 12 | 平板双页 | **真正双页并排 [1|2] [3|4]，两次翻一页**
| 13 | 首次启动 | **空状态引导页 + 选择目录按钮**
| 14 | 加载失败 | **错误图标 + 重试按钮**
