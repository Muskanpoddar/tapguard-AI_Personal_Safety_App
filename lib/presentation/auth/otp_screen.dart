// lib/presentation/auth/otp_screen.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/constants/app_colors.dart';
import '../../core/routes/app_routes.dart';
import '../../data/services/auth_session_service.dart';
import '../../data/services/email_otp_service.dart';

class OtpScreen extends StatefulWidget {
  final String email;
  const OtpScreen({super.key, required this.email});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> with TickerProviderStateMixin {
  static const int _len = 6;
  static const int _tick = 60;
  static const double _gap = 8;

  final List<TextEditingController> _ctrl = List.generate(
    _len,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _fn = List.generate(_len, (_) => FocusNode());

  bool _loading = false;
  bool _success = false;
  int _secs = _tick;
  Timer? _timer;

  late List<AnimationController> _stagger;
  late List<Animation<double>> _stFade;
  late List<Animation<double>> _stSlide;
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;
  late AnimationController _pulseCtrl;

  String get _code => _ctrl.map((c) => c.text).join();
  bool get _filled => _code.length == _len;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _startTimer();
    for (final c in _ctrl) {
      c.addListener(() {
        if (mounted) setState(() {});
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 750), () {
        if (mounted) FocusScope.of(context).requestFocus(_fn[0]);
      });
    });
  }

  void _initAnimations() {
    _stagger = List.generate(
      4,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      ),
    );
    _stFade = _stagger
        .map(
          (c) => CurvedAnimation(
            parent: c,
            curve: Curves.easeIn,
          ).drive(Tween(begin: 0.0, end: 1.0)),
        )
        .toList();
    _stSlide = _stagger
        .map(
          (c) => CurvedAnimation(
            parent: c,
            curve: Curves.easeOutCubic,
          ).drive(Tween(begin: 36.0, end: 0.0)),
        )
        .toList();

