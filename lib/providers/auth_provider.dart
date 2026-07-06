// lib/providers/auth_provider.dart
//
// Riverpod wrappers around FirebaseAuth + AuthSessionService.
// Use this for reactive auth state instead of calling FirebaseAuth directly.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tapguard/data/services/auth_session_service.dart';

/// Live Firebase auth state (null when signed out).
final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

/// Synchronous read of the current user (null when signed out).
final currentFirebaseUserProvider = Provider<User?>((ref) {
  final auth = ref.watch(authStateProvider);
  return auth.maybeWhen(data: (u) => u, orElse: () => null);
});

/// UID convenience — empty string when not signed in.
final currentUidProvider = Provider<String>((ref) {
  return ref.watch(currentFirebaseUserProvider)?.uid ?? '';
});

/// The email of the last verified session, from SharedPreferences.
final currentVerifiedEmailProvider = FutureProvider<String?>((ref) {
  return AuthSessionService.getVerifiedEmail();
});

/// Action provider for sign-out. Always call [AuthSessionService.clearSession]
/// (clears SharedPreferences + signs out of Firebase) and then navigate to
/// the login screen.
final signOutProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    await AuthSessionService.clearSession();
  };
});
