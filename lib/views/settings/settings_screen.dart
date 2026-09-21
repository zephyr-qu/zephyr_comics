import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import '../../cache/derived_cache.dart';
import '../../models/reader_mode.dart';
import '../../models/settings_options.dart';
import '../../signals/app_signals.dart';
import '../../theme/zephyr_theme.dart';
import '../../utils/format.dart';
import '../library/library_root_flow.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.cache});

  /// Optional seam. Production reads the Rust disk cache through it; tests
  /// inject an in-memory adapter so no FRB call is made.
  final DerivedCache? cache;

  DerivedCache get _cache =>
      cache ?? const DerivedCache(adapter: FrbDerivedCacheAdapter());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The prototype has no app bar here — the page opens with its own h1.
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            ZephyrSpacing.xl,
            0,
            ZephyrSpacing.xl,
            ZephyrSpacing.xl,
          ),
          children: [
            const _PageHeader(),
            const _SectionHeader('书库'),
            const _ScanPathRow(),
            _SwitchRow(
              label: '启动时自动刷新',
              read: () => settingsSnapshot.value.autoRefreshLibrary,
              onChanged: setAutoRefreshLibrary,
            ),
            const _SectionHeader('阅读'),
            const _ReaderModeTile(),
            _SwitchRow(
              label: '显示页码',
              read: () => settingsSnapshot.value.showPageNumber,
              onChanged: setShowPageNumber,
            ),
            const _SectionHeader('外观'),
            const _ThemeTile(),
            const _BackgroundTile(),
            const _SectionHeader('设备'),
            const _OrientationTile(),
            _SwitchRow(
              label: '阅读时保持屏幕常亮',
              read: () => settingsSnapshot.value.keepScreenAwake,
              onChanged: setKeepScreenAwake,
            ),
            _SwitchRow(
              label: '使用音量键翻页',
              read: () => settingsSnapshot.value.volumeKeyPaging,
              onChanged: setVolumeKeyPaging,
            ),
            const _SectionHeader('存储'),
            _StorageSection(cache: _cache),
            const _SectionHeader('关于'),
            const _VersionRow(),
            const _LicenseRow(),
          ],
        ),
      ),
    );
  }
}

/// `.sa-h1`: the page names itself. The app identity and version live in 关于
/// rather than being repeated under the title.
class _PageHeader extends StatelessWidget {
  const _PageHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: ZephyrSpacing.xl),
      child: Text('设置', style: theme.textTheme.headlineMedium),
    );
  }
}

/// `.sa-set-label`: a full `xl` step above and `sm` below — the top is
/// deliberately larger so a section reads as belonging to the content that
/// follows it.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        top: ZephyrSpacing.xl,
        bottom: ZephyrSpacing.sm,
      ),
      child: Text(
        title,
        style: theme.textTheme.labelSmall?.copyWith(fontSize: 9.5),
      ),
    );
  }
}

/// `.sa-set-row`: a flat row under a hairline, label (and optional sub) on the
/// left, the control on the right.
class _SetRow extends StatelessWidget {
  const _SetRow({required this.label, this.sub, this.trailing, this.onTap});

  final String label;
  final String? sub;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: ZephyrSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyLarge?.copyWith(fontSize: 13.5),
                ),
                if (sub != null) ...[
                  const SizedBox(height: ZephyrSpacing.xs),
                  Text(
                    sub!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(fontSize: 10.5),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            // 14px in the prototype; rounded to the nearest ladder step.
            const SizedBox(width: ZephyrSpacing.lg),
            trailing!,
          ],
        ],
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: onTap == null
          ? content
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: content,
            ),
    );
  }
}

/// `.sa-switch`: a 40×22 track with a 16px knob. Material's `Switch` is a
/// different shape and `SwitchListTile` would paint a second row shape inside
/// the one [_SetRow] already provides, so the control is drawn here.
class _ZephyrSwitch extends StatelessWidget {
  const _ZephyrSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      toggled: value,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 40,
          height: 22,
          // A pill, so the radius is the half-height: `StadiumBorder`, not a
          // radius literal.
          decoration: ShapeDecoration(
            color: value ? scheme.primary : null,
            shape: StadiumBorder(
              side: BorderSide(
                color: value ? scheme.primary : scheme.outlineVariant,
              ),
            ),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 180),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Padding(
              // The knob's inset inside the track, not a rhythm step.
              padding: const EdgeInsets.all(2),
              child: DecoratedBox(
                key: const Key('switch-knob'),
                // `.sa-switch i`: `--tx3` when off, the page colour when on.
                decoration: BoxDecoration(
                  color: value ? scheme.surface : scheme.outline,
                  shape: BoxShape.circle,
                ),
                child: const SizedBox(width: 16, height: 16),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.read,
    required this.onChanged,
  });

