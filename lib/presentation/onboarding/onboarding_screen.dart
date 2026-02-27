import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/routes/app_routes.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  ONBOARDING SCREEN
// ═══════════════════════════════════════════════════════════════════════════
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final int _totalPages = 3;

  // Content fade animation per slide
  late AnimationController _contentAnimController;
  late Animation<double> _contentFade;
  late Animation<double> _contentSlide;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    _contentAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _contentFade = CurvedAnimation(
      parent: _contentAnimController,
      curve: Curves.easeIn,
    ).drive(Tween(begin: 0.0, end: 1.0));
    _contentSlide = CurvedAnimation(
      parent: _contentAnimController,
      curve: Curves.easeOutCubic,
    ).drive(Tween(begin: 24.0, end: 0.0));

    _contentAnimController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _contentAnimController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
    _contentAnimController.reset();
    _contentAnimController.forward();
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    } else {
      _goToLogin();
    }
  }

  void _goToLogin() {
    Navigator.of(context).pushReplacementNamed(AppRoutes.login);
  }

  void _goBack() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    } else {
      // Go back to splash
      Navigator.of(context).pushReplacementNamed(AppRoutes.splash);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ───────────────────────────────────────────────────
            _buildTopBar(),

            // ── Page dots ─────────────────────────────────────────────────
            const SizedBox(height: 12),
            _buildPageDots(),
            const SizedBox(height: 8),

            // ── Page content ──────────────────────────────────────────────
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                physics: const BouncingScrollPhysics(),
                children: const [
                  _Slide1NfcPairing(),
                  _Slide2BiDirectional(),
                  _Slide3PrivacyFirst(),
                ],
              ),
            ),

            // ── Bottom buttons ────────────────────────────────────────────
            _buildBottomButtons(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ── Top bar: back + title + skip ─────────────────────────────────────────
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Back button
          GestureDetector(
            onTap: _goBack,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 16,
                color: Color(0xFF1A1A2E),
              ),
            ),
          ),

          // Title
          Text(
            _currentPage == 0 ? 'ONBOARDING' : 'TapGuard',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: _currentPage == 0 ? FontWeight.w600 : FontWeight.w700,
              color: _currentPage == 0
                  ? AppColors.primary
                  : const Color(0xFF1A1A2E),
              letterSpacing: _currentPage == 0 ? 1.2 : 0,
            ),
          ),

          // Skip button
          GestureDetector(
            onTap: _goToLogin,
            child: Text(
              AppStrings.skip,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Page indicator dots ───────────────────────────────────────────────────
  Widget _buildPageDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_totalPages, (i) {
        final isActive = i == _currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 28 : 10,
          height: 4,
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.primary
                : AppColors.primary.withOpacity(0.25),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  // ── Bottom action buttons (change per slide) ──────────────────────────────
  Widget _buildBottomButtons() {
    return AnimatedBuilder(
      animation: _contentAnimController,
      builder: (_, child) => Opacity(opacity: _contentFade.value, child: child),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            // Primary button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _nextPage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _currentPage == 0
                          ? AppStrings.startPairing
                          : _currentPage == 1
                          ? AppStrings.continueBtn
                          : AppStrings.getStarted,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_currentPage == 0) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.wifi_rounded, size: 18),
                    ],
                    if (_currentPage == 2) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Secondary button
            if (_currentPage == 0)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: Colors.grey.shade300, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    AppStrings.howDoesItWork,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),

            if (_currentPage == 1)
              TextButton(
                onPressed: _goToLogin,
                child: Text(
                  AppStrings.skipForNow,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade500,
                  ),
                ),
              ),

            if (_currentPage == 2)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'By tapping "Get Started", you agree to our Privacy Policy',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: Colors.grey.shade400,
                  ),
                ),
              ),

            // E2E badge on slide 1
            if (_currentPage == 0)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 13,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      AppStrings.endToEndEncrypted,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade500,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  SLIDE 1 — NFC Pairing
// ═══════════════════════════════════════════════════════════════════════════
class _Slide1NfcPairing extends StatefulWidget {
  const _Slide1NfcPairing();

  @override
  State<_Slide1NfcPairing> createState() => _Slide1NfcPairingState();
}

