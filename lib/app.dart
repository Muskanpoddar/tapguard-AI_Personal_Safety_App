import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/routes/app_routes.dart';
import 'core/theme/app_theme.dart';
import 'presentation/splash/splash_screen.dart';

class TapGuardApp extends ConsumerWidget {
  const TapGuardApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'TapGuard',
      debugShowCheckedModeBanner: false,

      // App theme
      theme: AppTheme.lightTheme,

      // Named routes
      onGenerateRoute: AppRoutes.onGenerateRoute,

      // Start at splash
      home: const SplashScreen(),
    );
  }
}