  final String label;
  final bool Function() read;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SignalBuilder(
    builder: (context) => _SetRow(
      label: label,
      trailing: _ZephyrSwitch(
        key: Key('settings-switch-$label'),
        value: read(),
        onChanged: onChanged,
      ),
    ),
  );
}

class _ScanPathRow extends StatelessWidget {
  const _ScanPathRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SignalBuilder(
      builder: (context) {
        final path = settingsSnapshot.value.scanDirectoryPath;
        return _SetRow(
          label: '漫画目录',
          sub: path.isEmpty ? '尚未设置' : path,
          trailing: Icon(
            Icons.chevron_right,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          onTap: () => chooseLibraryRootFrom(context),
        );
      },
    );
  }
}

/// A labelled row whose choices are an inline segmented control — the compact
/// sibling of the reader drawer's mode selector. Every option is directly
/// tappable, so the current value is always visible instead of hidden behind a
/// menu.
class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.keyPrefix,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String keyPrefix;
  final String label;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(
        top: ZephyrSpacing.sm,
        bottom: ZephyrSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyLarge?.copyWith(fontSize: 13.5),
          ),
          const SizedBox(height: ZephyrSpacing.sm),
          // Deliberately compact: unlike the reader drawer's pill, which keeps
          // `lg` vertical padding so it clears the 44px touch target, the
          // settings rows trade hit area for density.
          Container(
            padding: const EdgeInsets.all(ZephyrSpacing.xs),
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(ZephyrRadius.segmentCompact),
            ),
            child: Row(
              children: [
                for (final (option, optionLabel) in options)
                  Expanded(
                    child: GestureDetector(
                      key: Key('settings-$keyPrefix-${(option as Enum).name}'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(option),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: ZephyrSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: option == value ? scheme.primary : null,
                          borderRadius: BorderRadius.circular(
                            ZephyrRadius.segmentCompact - 2,
                          ),
                        ),
                        child: Text(
                          optionLabel,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontSize: 11,
                            fontWeight: option == value
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: option == value
                                ? scheme.onPrimary
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReaderModeTile extends StatelessWidget {
  const _ReaderModeTile();

  @override
  Widget build(BuildContext context) => SignalBuilder(
    builder: (context) {
      final mode = settingsSnapshot.value.readerMode;
      return _ChoiceRow<ReaderMode>(
        keyPrefix: 'reader-mode',
        label: '默认阅读模式',
        value: mode,
        options: [
          for (final option in ReaderMode.values) (option, option.label),
        ],
        onChanged: setReaderMode,
      );
    },
  );
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile();

  @override
  Widget build(BuildContext context) => SignalBuilder(
    builder: (context) {
      final preference = settingsSnapshot.value.themePreference;
      return _ChoiceRow<ThemePreference>(
        keyPrefix: 'theme',
        label: '应用主题',
        value: preference,
        options: const [
          (ThemePreference.system, '跟随系统'),
          (ThemePreference.light, '浅色'),
          (ThemePreference.dark, '深色'),
        ],
        onChanged: setThemePreference,
      );
    },
  );
}

class _OrientationTile extends StatelessWidget {
  const _OrientationTile();

  @override
  Widget build(BuildContext context) => SignalBuilder(
    builder: (context) {
      final value = settingsSnapshot.value.orientationPreference;
      return _ChoiceRow<OrientationPreference>(
        keyPrefix: 'orientation',
        label: '屏幕方向',
        value: value,
        options: const [
          (OrientationPreference.auto, '自动'),
          (OrientationPreference.portrait, '竖屏'),
          (OrientationPreference.landscape, '横屏'),
        ],
        onChanged: setOrientationPreference,
      );
    },
  );
}

class _BackgroundTile extends StatelessWidget {
  const _BackgroundTile();

  @override
  Widget build(BuildContext context) => SignalBuilder(
    builder: (context) {
      final value = settingsSnapshot.value.readerBackground;
      return _ChoiceRow<ReaderBackground>(
        keyPrefix: 'reader-background',
        label: '阅读页背景',
        value: value,
        options: const [
          (ReaderBackground.black, '纯黑'),
          (ReaderBackground.dark, '深灰'),
          (ReaderBackground.paper, '纸张'),
          (ReaderBackground.system, '跟随主题'),
        ],
        onChanged: setReaderBackground,
      );
    },
  );
}

class _VersionRow extends StatelessWidget {
  const _VersionRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SetRow(
      label: '版本',
      trailing: Text(
        'ZEPHYR COMICS · 0.1.0',
        style: theme.textTheme.labelSmall?.copyWith(fontSize: 10.5),
      ),
    );
  }
}

class _LicenseRow extends StatelessWidget {
  const _LicenseRow();

  @override
  Widget build(BuildContext context) => _SetRow(
    label: '许可证与隐私',
    sub: '不联网、不采集遥测',
    // PRD §9 asks for open-source licenses; showLicensePage collects the real
    // license text from every bundled package.
    onTap: () => showLicensePage(
      context: context,
      applicationName: 'Zephyr Comics',
      applicationVersion: '0.1.0',
      applicationLegalese: '不联网、不采集遥测。源漫画文件只读。',
    ),
  );
}

/// The Derived Cache is rebuildable, so clearing it is safe — but it does delete
/// files from disk and the next open pays to re-derive covers. That earns a
/// warning-toned trigger and a dialog that names the cost in bytes, rather than
/// an inline two-step confirm.
class _StorageSection extends StatefulWidget {
  const _StorageSection({required this.cache});

  final DerivedCache cache;

  @override
  State<_StorageSection> createState() => _StorageSectionState();
}

class _StorageSectionState extends State<_StorageSection> {
  late Future<DerivedCacheStats?> _stats;

  @override
  void initState() {
    super.initState();
    _stats = _read();
  }

  /// A cache query failure must not break Settings — the section reports an
  /// unknown size instead.
  Future<DerivedCacheStats?> _read() async {
    try {
      return await widget.cache.stats();
    } catch (_) {
      return null;
    }
  }

  void _reload() {
    setState(() {
      _stats = _read();
    });
  }

  Future<void> _confirmClear(DerivedCacheStats stats) async {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除派生缓存？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('删除后会在下次打开漫画时自动重建。'),
            const SizedBox(height: ZephyrSpacing.md),
            Divider(height: 1, color: scheme.outlineVariant),
            const SizedBox(height: ZephyrSpacing.sm),
            _DialogRow(label: '将释放', value: formatBytes(stats.bytes)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.cache.clear();
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return FutureBuilder<DerivedCacheStats?>(
      future: _stats,
      builder: (context, snapshot) {
        final busy = snapshot.connectionState != ConnectionState.done;
        final stats = snapshot.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SetRow(
              label: '派生缓存',
              sub: busy
                  ? '正在统计…'
                  : stats == null
                  ? '暂时无法读取'
                  : '封面与缩略图 · 可随时重建',
              trailing: Text(
                busy || stats == null ? '—' : formatBytes(stats.bytes),
                style: theme.textTheme.labelSmall?.copyWith(fontSize: 10.5),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(
                top: ZephyrSpacing.lg,
                bottom: ZephyrSpacing.xs,
              ),
              child: OutlinedButton.icon(
                onPressed: stats == null ? null : () => _confirmClear(stats),
                icon: const Icon(Icons.refresh, size: 15),
                label: Text(stats != null && stats.isEmpty ? '再次清除缓存' : '清除缓存'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: scheme.error,
                  side: BorderSide(color: scheme.error.withValues(alpha: 0.36)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// `.sa-dialog-row`: a monospace label/value pair.
class _DialogRow extends StatelessWidget {
  const _DialogRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(fontSize: 10.5),
        ),
        const SizedBox(width: ZephyrSpacing.md),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 10.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
