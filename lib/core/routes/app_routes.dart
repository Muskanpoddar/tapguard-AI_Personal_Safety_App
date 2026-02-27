import 'package:flutter/material.dart';

class AppRoutes {
  // ── Route name constants ──────────────────────────────────────────────────
  static const String splash          = '/';
  static const String onboarding      = '/onboarding';
  static const String login           = '/login';
  static const String otp             = '/otp';
  static const String profileSetup    = '/profile-setup';
  static const String home            = '/home';
  static const String nfcPairing      = '/nfc-pairing';
  static const String activeSession   = '/active-session';
  static const String liveMap         = '/live-map';
  static const String sos             = '/sos';
  static const String geofenceSetup   = '/geofence-setup';
  static const String safetyStatus    = '/safety-status';
  static const String sessionHistory  = '/session-history';
  static const String profile         = '/profile';
  static const String privacy         = '/privacy';
  static const String settings        = '/settings';

  // ── Route generator ───────────────────────────────────────────────────────
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
   //     return _buildRoute(const SplashScreen(), settings);

      case onboarding:
    //    return _buildRoute(const OnboardingScreen(), settings);

      case login:
    //    return _buildRoute(const LoginScreen(), settings);

      case otp:
        // Pass phone number argument
    //    final phone = settings.arguments as String? ?? '';
    //    return _buildRoute(OtpScreen(phoneNumber: phone), settings);

      case profileSetup:
    //    return _buildRoute(const ProfileSetupScreen(), settings);

      case home:
     //   return _buildRoute(const HomeScreen(), settings);

      case nfcPairing:
     //   return _buildRoute(const NfcPairingScreen(), settings);

      case activeSession:
     //   return _buildRoute(const ActiveSessionScreen(), settings);

      case liveMap:
     //   return _buildRoute(const LiveMapScreen(), settings);

      case sos:
     //   return _buildRoute(const SosScreen(), settings);

      case geofenceSetup:
     //   return _buildRoute(const GeofenceSetupScreen(), settings);

      case safetyStatus:
     //   return _buildRoute(const SafetyStatusScreen(), settings);

      case sessionHistory:
      //  return _buildRoute(const SessionHistoryScreen(), settings);

      case profile:
       // return _buildRoute(const ProfileScreen(), settings);

      case privacy:
      //  return _buildRoute(const PrivacyPermissionsScreen(), settings);

      case AppRoutes.settings:
      //  return _buildRoute(const SettingsScreen(), settings);

      default:
        // Fallback — show error screen
        return _buildRoute(
          const Scaffold(
            body: Center(child: Text('404 - Screen not found')),
          ),
          settings,
        );
    }
  }

  // ── Slide transition builder ──────────────────────────────────────────────
  static PageRouteBuilder _buildRoute(Widget page, RouteSettings routeSettings) {
    return PageRouteBuilder(
      settings: routeSettings,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        // Slide from right
        const begin = Offset(1.0, 0.0);
        const end   = Offset.zero;
        const curve = Curves.easeOutCubic;

        final tween = Tween(begin: begin, end: end)
            .chain(CurveTween(curve: curve));

        return SlideTransition(
          position: animation.drive(tween),
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 350),
    );
  }
}