class _Slide1NfcPairingState extends State<_Slide1NfcPairing>
    with SingleTickerProviderStateMixin {
  late AnimationController _nfcController;
  late Animation<double> _nfcScale;
  late Animation<double> _nfcOpacity;

  @override
  void initState() {
    super.initState();
    _nfcController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _nfcScale = CurvedAnimation(
      parent: _nfcController,
      curve: Curves.easeInOut,
    ).drive(Tween(begin: 0.92, end: 1.06));
    _nfcOpacity = CurvedAnimation(
      parent: _nfcController,
      curve: Curves.easeInOut,
    ).drive(Tween(begin: 0.7, end: 1.0));
  }

  @override
  void dispose() {
    _nfcController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // ── Illustration card ───────────────────────────────────────────
          Container(
            width: double.infinity,
            height: 280,
            decoration: BoxDecoration(
              color: const Color(0xFFEDE7FF),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Soft purple bg blobs
                Positioned(
                  left: 40,
                  top: 60,
                  child: Container(
                    width: 130,
                    height: 160,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.08),
                          blurRadius: 20,
                          offset: const Offset(4, 8),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEDE7FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.smartphone_rounded,
                          color: AppColors.primary,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 40,
                  top: 40,
                  child: Container(
                    width: 130,
                    height: 180,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.primary, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.15),
                          blurRadius: 24,
                          offset: const Offset(-4, 8),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.phone_android_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                ),

                // Center NFC pulse icon
                AnimatedBuilder(
                  animation: _nfcController,
                  builder: (_, __) => Transform.scale(
                    scale: _nfcScale.value,
                    child: Opacity(
                      opacity: _nfcOpacity.value,
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.4),
                              blurRadius: 16,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.wifi_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Title
          const Text(
            AppStrings.onboarding1Title,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A2E),
            ),
          ),

          const SizedBox(height: 12),

          // Body
          Text(
            AppStrings.onboarding1Body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: Colors.grey.shade600,
              height: 1.65,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  SLIDE 2 — Bi-directional Sharing
// ═══════════════════════════════════════════════════════════════════════════
class _Slide2BiDirectional extends StatefulWidget {
  const _Slide2BiDirectional();

  @override
  State<_Slide2BiDirectional> createState() => _Slide2BiDirectionalState();
}

class _Slide2BiDirectionalState extends State<_Slide2BiDirectional>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ).drive(Tween(begin: 0.92, end: 1.08));
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // ── Illustration ────────────────────────────────────────────────
          Container(
            width: double.infinity,
            height: 260,
            decoration: BoxDecoration(
              color: const Color(0xFFEDE7FF),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer soft circle
                Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withOpacity(0.08),
                  ),
                ),

                // Floating dots
                Positioned(
                  top: 40,
                  right: 60,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withOpacity(0.4),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 50,
                  left: 55,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withOpacity(0.35),
                    ),
                  ),
                ),

                // Row of 3 icons connected by line
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Location icon
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.12),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.location_on_rounded,
                        color: AppColors.primary,
                        size: 30,
                      ),
                    ),

                    // Connector line with center NFC icon
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 80,
                          height: 2,
                          color: AppColors.primary.withOpacity(0.25),
                        ),
                        AnimatedBuilder(
                          animation: _pulseController,
                          builder: (_, __) => Transform.scale(
                            scale: _pulse.value,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.15),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.primary,
                                  width: 1.5,
                                ),
                              ),
                              child: const Icon(
                                Icons.crop_square_rounded,
                                color: AppColors.primary,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // NFC icon
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.12),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.nfc_rounded,
                        color: AppColors.primary,
                        size: 30,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          const Text(
            AppStrings.onboarding2Title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A2E),
            ),
          ),

          const SizedBox(height: 12),

          Text(
            AppStrings.onboarding2Body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: Colors.grey.shade600,
              height: 1.65,
            ),
          ),

          const SizedBox(height: 16),

          // "End session at any time" badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFEDE7FF),
              borderRadius: BorderRadius.circular(50),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.verified_user_rounded,
                  color: AppColors.primary,
                  size: 15,
                ),
                const SizedBox(width: 6),
                Text(
                  AppStrings.onboarding2Badge,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  SLIDE 3 — Privacy First
// ═══════════════════════════════════════════════════════════════════════════
class _Slide3PrivacyFirst extends StatefulWidget {
  const _Slide3PrivacyFirst();

  @override
  State<_Slide3PrivacyFirst> createState() => _Slide3PrivacyFirstState();
}

class _Slide3PrivacyFirstState extends State<_Slide3PrivacyFirst>
    with SingleTickerProviderStateMixin {
  late AnimationController _shieldController;
  late Animation<double> _shieldPulse;

  @override
  void initState() {
    super.initState();
    _shieldController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _shieldPulse = CurvedAnimation(
      parent: _shieldController,
      curve: Curves.easeInOut,
    ).drive(Tween(begin: 1.0, end: 1.06));
  }

  @override
  void dispose() {
    _shieldController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // ── Illustration ────────────────────────────────────────────────
          Container(
            width: double.infinity,
            height: 250,
            decoration: BoxDecoration(
              color: const Color(0xFFEDE7FF),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer soft circle
                Container(
                  width: 210,
                  height: 210,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withOpacity(0.07),
                  ),
                ),

                // NFC dots around
                Positioned(top: 55, right: 65, child: _smallNfcDot()),
                Positioned(bottom: 65, left: 60, child: _smallNfcDot()),

                // Center shield card
                AnimatedBuilder(
                  animation: _shieldController,
                  builder: (_, __) => Transform.scale(
                    scale: _shieldPulse.value,
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.35),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.shield_rounded,
                        color: Colors.white,
                        size: 44,
                      ),
                    ),
                  ),
                ),

                // Toggle pill at bottom of card
                Positioned(
                  bottom: 52,
                  child: Container(
                    width: 90,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(50),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          margin: const EdgeInsets.only(right: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          const Text(
            AppStrings.onboarding3Title,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A2E),
            ),
          ),

          const SizedBox(height: 12),

          Text(
            AppStrings.onboarding3Body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: Colors.grey.shade600,
              height: 1.65,
            ),
          ),

          const SizedBox(height: 20),

          // Feature tile 1
          _featureTile(
            icon: Icons.timer_rounded,
            text: AppStrings.onboarding3Feature1,
          ),

          const SizedBox(height: 10),

          // Feature tile 2
          _featureTile(
            icon: Icons.crop_square_rounded,
            text: AppStrings.onboarding3Feature2,
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _featureTile({required IconData icon, required String text}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFEDE7FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 14),
          Text(
            text,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1A1A2E),
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallNfcDot() {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary.withOpacity(0.15),
        border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 1),
      ),
      child: const Icon(Icons.wifi_rounded, color: AppColors.primary, size: 14),
    );
  }
}