    for (int i = 0; i < 4; i++) {
      Future.delayed(Duration(milliseconds: i * 120), () {
        if (mounted) _stagger[i].forward();
      });
    }

    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnim = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -12.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -12.0, end: 12.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 12.0, end: -8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: 0.0), weight: 1),
    ]).animate(_shakeCtrl);

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secs = _tick);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _secs--;
        if (_secs <= 0) t.cancel();
      });
    });
  }

  void _shake() {
    _shakeCtrl.reset();
    _shakeCtrl.forward();
  }

  @override
  void dispose() {
    for (final c in _ctrl) {
      c.dispose();
    }
    for (final f in _fn) {
      f.dispose();
    }
    _timer?.cancel();
    for (final c in _stagger) {
      c.dispose();
    }
    _shakeCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Input handlers ────────────────────────────────────────────────────────
  void _onChange(int idx, String val) {
    if (val.length > 1) {
      final digits = val.replaceAll(RegExp(r'\D'), '');
      for (int i = 0; i < _len; i++) {
        _ctrl[i].text = i < digits.length ? digits[i] : '';
      }
      final next = digits.length < _len ? digits.length : _len - 1;
      FocusScope.of(context).requestFocus(_fn[next]);
      setState(() {});
      if (_filled) _verify();
      return;
    }
    if (val.isNotEmpty && idx < _len - 1) {
      FocusScope.of(context).requestFocus(_fn[idx + 1]);
    }
    setState(() {});
    if (_filled) Future.delayed(const Duration(milliseconds: 100), _verify);
  }

  void _onKey(int idx, KeyEvent e) {
    if (e is KeyDownEvent &&
        e.logicalKey == LogicalKeyboardKey.backspace &&
        _ctrl[idx].text.isEmpty &&
        idx > 0) {
      _ctrl[idx - 1].clear();
      FocusScope.of(context).requestFocus(_fn[idx - 1]);
      setState(() {});
    }
  }

  // ── Verify OTP ────────────────────────────────────────────────────────────
  Future<void> _verify() async {
    if (!_filled || _loading || _success) return;
    FocusScope.of(context).unfocus();
    HapticFeedback.mediumImpact();
    setState(() => _loading = true);

    final valid = EmailOtpService.verifyOtp(widget.email, _code);

    if (!valid) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Wrong code. Please check and try again.', error: true);
      _shake();
      return;
    }

    // Sign in anonymously so Firestore auth works
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _loading = false;
      _success = true;
    });

    await AuthSessionService.markSessionVerified(widget.email);
    HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 850));
    if (!mounted) return;

    // ── KEY FIX: check if user already has a profile ──────────────────────
    // New user    → go to Profile Setup
    // Existing user → go directly to Home
    bool hasProfile = false;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        hasProfile =
            doc.exists && (doc.data()?['name'] as String? ?? '').isNotEmpty;
      }
    } catch (_) {
      // Non-fatal — if check fails, send to profile setup
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(
      hasProfile ? AppRoutes.home : AppRoutes.profileSetup,
    );
  }

  // ── Resend OTP ────────────────────────────────────────────────────────────
  Future<void> _resend() async {
    if (_secs > 0) return;
    HapticFeedback.lightImpact();
    _startTimer();
    final error = await EmailOtpService.sendOtp(widget.email);
    if (!mounted) return;
    if (error != null) {
      _snack(error, error: true);
    } else {
      _snack('New code sent to ${widget.email}', error: false);
    }
  }

  void _snack(String msg, {required bool error}) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
          backgroundColor: error ? AppColors.sos : AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        ),
      );

  Widget _fade(int i, Widget child) => AnimatedBuilder(
    animation: _stagger[i],
    builder: (_, w) => Transform.translate(
      offset: Offset(0, _stSlide[i].value),
      child: Opacity(opacity: _stFade[i].value, child: w),
    ),
    child: child,
  );

  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 16),
                _fade(0, _buildBackButton()),
                const SizedBox(height: 24),
                _fade(1, _buildTopIcon()),
                const SizedBox(height: 24),
                _fade(2, _buildTitle()),
                const SizedBox(height: 32),
                _fade(3, _success ? _buildSuccessBody() : _buildCard()),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackButton() => Align(
    alignment: Alignment.centerLeft,
    child: GestureDetector(
      onTap: () => Navigator.of(context).pop(),
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
  );

  Widget _buildTopIcon() => Container(
    width: 80,
    height: 80,
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha:0.1),
      shape: BoxShape.circle,
    ),
    child: const Icon(
      Icons.mark_email_unread_rounded,
      size: 38,
      color: AppColors.primary,
    ),
  );

  Widget _buildTitle() => Column(
    children: [
      const Text(
        'Verification Code',
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 26,
          fontWeight: FontWeight.w800,
          color: Color(0xFF1A1A2E),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'We sent a 6-digit code to\n${widget.email}',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 14,
          color: Colors.grey.shade600,
          height: 1.6,
        ),
      ),
    ],
  );

  Widget _buildCard() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha:0.06),
          blurRadius: 24,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Column(
      children: [
        // Digit boxes with shake
        AnimatedBuilder(
          animation: _shakeAnim,
          builder: (_, child) => Transform.translate(
            offset: Offset(_shakeAnim.value, 0),
            child: child,
          ),
          child: LayoutBuilder(
            builder: (ctx, box) {
              final boxW = (box.maxWidth - (_len - 1) * _gap) / _len;
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_len, (i) {
                  final isFilled = _ctrl[i].text.isNotEmpty;
                  return Padding(
                    padding: EdgeInsets.only(right: i < _len - 1 ? _gap : 0),
                    child: _buildDigitBox(i, boxW, isFilled),
                  );
                }),
              );
            },
          ),
        ),

        const SizedBox(height: 28),

        // Verify button
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: (_filled && !_loading) ? _verify : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              disabledBackgroundColor: AppColors.primary.withValues(alpha:0.35),
              disabledForegroundColor: Colors.white70,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _loading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : const Text(
                    'Verify Code',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),

        const SizedBox(height: 20),
        _buildResendRow(),
      ],
    ),
  );

  Widget _buildDigitBox(int idx, double width, bool filled) => SizedBox(
    width: width,
    height: width * 1.2,
    child: KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: (e) => _onKey(idx, e),
      child: TextField(
        controller: _ctrl[idx],
        focusNode: _fn[idx],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(1),
        ],
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: width * 0.42,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF1A1A2E),
        ),
        decoration: InputDecoration(
          filled: true,
          fillColor: filled
              ? AppColors.primary.withValues(alpha:0.08)
              : const Color(0xFFF0EFF5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: filled
                  ? AppColors.primary.withValues(alpha:0.4)
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: (v) => _onChange(idx, v),
        onTap: () {
          _ctrl[idx].selection = TextSelection(
            baseOffset: 0,
            extentOffset: _ctrl[idx].text.length,
          );
        },
      ),
    ),
  );

  Widget _buildResendRow() {
    final canResend = _secs <= 0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "Didn't receive code?  ",
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            color: Colors.grey.shade500,
          ),
        ),
        GestureDetector(
          onTap: canResend ? _resend : null,
          child: Text(
            canResend ? 'Resend' : 'Resend in ${_secs}s',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: canResend ? AppColors.primary : Colors.grey.shade400,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessBody() => AnimatedBuilder(
    animation: _pulseCtrl,
    builder: (_, child) =>
        Transform.scale(scale: 1.0 + _pulseCtrl.value * 0.04, child: child),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.success.withValues(alpha:0.18),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha:0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              size: 46,
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Verified!',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your email has been\nsuccessfully verified.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              color: Colors.grey.shade500,
              height: 1.6,
            ),
          ),
        ],
      ),
    ),
  );
}
