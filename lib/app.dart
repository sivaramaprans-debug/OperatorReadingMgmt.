import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'routing/app_router.dart';

/// Root application widget.
/// Reads the router from Riverpod and applies light/dark themes.
class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Operator Reading Mgmt',
      debugShowCheckedModeBanner: false,

      // Material 3 light + dark themes
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,

      // GoRouter integration
      routerConfig: router,
    );
  }
}
