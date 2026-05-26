// lib/presentation/auth/login_screen.dart
//
// Login Screen – Email OTP (free SMTP via Gmail)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/routes/app_routes.dart';
import '../../data/services/auth_session_service.dart';
import '../../data/services/email_otp_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  LOGIN SCREEN
// ═══════════════════════════════════════════════════════════════════════════
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _emailController = TextEditingController();
  final FocusNode _emailFocus = FocusNode();

  bool _isLoading = false;
  bool _emailValid = false;

  // Simple email regex
  static final _emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
  );

  // Entrance animation
  late AnimationController _enterController;
  late Animation<double> _enterFade;
  late Animation<double> _enterSlide;

  @override
  void initState() {
    super.initState();

    // Returning users with an active Firebase session should not re-verify OTP.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final hasActiveSession = await AuthSessionService.hasActiveSession();
      if (hasActiveSession && mounted) {
        Navigator.of(context).pushReplacementNamed(AppRoutes.home);
      }
    });

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _enterFade = CurvedAnimation(
      parent: _enterController,
      curve: Curves.easeIn,
    ).drive(Tween(begin: 0.0, end: 1.0));
    _enterSlide = CurvedAnimation(
      parent: _enterController,
      curve: Curves.easeOutCubic,
    ).drive(Tween(begin: 40.0, end: 0.0));

    _enterController.forward();

    _emailController.addListener(() {
      final valid = _emailRegex.hasMatch(_emailController.text.trim());
      if (valid != _emailValid) setState(() => _emailValid = valid);
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _emailFocus.dispose();
    _enterController.dispose();
    super.dispose();
  }

  // ── Send OTP via email ────────────────────────────────────────────────────
  Future<void> _sendOtp() async {
    if (!_emailValid || _isLoading) return;

    FocusScope.of(context).unfocus();
    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);

    final email = _emailController.text.trim().toLowerCase();
    final error = await EmailOtpService.sendOtp(email);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (error != null) {
      _showError(error);
      return;
    }

    Navigator.of(context).pushNamed(AppRoutes.otp, arguments: {'email': email});
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: AppColors.sos,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: AnimatedBuilder(
              animation: _enterController,
              builder: (_, child) => Transform.translate(
                offset: Offset(0, _enterSlide.value),
                child: Opacity(opacity: _enterFade.value, child: child),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 48),

                  // ── Logo ──────────────────────────────────────────────
                  _buildLogo(),

                  const SizedBox(height: 32),

                  // ── Title ─────────────────────────────────────────────
                  const Text(
                    AppStrings.welcomeTitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    'Enter your email address and we\'ll send\na verification code instantly.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: Colors.grey.shade600,
                      height: 1.6,
                    ),
                  ),

                  const SizedBox(height: 36),

                  // ── Email input card ──────────────────────────────────────────────────
                  _buildEmailCard(),

                  const SizedBox(height: 52),

                  // ── Footer ────────────────────────────────────────────
                  _buildFooter(),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Logo ──────────────────────────────────────────────────────────────────
  Widget _buildLogo() {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha:0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Center(
        child: Icon(Icons.shield_rounded, color: AppColors.primary, size: 38),
      ),
    );
  }

  // ── Email input card ──────────────────────────────────────────────────────
  Widget _buildEmailCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label
          const Text(
            'Email Address',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A2E),
            ),
          ),

          const SizedBox(height: 12),

          // Email text field
          Container(
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFF0EFF5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _emailFocus.hasFocus
                    ? AppColors.primary
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: TextField(
              controller: _emailController,
              focusNode: _emailFocus,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1A1A2E),
              ),
              decoration: InputDecoration(
                hintText: 'you@gmail.com',
                hintStyle: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  color: Colors.grey.shade400,
                ),
                prefixIcon: Icon(
                  Icons.email_outlined,
                  color: _emailValid ? AppColors.primary : Colors.grey.shade400,
                  size: 20,
                ),
                suffixIcon: _emailValid
                    ? const Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.success,
                        size: 20,
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 15,
                ),
              ),
              onSubmitted: (_) => _sendOtp(),
            ),
          ),

          const SizedBox(height: 16),

          // Send OTP button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: (_emailValid && !_isLoading) ? _sendOtp : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                disabledBackgroundColor: AppColors.primary.withValues(alpha:0.4),
                disabledForegroundColor: Colors.white70,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Send OTP',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.send_rounded, size: 18),
                      ],
                    ),
            ),
          ),

          const SizedBox(height: 14),

          // Privacy note
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0EFF5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.verified_user_rounded,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppStrings.locationEncrypted,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────────
  Widget _buildFooter() {
    return Column(
      children: [
        // Privacy + Terms links
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () {},
              child: Text(
                AppStrings.privacyPolicy,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: Colors.grey.shade500,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey.shade400,
                ),
              ),
            ),
            GestureDetector(
              onTap: () {},
              child: Text(
                AppStrings.termsOfService,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: Colors.grey.shade500,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // NFC badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.crop_square_rounded,
                size: 14,
                color: AppColors.primary,
              ),
              const SizedBox(width: 6),
              Text(
                AppStrings.nfcEnabledPrivacy,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
