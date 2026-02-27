import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/routes/app_routes.dart';
import 'core/theme/app_theme.dart';

class TapGuardApp extends ConsumerWidget {
  const TapGuardApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'TapGuard',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,

      // ── Use initialRoute + onGenerateRoute (NOT home:) ─────────────────
      // home: removed intentionally — it bypasses onGenerateRoute
      initialRoute: AppRoutes.splash,
      onGenerateRoute: AppRoutes.onGenerateRoute,
    );
  }
}
