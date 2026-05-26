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
  late AnimationController _logoController;
  late AnimationController _pulseController;
  late AnimationController _ringController;
  late AnimationController _contentController;
  late AnimationController _loadBarController;
  late AnimationController _sparkleController;

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

  // ── Hold-to-freeze state ──────────────────────────────────────────────────
  bool _isHolding = false;
  Timer? _autoNavigateTimer;

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

  // ── Init controllers ──────────────────────────────────────────────────────
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
      duration: const Duration(milliseconds: 2800),
    );

    _sparkleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  // ── Init animations ───────────────────────────────────────────────────────
  void _initAnimations() {
    _logoScale = CurvedAnimation(
      parent: _logoController,
      curve: Curves.elasticOut,
    ).drive(Tween(begin: 0.3, end: 1.0));

    _logoOpacity = CurvedAnimation(
      parent: _logoController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
    ).drive(Tween(begin: 0.0, end: 1.0));

    _pulseScale = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ).drive(Tween(begin: 1.0, end: 1.06));

    _ringScale = CurvedAnimation(
      parent: _ringController,
      curve: Curves.easeOut,
    ).drive(Tween(begin: 0.75, end: 1.2));

    _ringOpacity = CurvedAnimation(
      parent: _ringController,
      curve: Curves.easeOut,
    ).drive(Tween(begin: 0.55, end: 0.0));

    _contentSlide = CurvedAnimation(
      parent: _contentController,
      curve: Curves.easeOutCubic,
    ).drive(Tween(begin: 32.0, end: 0.0));

    _contentOpacity = CurvedAnimation(
      parent: _contentController,
      curve: Curves.easeIn,
    ).drive(Tween(begin: 0.0, end: 1.0));

    _loadBarWidth = CurvedAnimation(
      parent: _loadBarController,
      curve: Curves.easeInOut,
    ).drive(Tween(begin: 0.0, end: 1.0));

    _sparkleOpacity = CurvedAnimation(
      parent: _sparkleController,
      curve: Curves.easeInOut,
    ).drive(Tween(begin: 0.15, end: 0.85));

    _badgeOpacity = CurvedAnimation(
      parent: _contentController,
      curve: const Interval(0.4, 1.0, curve: Curves.easeIn),
    ).drive(Tween(begin: 0.0, end: 1.0));
  }

  // ── Start entrance sequence ───────────────────────────────────────────────
  void _startSequence() async {
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;

    _logoController.forward();

    await Future.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;

    _contentController.forward();
    _loadBarController.forward();

    // Listen for load bar completion → then navigate if not holding
    _loadBarController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _tryNavigate();
      }
    });
  }

  // ── Try navigate — only if finger is NOT on screen ───────────────────────
  void _tryNavigate() {
    if (_isHolding) {
      // Finger still on screen — wait for finger lift (handled in onPointerUp)
      return;
    }
    _navigateAfterSplash();
  }

  void _navigateAfterSplash() {
    _autoNavigateTimer?.cancel();
    if (!mounted) return;

    // Always show onboarding first; onboarding then routes to login or home.
    Navigator.of(context).pushReplacementNamed(AppRoutes.onboarding);
  }

  // ── Finger DOWN — freeze everything ──────────────────────────────────────
  void _onPointerDown(PointerDownEvent event) {
    HapticFeedback.lightImpact();
    setState(() => _isHolding = true);

    // Stop all animations
    _loadBarController.stop();
    _pulseController.stop();
    _ringController.stop();
    _autoNavigateTimer?.cancel();
  }

  // ── Finger UP — resume everything ────────────────────────────────────────
  void _onPointerUp(PointerUpEvent event) {
    setState(() => _isHolding = false);

    // Resume all animations
    _pulseController.repeat(reverse: true);
    _ringController.repeat();

    // If load bar was already complete, navigate immediately
    if (_loadBarController.value >= 1.0) {
      // Small delay so user sees the resume
      _autoNavigateTimer = Timer(
        const Duration(milliseconds: 300),
        _navigateAfterSplash,
      );
    } else {
      // Resume load bar from where it stopped
      _loadBarController.forward();
    }
  }

  // ── Finger leaves screen (cancel) ────────────────────────────────────────
  void _onPointerCancel(PointerCancelEvent event) {
    if (_isHolding) {
      setState(() => _isHolding = false);
      _pulseController.repeat(reverse: true);
      _ringController.repeat();
      _loadBarController.forward();
    }
  }

  @override
  void dispose() {
    _autoNavigateTimer?.cancel();
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
    return Scaffold(
      body: Listener(
        // Using Listener (not GestureDetector) so we get
        // exact pointer down/up events without gesture competition
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: Container(
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
              // Layer 1: Static bg rings
              const _BackgroundRings(),

              // Layer 2: NFC ripple ring
              _buildNfcRipple(),

              // Layer 3: Sparkles
              _buildSparkles(),

              // Layer 4: Center content
              _buildCenterContent(),

              // Layer 5: Privacy badge
              _buildPrivacyBadge(),

              // Layer 6: Page dots
              _buildPageDots(),

              // Layer 7: Loading bar
              _buildLoadingBar(),
            ],
          ),
        ),
      ),
    );
  }

  // ── NFC ripple ────────────────────────────────────────────────────────────
  Widget _buildNfcRipple() {
    return Center(
      child: AnimatedBuilder(
        animation: _ringController,
        builder: (_, _) => Transform.scale(
          scale: _ringScale.value,
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha:_ringOpacity.value),
                width: 1.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Center: logo + name + tagline ─────────────────────────────────────────
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
            // Logo card
            AnimatedBuilder(
              animation: Listenable.merge([_logoController, _pulseController]),
              builder: (_, child) => Transform.scale(
                scale: _logoScale.value * _pulseScale.value,
                child: Opacity(opacity: _logoOpacity.value, child: child),
              ),
              child: const _LogoCard(),
            ),

            const SizedBox(height: 28),

            // App name
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

            // Tagline
            Text(
              AppStrings.appTagline,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: Colors.white.withValues(alpha:0.85),
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Privacy badge ─────────────────────────────────────────────────────────
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha:0.14),
              borderRadius: BorderRadius.circular(50),
              border: Border.all(
                color: Colors.white.withValues(alpha:0.22),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  color: Colors.white.withValues(alpha:0.9),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  AppStrings.privacyFocused,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha:0.9),
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

  // ── Page dots ─────────────────────────────────────────────────────────────
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

  // ── Loading bar ───────────────────────────────────────────────────────────
  Widget _buildLoadingBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: AnimatedBuilder(
        animation: _loadBarController,
        builder: (_, _) => FractionallySizedBox(
          widthFactor: _loadBarWidth.value,
          alignment: Alignment.centerLeft,
          child: Container(
            height: 3,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha:0.55),
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

  // ── Sparkles ──────────────────────────────────────────────────────────────
  Widget _buildSparkles() {
    return AnimatedBuilder(
      animation: _sparkleController,
      builder: (_, _) => Stack(
        children: [
          _Sparkle(
            top: 130,
            right: 60,
            size: 8,
            opacity: _sparkleOpacity.value,
          ),
          _Sparkle(
            top: 210,
            right: 100,
            size: 5,
            opacity: _sparkleOpacity.value * 0.65,
          ),
          _Sparkle(
            top: 105,
            left: 55,
            size: 6,
            opacity: _sparkleOpacity.value * 0.80,
          ),
          _Sparkle(
            top: 320,
            left: 72,
            size: 4,
            opacity: _sparkleOpacity.value * 0.50,
          ),
          _Sparkle(
            bottom: 220,
            right: 50,
            size: 5,
            opacity: _sparkleOpacity.value * 0.60,
          ),
          _Sparkle(
            bottom: 170,
            left: 80,
            size: 7,
            opacity: _sparkleOpacity.value * 0.90,
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Private Sub-Widgets (unchanged from before)
// ══════════════════════════════════════════════════════════════════════════════

class _LogoCard extends StatelessWidget {
  const _LogoCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 114,
      height: 114,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha:0.16),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha:0.25), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.20),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha:0.10),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: const Center(child: _ShieldIcon(size: 62)),
    );
  }
}

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

    // Shield body
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.50, h * 0.04)
        ..lineTo(w * 0.10, h * 0.20)
        ..lineTo(w * 0.10, h * 0.52)
        ..cubicTo(w * 0.10, h * 0.76, w * 0.32, h * 0.92, w * 0.50, h * 0.97)
        ..cubicTo(w * 0.68, h * 0.92, w * 0.90, h * 0.76, w * 0.90, h * 0.52)
        ..lineTo(w * 0.90, h * 0.20)
        ..close(),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );

    // Person head
    canvas.drawCircle(
      Offset(w * 0.50, h * 0.37),
      w * 0.115,
      Paint()
        ..color = const Color(0xFF7C4DFF)
        ..style = PaintingStyle.fill,
    );

    // Person body arc
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.22, h * 0.72)
        ..quadraticBezierTo(w * 0.22, h * 0.56, w * 0.50, h * 0.56)
        ..quadraticBezierTo(w * 0.78, h * 0.56, w * 0.78, h * 0.72),
      Paint()
        ..color = const Color(0xFF7C4DFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.07
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

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
              color: Colors.white.withValues(alpha:0.045),
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
        border: Border.all(color: Colors.white.withValues(alpha:opacity), width: 1),
      ),
    );
  }
}

class _Sparkle extends StatelessWidget {
  final double? top, bottom, left, right, size, opacity;
  const _Sparkle({
    this.top,
    this.bottom,
    this.left,
    this.right,
    required this.size,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha:opacity!),
        ),
      ),
    );
  }
}

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
        color: Colors.white.withValues(alpha:active ? 0.85 : 0.35),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
