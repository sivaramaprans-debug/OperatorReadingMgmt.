import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'routing/app_router.dart';

/// Root application widget.
/// Reads the router from Riverpod and applies light/dark themes.
/// In Step 2, the theme mode will be driven by a Settings provider
/// (device_local scope). For Step 1, defaults to system theme.
class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Operator Reading Mgmt',
      debugShowCheckedModeBanner: false,

      // Material 3 light + dark themes
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // TODO(Step2): replace with Settings-driven themeMode provider
      themeMode: ThemeMode.system,

      // GoRouter integration
      routerConfig: router,
    );
  }
}
