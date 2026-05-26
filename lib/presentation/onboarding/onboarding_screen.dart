import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/routes/app_routes.dart';
import '../../data/services/auth_session_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final int _totalPages = 3;

  bool _isPairing = false;
  String _pairingStatus = '';
  bool _privacyAccepted = false;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    )..forward();
    _fadeAnim = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    ).drive(Tween(begin: 0.0, end: 1.0));
  }

  @override
  void dispose() {
    _pageController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentPage = index;
      if (index != 0) {
        _isPairing = false;
        _pairingStatus = '';
      }
    });
    _fadeController.reset();
    _fadeController.forward();
  }

  void _onStartPairing() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _isPairing = true;
      _pairingStatus = 'searching';
    });
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() => _pairingStatus = 'connected');
    HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    setState(() {
      _isPairing = false;
      _pairingStatus = '';
    });
    _pageController.nextPage(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    } else {
      if (!_privacyAccepted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Please accept the privacy terms to continue',
              style: TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        return;
      }
      _goToAuthOrHome();
    }
  }

  Future<void> _goToAuthOrHome() async {
    final hasActiveSession = await AuthSessionService.hasActiveSession();
    if (!mounted) return;
    final route = hasActiveSession ? AppRoutes.home : AppRoutes.login;
    Navigator.of(context).pushReplacementNamed(route);
  }

  void _goBack() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    } else {
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
            _buildTopBar(),
            const SizedBox(height: 8),
            _buildPageDots(),
            const SizedBox(height: 4),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                physics: const BouncingScrollPhysics(),
                children: [
                  _Slide1NfcPairing(
                    isPairing: _isPairing,
                    pairingStatus: _pairingStatus,
                  ),
                  const _Slide2BiDirectional(),
                  _Slide3PrivacyFirst(
                    accepted: _privacyAccepted,
                    onChanged: (val) =>
                        setState(() => _privacyAccepted = val ?? false),
                  ),
                ],
              ),
            ),
            _buildBottomButtons(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
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
                    color: Colors.black.withValues(alpha:0.06),
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
          GestureDetector(
            onTap: _goToAuthOrHome,
            child: Text(
              'Skip',
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

  Widget _buildPageDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_totalPages, (i) {
        final active = i == _currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 28 : 10,
          height: 4,
          decoration: BoxDecoration(
            color: active
                ? AppColors.primary
                : AppColors.primary.withValues(alpha:0.25),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  Widget _buildBottomButtons() {
    return AnimatedBuilder(
      animation: _fadeController,
      builder: (_, child) => Opacity(opacity: _fadeAnim.value, child: child),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            if (_currentPage == 0) ...[
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isPairing ? null : _onStartPairing,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _pairingStatus == 'connected'
                        ? AppColors.success
                        : AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    disabledBackgroundColor: AppColors.primary.withValues(alpha:0.7),
                    disabledForegroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isPairing
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_pairingStatus == 'searching') ...[
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Searching…',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ] else ...[
                              const Icon(
                                Icons.check_circle_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'Connected!',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              AppStrings.startPairing,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.wifi_rounded, size: 18),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () => _showHowItWorksSheet(context),
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
              const SizedBox(height: 12),
              Row(
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
            ],
            if (_currentPage == 1) ...[
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
                  child: const Text(
                    AppStrings.continueBtn,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: _goToAuthOrHome,
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
            ],
            if (_currentPage == 2) ...[
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _privacyAccepted ? _nextPage : null,
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
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Text(
                        AppStrings.getStarted,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'By tapping "Get Started", you agree to our Privacy Policy',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: Colors.grey.shade400,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showHowItWorksSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'How NFC Pairing Works',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 16),
            _howItWorksStep('1', 'Open TapGuard on both phones'),
            _howItWorksStep('2', 'Tap "Start Pairing" on both devices'),
            _howItWorksStep('3', 'Hold the backs of both phones together'),
            _howItWorksStep('4', 'Feel the vibration — you\'re connected!'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEDE7FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.lock_rounded,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Connection is end-to-end encrypted. Only the two paired devices can see each other\'s location.',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _howItWorksStep(String num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                num,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                color: Color(0xFF1A1A2E),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  SLIDE 1 — NFC Pairing — FIXED overflow
// ═══════════════════════════════════════════════════════════════════════════
class _Slide1NfcPairing extends StatefulWidget {
  final bool isPairing;
  final String pairingStatus;
  const _Slide1NfcPairing({
    required this.isPairing,
    required this.pairingStatus,
  });
  @override
  State<_Slide1NfcPairing> createState() => _Slide1NfcPairingState();
}

class _Slide1NfcPairingState extends State<_Slide1NfcPairing>
    with TickerProviderStateMixin {
  late AnimationController _nfcPulse;
  late Animation<double> _nfcScale;
  late AnimationController _phoneAnim;
  late Animation<double> _phoneMoveL;
  late Animation<double> _phoneMoveR;

  @override
  void initState() {
    super.initState();
    _nfcPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _nfcScale = CurvedAnimation(
      parent: _nfcPulse,
      curve: Curves.easeInOut,
    ).drive(Tween(begin: 0.85, end: 1.18));
    _phoneAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _phoneMoveL = CurvedAnimation(
      parent: _phoneAnim,
      curve: Curves.easeInOut,
    ).drive(Tween(begin: 0.0, end: 10.0));
    _phoneMoveR = CurvedAnimation(
      parent: _phoneAnim,
      curve: Curves.easeInOut,
    ).drive(Tween(begin: 0.0, end: -10.0));
  }

  @override
  void dispose() {
    _nfcPulse.dispose();
    _phoneAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = widget.pairingStatus == 'connected';
    // ── FIX: use LayoutBuilder so phones scale to screen width ──────────────
    return LayoutBuilder(
      builder: (context, constraints) {
        final availW = constraints.maxWidth;
        // Phone card width = 18% of screen, NFC icon = 13%
        final phoneW = (availW * 0.18).clamp(60.0, 90.0);
        final phoneH = phoneW * 1.75;
        final nfcSize = (availW * 0.13).clamp(44.0, 56.0);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              // Illustration box — clips overflow
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: double.infinity,
                height: 270,
                clipBehavior: Clip.hardEdge, // ← KEY FIX: clips any overflow
                decoration: BoxDecoration(
                  color: isConnected
                      ? const Color(0xFFE8F8EE)
                      : const Color(0xFFEDE7FF),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Glow circle
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            (isConnected
                                    ? AppColors.success
                                    : AppColors.primary)
                                .withValues(alpha:0.1),
                      ),
                    ),

                    // Phones + NFC icon row — uses proportional sizing
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Left phone
                        AnimatedBuilder(
                          animation: _phoneAnim,
                          builder: (_, child) => Transform.translate(
                            offset: Offset(
                              widget.isPairing ? _phoneMoveL.value : 0,
                              0,
                            ),
                            child: child,
                          ),
                          child: _PhoneCard(
                            isPrimary: false,
                            isConnected: isConnected,
                            width: phoneW,
                            height: phoneH,
                          ),
                        ),

                        SizedBox(width: availW * 0.04),

                        // NFC icon center
                        AnimatedBuilder(
                          animation: _nfcPulse,
                          builder: (_, _) => Transform.scale(
                            scale: widget.isPairing ? _nfcScale.value : 1.0,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 400),
                              width: nfcSize,
                              height: nfcSize,
                              decoration: BoxDecoration(
                                color: isConnected
                                    ? AppColors.success
                                    : AppColors.primary,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        (isConnected
                                                ? AppColors.success
                                                : AppColors.primary)
                                            .withValues(alpha:0.45),
                                    blurRadius: widget.isPairing ? 20 : 10,
                                    spreadRadius: widget.isPairing ? 5 : 2,
                                  ),
                                ],
                              ),
                              child: Icon(
                                isConnected
                                    ? Icons.check_rounded
                                    : Icons.wifi_rounded,
                                color: Colors.white,
                                size: nfcSize * 0.48,
                              ),
                            ),
                          ),
                        ),

                        SizedBox(width: availW * 0.04),

                        // Right phone
                        AnimatedBuilder(
                          animation: _phoneAnim,
                          builder: (_, child) => Transform.translate(
                            offset: Offset(
                              widget.isPairing ? _phoneMoveR.value : 0,
                              0,
                            ),
                            child: child,
                          ),
                          child: _PhoneCard(
                            isPrimary: true,
                            isConnected: isConnected,
                            width: phoneW,
                            height: phoneH,
                          ),
                        ),
                      ],
                    ),

                    // Status badge
                    if (widget.isPairing)
                      Positioned(
                        bottom: 16,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isConnected
                                ? AppColors.success
                                : AppColors.primary,
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!isConnected)
                                const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                ),
                              if (isConnected)
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              const SizedBox(width: 6),
                              Text(
                                isConnected
                                    ? 'Pairing Successful!'
                                    : 'Searching…',
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
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
                AppStrings.onboarding1Title,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A2E),
                ),
              ),

              const SizedBox(height: 12),

              Text(
                AppStrings.onboarding1Body,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.65,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Phone card widget — now accepts width/height ───────────────────────────
class _PhoneCard extends StatelessWidget {
  final bool isPrimary;
  final bool isConnected;
  final double width;
  final double height;
  const _PhoneCard({
    required this.isPrimary,
    this.isConnected = false,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isPrimary ? Colors.white : Colors.white.withValues(alpha:0.85),
        borderRadius: BorderRadius.circular(14),
        border: isPrimary
            ? Border.all(
                color: isConnected ? AppColors.success : AppColors.primary,
                width: 2,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: (isConnected ? AppColors.success : AppColors.primary)
                .withValues(alpha:0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: width * 0.44,
          height: width * 0.44,
          decoration: BoxDecoration(
            color: isPrimary
                ? (isConnected ? AppColors.success : AppColors.primary)
                : const Color(0xFFEDE7FF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            isPrimary ? Icons.phone_android_rounded : Icons.smartphone_rounded,
            color: isPrimary ? Colors.white : AppColors.primary,
            size: width * 0.26,
          ),
        ),
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
  late AnimationController _pulse;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _scale = CurvedAnimation(
      parent: _pulse,
      curve: Curves.easeInOut,
    ).drive(Tween(begin: 0.92, end: 1.08));
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            height: 260,
            clipBehavior: Clip.hardEdge, // ← FIX overflow
            decoration: BoxDecoration(
              color: const Color(0xFFEDE7FF),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 210,
                  height: 210,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha:0.07),
                  ),
                ),
                Positioned(
                  top: 40,
                  right: 62,
                  child: _dot(size: 10, opacity: 0.4),
                ),
                Positioned(
                  bottom: 50,
                  left: 58,
                  child: _dot(size: 10, opacity: 0.35),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _iconBox(Icons.location_on_rounded),
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 80,
                          height: 2,
                          color: AppColors.primary.withValues(alpha:0.25),
                        ),
                        AnimatedBuilder(
                          animation: _pulse,
                          builder: (_, _) => Transform.scale(
                            scale: _scale.value,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha:0.12),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.primary,
                                  width: 1.5,
                                ),
                              ),
                              child: const Icon(
                                Icons.swap_horiz_rounded,
                                color: AppColors.primary,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    _iconBox(Icons.nfc_rounded),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

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
              color: Colors.grey.shade600,
              height: 1.65,
            ),
          ),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFEDE7FF),
              borderRadius: BorderRadius.circular(50),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(
                  Icons.verified_user_rounded,
                  color: AppColors.primary,
                  size: 15,
                ),
                SizedBox(width: 6),
                Text(
                  AppStrings.onboarding2Badge,
                  style: TextStyle(
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

  Widget _iconBox(IconData icon) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha:0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, color: AppColors.primary, size: 30),
    );
  }

  Widget _dot({required double size, required double opacity}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary.withValues(alpha:opacity),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  SLIDE 3 — Privacy First
// ═══════════════════════════════════════════════════════════════════════════
class _Slide3PrivacyFirst extends StatefulWidget {
  final bool accepted;
  final ValueChanged<bool?> onChanged;
  const _Slide3PrivacyFirst({required this.accepted, required this.onChanged});
  @override
  State<_Slide3PrivacyFirst> createState() => _Slide3PrivacyFirstState();
}

class _Slide3PrivacyFirstState extends State<_Slide3PrivacyFirst>
    with SingleTickerProviderStateMixin {
  late AnimationController _shieldPulse;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _shieldPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _scale = CurvedAnimation(
      parent: _shieldPulse,
      curve: Curves.easeInOut,
    ).drive(Tween(begin: 1.0, end: 1.06));
  }

  @override
  void dispose() {
    _shieldPulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            height: 240,
            clipBehavior: Clip.hardEdge, // ← FIX overflow
            decoration: BoxDecoration(
              color: const Color(0xFFEDE7FF),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha:0.07),
                  ),
                ),
                Positioned(top: 50, right: 65, child: _nfcDot()),
                Positioned(bottom: 60, left: 60, child: _nfcDot()),
                AnimatedBuilder(
                  animation: _shieldPulse,
                  builder: (_, _) => Transform.scale(
                    scale: _scale.value,
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha:0.35),
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
                Positioned(
                  bottom: 44,
                  child: Container(
                    width: 88,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(50),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha:0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: 28,
                          height: 28,
                          margin: const EdgeInsets.only(right: 2),
                          decoration: BoxDecoration(
                            color: widget.accepted
                                ? AppColors.success
                                : AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            widget.accepted
                                ? Icons.check_rounded
                                : Icons.lock_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          const Text(
            AppStrings.onboarding3Title,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A2E),
            ),
          ),

          const SizedBox(height: 10),

          Text(
            AppStrings.onboarding3Body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              color: Colors.grey.shade600,
              height: 1.6,
            ),
          ),

          const SizedBox(height: 16),

          _featureTile(Icons.timer_rounded, AppStrings.onboarding3Feature1),
          const SizedBox(height: 10),
          _featureTile(
            Icons.crop_square_rounded,
            AppStrings.onboarding3Feature2,
          ),

          const SizedBox(height: 20),

          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              widget.onChanged(!widget.accepted);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: widget.accepted
                    ? AppColors.primary.withValues(alpha:0.08)
                    : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: widget.accepted
                      ? AppColors.primary
                      : Colors.grey.shade300,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: widget.accepted
                          ? AppColors.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: widget.accepted
                            ? AppColors.primary
                            : Colors.grey.shade400,
                        width: 2,
                      ),
                    ),
                    child: widget.accepted
                        ? const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 16,
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          color: Color(0xFF1A1A2E),
                        ),
                        children: [
                          const TextSpan(text: 'I agree to the '),
                          TextSpan(
                            text: 'Privacy Policy',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                          const TextSpan(text: ' and '),
                          TextSpan(
                            text: 'Terms of Service',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _featureTile(IconData icon, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.04),
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
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1A1A2E),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _nfcDot() {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary.withValues(alpha:0.15),
        border: Border.all(color: AppColors.primary.withValues(alpha:0.3), width: 1),
      ),
      child: const Icon(Icons.wifi_rounded, color: AppColors.primary, size: 14),
    );
  }
}
 