// lib/main.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'firebase_options.dart';
import 'app.dart';
import 'data/services/deep_link_service.dart';
import 'data/services/notification_service.dart';
import 'data/services/risk/baseline_store.dart';
import 'data/services/risk/risk_training_example.dart';

/// Top-level navigator key so the deep-link listener (which lives
/// outside any widget tree) can push routes into the running app
/// without needing a BuildContext. Wired into `MaterialApp.navigatorKey`.
final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load runtime secrets from .env BEFORE anything that needs them
  // (Firebase options, SMTP service, OneSignal). The file is
  // gitignored — see .gitignore and docs/SECURITY.md.
  await dotenv.load(fileName: '.env');

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // Initialize Hive + register all adapters up-front. The baseline
  // store wraps its own `ensureInitialized` for adapters it owns, but
  // the risk training adapter (typeId 10) lives elsewhere so we
  // register it here. Doing it in main avoids a crash on the "View
  // Risk Insights" screen — the TrainingDataStore opens its box
  // there, and Hive needs a path on disk + adapter registered before
  // any box can be opened.
  await HiveBaselineStore.ensureInitialized();
  if (!Hive.isAdapterRegistered(10)) {
    Hive.registerAdapter(RiskTrainingExampleAdapter());
  }

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Ensure we have an auth user BEFORE the user reaches the home screen.
  // Anonymous sign-in is cheap (~500 ms on warm cache, slower on cold
  // first-launch only) — doing it here instead of inside
  // `createSessionForContact` keeps session-start under the ANR budget.
  // OTP screens can upgrade later via FirebaseAuth.linkWithCredential
  // without re-creating the auth state.
  if (FirebaseAuth.instance.currentUser == null) {
    unawaited(_ensureSignedIn());
  }

  // Initialize push notifications + FCM token saving
  await NotificationService().initialize();

  // Start the deep-link listener BEFORE runApp so the cold-start
  // initial link is captured and re-emitted on the service's
  // broadcast stream. The actual route push happens after the
  // MaterialApp is mounted (see app.dart). Wrapped in unawaited()
  // — this returns within microseconds because `app_links` is
  // just attaching to a platform channel and reading the cold-
  // start URI.
  unawaited(DeepLinkService().initialize());

  runApp(const ProviderScope(child: TapGuardApp()));
}

Future<void> _ensureSignedIn() async {
  try {
    await FirebaseAuth.instance.signInAnonymously();
  } catch (e) {
    debugPrint('Anonymous sign-in failed: $e');
  }
}