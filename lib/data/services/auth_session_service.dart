import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthSessionService {
  static const String _kIsLoggedIn = 'auth.is_logged_in';
  static const String _kVerifiedEmail = 'auth.verified_email';

  static Future<void> markSessionVerified(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kIsLoggedIn, true);
    await prefs.setString(_kVerifiedEmail, email.trim().toLowerCase());
  }

  static Future<bool> hasActiveSession() async {
    if (FirebaseAuth.instance.currentUser != null) {
      return true;
    }

    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kIsLoggedIn) ?? false;
  }

  static Future<String?> getVerifiedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kVerifiedEmail);
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kIsLoggedIn);
    await prefs.remove(_kVerifiedEmail);

    if (FirebaseAuth.instance.currentUser != null) {
      await FirebaseAuth.instance.signOut();
    }
  }
}
