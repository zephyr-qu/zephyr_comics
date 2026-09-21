import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/zephyr_theme.dart';

/// The three sibling destinations. The reader is an immersive drill-down and is
/// deliberately not one of them.
const List<_Destination> _destinations = [
  _Destination(
    slug: 'library',
    path: '/library',
    label: '书架',
    icon: Icons.grid_view,
  ),
  _Destination(
    slug: 'history',
    path: '/history',
    label: '历史',
    icon: Icons.access_time,
  ),
  _Destination(
    slug: 'settings',
    path: '/settings',
    label: '设置',
    icon: Icons.tune,
  ),
];

class _Destination {
  const _Destination({
    required this.slug,
    required this.path,
    required this.label,
    required this.icon,
  });

  final String slug;
  final String path;
  final String label;
  final IconData icon;
}

/// The prototype's bottom bar (`.sa-nav`): a flat 64px strip whose selection is
/// carried by the brass colour alone. Material's `NavigationBar` paints an
/// indicator pill the prototype does not have, so the bar is drawn here.
class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final scheme = Theme.of(context).colorScheme;

    int currentIndex;
    if (location.startsWith('/history')) {
      currentIndex = 1;
    } else if (location.startsWith('/settings')) {
      currentIndex = 2;
    } else {
      // `/comic-detail` is reached from the shelf, so it keeps the shelf lit.
      currentIndex = 0;
    }

    final bool isReader = location.startsWith('/reader');

    return Scaffold(
      body: child,
      bottomNavigationBar: isReader
          ? null
          : DecoratedBox(
              // A hairline so the bar reads as a surface, not a floating strip.
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: scheme.outlineVariant)),
              ),
              child: SizedBox(
                height: 64,
                child: Row(
                  children: [
                    for (final destination in _destinations)
                      Expanded(
                        child: _NavItem(
                          key: Key('nav-${destination.slug}'),
                          destination: destination,
                          selected: destination == _destinations[currentIndex],
                          onTap: () =>
                              GoRouter.of(context).go(destination.path),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.outline;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(destination.icon, size: 19, color: color),
            const SizedBox(height: ZephyrSpacing.xs),
            Text(
              destination.label,
              // `.sa-nav em`: 9.5px monospace, no tracking (Chinese label).
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 9.5,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
