---
status: accepted
---

# 个人 Android MVP 采用直接文件系统访问

Zephyr Comics 面向个人侧载（sideload）的 Android 11+ 应用，通过 Android 的"所有文件访问"权限读取用户选定的唯一漫画根目录。我们否决了与之并行的 SAF 流程，因为 Rust 需要稳定的路径，而把 200–500 MB 的压缩包复制进应用缓存会带来延迟、存储重复，以及第二套文件访问实现；如果权限被拒绝，MVP 会要求用户重新授权，而不是悄悄切换访问模型。

## 后果（Consequences）

MVP 不为 Google Play 分发而设计。漫画源文件保持只读，应用代码绝不删除或改写它们。

SAF 时期的脚手架（SAF MethodChannel、复制到缓存的流水线、路径映射器，以及遗留的 READ/WRITE_EXTERNAL_STORAGE 权限）已被移除；应用只暴露一个用于"所有文件访问"的存储通道。
