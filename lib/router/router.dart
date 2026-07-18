import 'package:go_router/go_router.dart';
import '../views/app_shell.dart';
import '../views/library/library_screen.dart';
import '../views/history/history_screen.dart';
import '../views/settings/settings_screen.dart';
import '../views/reader/comic_reader_screen.dart';

final GoRouter router = GoRouter(
  initialLocation: '/library',
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: '/library',
          pageBuilder: (context, state) => NoTransitionPage(
            key: state.pageKey,
            child: const LibraryScreen(),
          ),
        ),
        GoRoute(
          path: '/history',
          pageBuilder: (context, state) => NoTransitionPage(
            key: state.pageKey,
            child: const HistoryScreen(),
          ),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) => NoTransitionPage(
            key: state.pageKey,
            child: const SettingsScreen(),
          ),
        ),
      ],
    ),
    GoRoute(
      path: '/reader',
      builder: (context, state) =>
          ComicReaderScreen(filePath: state.extra as String),
    ),
  ],
);
