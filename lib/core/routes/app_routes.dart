// lib/core/routes/app_routes.dart
import 'package:flutter/material.dart';

// Splash
import '../../presentation/splash/splash_screen.dart';
// Onboarding
import '../../presentation/onboarding/onboarding_screen.dart';
// Auth
import '../../presentation/auth/login_screen.dart';
import '../../presentation/auth/otp_screen.dart';
import '../../presentation/auth/profile_setup_screen.dart';
// Main
import '../../presentation/main/main_screen.dart';
// NFC Pairing
import '../../presentation/nfc_pairing/nfc_pairing_screen.dart';
// QR Pairing  ← NEW
import '../../presentation/qr_pairing/qr_pairing_screen.dart';
// Session
import '../../presentation/session/active_session_screen.dart';
import '../../presentation/session/live_session_screen.dart';
// Map
import '../../presentation/map/live_map_screen.dart';
// Contacts
import '../../presentation/contacts/contact_detail_screen.dart';
import '../../presentation/contacts/contacts_screen.dart';
// SOS
import '../../presentation/sos/sos_screen.dart';
// Geofence
import '../../presentation/geofence/geofence_setup_screen.dart';
// Safety Status
import '../../presentation/safety_status/safety_status_screen.dart';
import '../../presentation/safety_status/risk_insights_screen.dart';
// History
import '../../presentation/history/session_history_screen.dart';
// Profile
import '../../presentation/profile/profile_screen.dart';
// Privacy
import '../../presentation/privacy/privacy_permissions_screen.dart';
// Settings
import '../../presentation/settings/settings_screen.dart';

class AppRoutes {
  static const String splash         = '/';
  static const String onboarding     = '/onboarding';
  static const String login          = '/login';
  static const String otp            = '/otp';
  static const String profileSetup   = '/profile-setup';
  static const String home           = '/home';
  static const String nfcPairing     = '/nfc-pairing';
  static const String qrPairing      = '/qr-pairing';   // ← NEW
  static const String activeSession  = '/active-session';
  static const String liveSession    = '/live-session';
  static const String liveMap        = '/live-map';
  static const String contacts       = '/contacts';
  static const String contactDetail  = '/contact-detail';
  static const String sos            = '/sos';
  static const String geofenceSetup  = '/geofence-setup';
  static const String safetyStatus   = '/safety-status';
  static const String riskInsights   = '/risk-insights';
  static const String sessionHistory = '/session-history';
  static const String profile        = '/profile';
  static const String privacy        = '/privacy';
  static const String settings       = '/settings';

  static Route<dynamic> onGenerateRoute(RouteSettings routeSettings) {
    switch (routeSettings.name) {

      case splash:
        return _slide(const SplashScreen(), routeSettings);

      case onboarding:
        return _slide(const OnboardingScreen(), routeSettings);

      case login:
        return _slide(const LoginScreen(), routeSettings);

      case otp:
        final args  = routeSettings.arguments as Map<String, String>? ?? {};
        final email = args['email'] ?? '';
        return _slide(OtpScreen(email: email), routeSettings);

      case profileSetup:
        final args = routeSettings.arguments as Map<String, String>? ?? {};
        final email = args['email'] ?? '';
        return _slide(ProfileSetupScreen(email: email), routeSettings);

      case home:
        return _slide(const MainScreen(), routeSettings);

      case nfcPairing:
        return _slide(const NfcPairingScreen(), routeSettings);

      case qrPairing:                                        // ← NEW
        return _slide(const QrPairingScreen(), routeSettings);

      case activeSession:
        return _slide(const ActiveSessionScreen(), routeSettings);

      case liveSession:
        return _slide(const LiveSessionScreen(), routeSettings);

      case liveMap:
        return _slide(const LiveMapScreen(), routeSettings);

      case contacts:
        return _slide(const ContactsScreen(), routeSettings);

      case contactDetail:
        final args = routeSettings.arguments as Map<String, dynamic>? ?? {};
        final uid = args['contactUid'] as String? ?? '';
        return _slide(
          ContactDetailScreen(contactUid: uid),
          routeSettings,
        );

      case sos:
        return _slide(const SosScreen(), routeSettings);

      case geofenceSetup:
        return _slide(const GeofenceSetupScreen(), routeSettings);

      case safetyStatus:
        return _slide(const SafetyStatusScreen(), routeSettings);

      case riskInsights:
        return _slide(const RiskInsightsScreen(), routeSettings);

      case sessionHistory:
        return _slide(const SessionHistoryScreen(), routeSettings);

      case profile:
        return _slide(const ProfileScreen(), routeSettings);

      case privacy:
        return _slide(const PrivacyPermissionsScreen(), routeSettings);

      case settings:
        return _slide(const SettingsScreen(), routeSettings);

      default:
        return _slide(
          Scaffold(
            backgroundColor: const Color(0xFFF4F3F8),
            body: Center(
              child: Text(
                '404 - Not found:\n${routeSettings.name}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  color: Color(0xFF7C4DFF),
                  fontFamily: 'Poppins',
                ),
              ),
            ),
          ),
          routeSettings,
        );
    }
  }

  static PageRouteBuilder _slide(Widget page, RouteSettings routeSettings) {
    return PageRouteBuilder(
      settings: routeSettings,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final tween = Tween(
          begin: const Offset(1.0, 0.0),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOutCubic));
        return SlideTransition(
            position: animation.drive(tween), child: child);
      },
      transitionDuration: const Duration(milliseconds: 350),
    );
  }
}