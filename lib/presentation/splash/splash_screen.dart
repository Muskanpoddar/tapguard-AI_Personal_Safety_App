import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/routes/app_routes.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {

  // ── Animation Controllers ─────────────────────────────────────────────────
  late AnimationController _logoController;       // logo scale-in
  late AnimationController _pulseController;      // shield card pulse
  late AnimationController _ringController;       // expanding NFC ring
  late AnimationController _contentController;    // text fade + slide up
  late AnimationController _loadBarController;    // bottom loading bar
  late AnimationController _sparkleController;    // sparkle twinkle

  // ── Animations ────────────────────────────────────────────────────────────
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _pulseScale;
  late Animation<double> _ringScale;
  late Animation<double> _ringOpacity;
  late Animation<double> _contentSlide;
  late Animation<double> _contentOpacity;
  late Animation<double> _loadBarWidth;
  late Animation<double> _sparkleOpacity;
  late Animation<double> _badgeOpacity;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );
    _initControllers();
    _initAnimations();
    _startSequence();
  }

  // ── Init all controllers ──────────────────────────────────────────────────
  void _initControllers() {
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();

    _contentController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _loadBarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );

    _sparkleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  // ── Init all animations ───────────────────────────────────────────────────
  void _initAnimations() {
    // Logo bouncy scale-in
    _logoScale = CurvedAnimation(
      parent: _logoController,
      curve: Curves.elasticOut,
    ).drive(Tween(begin: 0.3, end: 1.0));

    _logoOpacity = CurvedAnimation(
      parent: _logoController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
    ).drive(Tween(begin: 0.0, end: 1.0));

    // Shield card breathing pulse (looping)
    _pulseScale = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ).drive(Tween(begin: 1.0, end: 1.06));

    // Expanding NFC-style ripple ring
    _ringScale = CurvedAnimation(
      parent: _ringController,
      curve: Curves.easeOut,
    ).drive(Tween(begin: 0.75, end: 1.2));

    _ringOpacity = CurvedAnimation(
      parent: _ringController,
      curve: Curves.easeOut,
    ).drive(Tween(begin: 0.55, end: 0.0));

    // Text content slide up + fade in
    _contentSlide = CurvedAnimation(
      parent: _contentController,
      curve: Curves.easeOutCubic,
    ).drive(Tween(begin: 32.0, end: 0.0));

    _contentOpacity = CurvedAnimation(
      parent: _contentController,
      curve: Curves.easeIn,
    ).drive(Tween(begin: 0.0, end: 1.0));

    // Loading bar sweeps left → right
    _loadBarWidth = CurvedAnimation(
      parent: _loadBarController,
      curve: Curves.easeInOut,
    ).drive(Tween(begin: 0.0, end: 1.0));

    // Sparkle twinkle (looping)
    _sparkleOpacity = CurvedAnimation(
      parent: _sparkleController,
      curve: Curves.easeInOut,
    ).drive(Tween(begin: 0.15, end: 0.85));

    // Privacy badge fades in slightly after content
    _badgeOpacity = CurvedAnimation(
      parent: _contentController,
      curve: const Interval(0.4, 1.0, curve: Curves.easeIn),
    ).drive(Tween(begin: 0.0, end: 1.0));
  }

  // ── Animation sequence ────────────────────────────────────────────────────
  void _startSequence() async {
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;

    _logoController.forward();

    await Future.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;

    _contentController.forward();
    _loadBarController.forward();

    // Navigate after splash duration
    await Future.delayed(const Duration(milliseconds: 3000));
    if (!mounted) return;
    _navigateNext();
  }

  void _navigateNext() {
    // TODO: check SharedPreferences → if onboarding done go to home, else onboarding
    // final prefs = await SharedPreferences.getInstance();
    // final done = prefs.getBool('onboarding_done') ?? false;
    // Navigator.of(context).pushReplacementNamed(done ? AppRoutes.home : AppRoutes.onboarding);
    Navigator.of(context).pushReplacementNamed(AppRoutes.onboarding);
  }

  @override
  void dispose() {
    _logoController.dispose();
    _pulseController.dispose();
    _ringController.dispose();
    _contentController.dispose();
    _loadBarController.dispose();
    _sparkleController.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppColors.splashGradient,
            stops: [0.0, 0.4, 0.75, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Layer 1: Static concentric bg rings
            const _BackgroundRings(),

            // Layer 2: Expanding NFC ripple
            _buildNfcRipple(),

            // Layer 3: Sparkle dots
            _buildSparkles(),

            // Layer 4: Logo + App name + Tagline
            _buildCenterContent(),

            // Layer 5: Privacy badge
            _buildPrivacyBadge(),

            // Layer 6: Page indicator dots
            _buildPageDots(),

            // Layer 7: Bottom loading bar
            _buildLoadingBar(),
          ],
        ),
      ),
    );
  }

  // ── NFC-style expanding ripple ─────────────────────────────────────────────
  Widget _buildNfcRipple() {
    return Center(
      child: AnimatedBuilder(
        animation: _ringController,
        builder: (_, __) => Transform.scale(
          scale: _ringScale.value,
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(_ringOpacity.value),
                width: 1.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Center: Logo card + name + tagline ────────────────────────────────────
  Widget _buildCenterContent() {
    return Center(
      child: AnimatedBuilder(
        animation: _contentController,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, _contentSlide.value),
          child: Opacity(opacity: _contentOpacity.value, child: child),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            // Logo card with combined scale animations
            AnimatedBuilder(
              animation: Listenable.merge([_logoController, _pulseController]),
              builder: (_, child) => Transform.scale(
                scale: _logoScale.value * _pulseScale.value,
                child: Opacity(opacity: _logoOpacity.value, child: child),
              ),
              child: const _LogoCard(),
            ),

            const SizedBox(height: 28),

            // TapGuard
            const Text(
              AppStrings.appName,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 44,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.5,
                height: 1.0,
              ),
            ),

            const SizedBox(height: 10),

            // Safety at your fingertips
            Text(
              AppStrings.appTagline,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: Colors.white.withOpacity(0.85),
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Privacy badge at bottom ────────────────────────────────────────────────
  Widget _buildPrivacyBadge() {
    return Positioned(
      bottom: 60,
      left: 0,
      right: 0,
      child: AnimatedBuilder(
        animation: _contentController,
        builder: (_, child) =>
            Opacity(opacity: _badgeOpacity.value, child: child),
        child: Center(
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(50),
              border: Border.all(
                color: Colors.white.withOpacity(0.22),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  color: Colors.white.withOpacity(0.9),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  AppStrings.privacyFocused,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withOpacity(0.9),
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Page indicator dots ───────────────────────────────────────────────────
  Widget _buildPageDots() {
    return const Positioned(
      bottom: 24,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _PageDot(active: true),
          SizedBox(width: 6),
          _PageDot(active: false),
          SizedBox(width: 6),
          _PageDot(active: false),
        ],
      ),
    );
  }

  // ── Bottom loading bar ────────────────────────────────────────────────────
  Widget _buildLoadingBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: AnimatedBuilder(
        animation: _loadBarController,
        builder: (_, __) => FractionallySizedBox(
          widthFactor: _loadBarWidth.value,
          alignment: Alignment.centerLeft,
          child: Container(
            height: 3,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.55),
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(2),
                bottomRight: Radius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Sparkle dots ──────────────────────────────────────────────────────────
  Widget _buildSparkles() {
    return AnimatedBuilder(
      animation: _sparkleController,
      builder: (_, __) => Stack(
        children: [
          _Sparkle(top: 130,    right: 60,  size: 8, opacity: _sparkleOpacity.value),
          _Sparkle(top: 210,    right: 100, size: 5, opacity: _sparkleOpacity.value * 0.65),
          _Sparkle(top: 105,    left: 55,   size: 6, opacity: _sparkleOpacity.value * 0.80),
          _Sparkle(top: 320,    left: 72,   size: 4, opacity: _sparkleOpacity.value * 0.50),
          _Sparkle(bottom: 220, right: 50,  size: 5, opacity: _sparkleOpacity.value * 0.60),
          _Sparkle(bottom: 170, left: 80,   size: 7, opacity: _sparkleOpacity.value * 0.90),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Private Widgets
// ══════════════════════════════════════════════════════════════════════════════

/// Frosted-glass logo card with shield icon inside
class _LogoCard extends StatelessWidget {
  const _LogoCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 114,
      height: 114,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: Colors.white.withOpacity(0.25),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.20),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.10),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: const Center(
        child: _ShieldIcon(size: 62),
      ),
    );
  }
}

/// Custom shield with person icon — drawn with CustomPainter
class _ShieldIcon extends StatelessWidget {
  final double size;
  const _ShieldIcon({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ShieldPainter()),
    );
  }
}

class _ShieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ── Shield body ────────────────────────────────────────────────────────
    final shieldPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final shieldPath = Path()
      ..moveTo(w * 0.50, h * 0.04)
      ..lineTo(w * 0.10, h * 0.20)
      ..lineTo(w * 0.10, h * 0.52)
      ..cubicTo(w * 0.10, h * 0.76, w * 0.32, h * 0.92, w * 0.50, h * 0.97)
      ..cubicTo(w * 0.68, h * 0.92, w * 0.90, h * 0.76, w * 0.90, h * 0.52)
      ..lineTo(w * 0.90, h * 0.20)
      ..close();

    canvas.drawPath(shieldPath, shieldPaint);

    // ── Person head ────────────────────────────────────────────────────────
    final personPaint = Paint()
      ..color = const Color(0xFF7C4DFF)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(w * 0.50, h * 0.37), w * 0.115, personPaint);

    // ── Person body arc ────────────────────────────────────────────────────
    final bodyPaint = Paint()
      ..color = const Color(0xFF7C4DFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.07
      ..strokeCap = StrokeCap.round;

    final bodyPath = Path()
      ..moveTo(w * 0.22, h * 0.72)
      ..quadraticBezierTo(w * 0.22, h * 0.56, w * 0.50, h * 0.56)
      ..quadraticBezierTo(w * 0.78, h * 0.56, w * 0.78, h * 0.72);

    canvas.drawPath(bodyPath, bodyPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Three concentric static rings in the background
class _BackgroundRings extends StatelessWidget {
  const _BackgroundRings();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          _ring(size: 490, opacity: 0.09),
          _ring(size: 350, opacity: 0.11),
          Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.045),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ring({required double size, required double opacity}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withOpacity(opacity),
          width: 1,
        ),
      ),
    );
  }
}

/// Single ambient sparkle dot
class _Sparkle extends StatelessWidget {
  final double? top;
  final double? bottom;
  final double? left;
  final double? right;
  final double size;
  final double opacity;

  const _Sparkle({
    this.top, this.bottom, this.left, this.right,
    required this.size,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top, bottom: bottom, left: left, right: right,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(opacity),
        ),
      ),
    );
  }
}

/// Animated page indicator dot
class _PageDot extends StatelessWidget {
  final bool active;
  const _PageDot({required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: active ? 28 : 18,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(active ? 0.85 : 0.35),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}