// lib/presentation/session/active_session_screen.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';
import '../../core/routes/app_routes.dart';
import '../../data/models/session_model.dart';
import '../../data/services/session_service.dart';
import '../../data/services/notification_service.dart';

class ActiveSessionScreen extends StatefulWidget {
  const ActiveSessionScreen({super.key});

  @override
  State<ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends State<ActiveSessionScreen>
    with TickerProviderStateMixin {
  final _sessionService = SessionService();
  final _notifService = NotificationService(); // ← NEW
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  SessionModel? _session;
  StreamSubscription? _sessionSub;
  bool _isEnding = false;
  bool _isSafe = false;

  // Timer state
  int _totalSeconds = 20 * 60;
  int _remainingSeconds = 20 * 60;
  bool _timerRunning = false;
  Timer? _countdownTimer;

  // Animations
  late AnimationController _ringAnim;
  late AnimationController _safeAnim;
  late Animation<double> _safeScale;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    _initAnimations();
    _loadSession();
  }

  void _initAnimations() {
    _ringAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _safeAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _safeScale = CurvedAnimation(
      parent: _safeAnim,
      curve: Curves.elasticOut,
    ).drive(Tween(begin: 0.8, end: 1.0));
  }

  void _loadSession() {
    final active = _sessionService.activeSession;
    if (active != null) {
      setState(() => _session = active);
      _watchSession(active.sessionId);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showTimerPicker();
    });
  }

  void _watchSession(String sessionId) {
    _sessionSub?.cancel();
    _sessionSub = _sessionService.watchSession(sessionId).listen((s) {
      if (!mounted || s == null) return;
      setState(() => _session = s);
      if (!s.isActive) _navigateHome();
    });
  }

  // ── Timer picker bottom sheet ─────────────────────────────────────────────
  void _showTimerPicker() {
    final options = [
      {'label': '10 min', 'seconds': 10 * 60},
      {'label': '20 min', 'seconds': 20 * 60},
      {'label': '30 min', 'seconds': 30 * 60},
      {'label': '45 min', 'seconds': 45 * 60},
      {'label': '1 hour', 'seconds': 60 * 60},
      {'label': '2 hours', 'seconds': 120 * 60},
      {'label': 'Custom', 'seconds': -1},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Set Safety Timer',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Timer reminds your contact to check on you',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: options.map((o) {
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    if (o['seconds'] == -1) {
                      _showCustomTimer();
                    } else {
                      _setTimer(o['seconds'] as int);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha:0.08),
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha:0.3),
                      ),
                    ),
                    child: Text(
                      o['label'] as String,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ── Custom timer ──────────────────────────────────────────────────────────
  void _showCustomTimer() {
    int customMinutes = 30;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Custom Duration',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter minutes:',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                hintText: '30',
                filled: true,
                fillColor: const Color(0xFFF0EFF5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppColors.primary,
                    width: 1.5,
                  ),
                ),
              ),
              onChanged: (v) => customMinutes = int.tryParse(v) ?? 30,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.grey.shade500,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _setTimer(customMinutes.clamp(1, 480) * 60);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Set',
              style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // ── Set and start timer ───────────────────────────────────────────────────
  void _setTimer(int seconds) {
    _countdownTimer?.cancel();
    setState(() {
      _totalSeconds = seconds;
      _remainingSeconds = seconds;
      _timerRunning = true;
    });
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        } else {
          _countdownTimer?.cancel();
          _timerRunning = false;
          _onTimerEnd();
        }
      });
    });
  }

  // ── Timer ended — vibrate + push notification + local alert ──────────────
  void _onTimerEnd() {
    HapticFeedback.heavyImpact();

    // 1. Vibrate urgently on THIS device
    _notifService.vibrateTimerEnd();

    // 2. Send push notification to all active contacts via OneSignal
    if (_session != null) {
      _notifService.alertContactsTimerEnded(
        ownerUid: _session!.ownerUid,
        ownerName: _session!.ownerName,
        sessionId: _session!.sessionId,
      );
    }

    // 3. Show dialog on screen
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '⏰ Timer Ended',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Are you safe? Tap "I am Safe" to confirm '
          'or extend your timer.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 14),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _iAmSafe();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'I am Safe',
              style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _notifService.stopVibration(); // stop vibration when extending
              _showTimerPicker();
            },
            child: const Text(
              'Extend Timer',
              style: TextStyle(fontFamily: 'Poppins', color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  String get _timerDisplay {
    final h = _remainingSeconds ~/ 3600;
    final m = (_remainingSeconds % 3600) ~/ 60;
    final s = _remainingSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  double get _timerProgress =>
      _totalSeconds > 0 ? _remainingSeconds / _totalSeconds : 0;

  // ── I am Safe ─────────────────────────────────────────────────────────────
  Future<void> _iAmSafe() async {
    HapticFeedback.heavyImpact();
    _safeAnim.reset();
    _safeAnim.forward();
    setState(() => _isSafe = true);

    try {
      if (_session != null) {
        await _db.collection('sessions').doc(_session!.sessionId).update({
          'lastSafeAt': FieldValue.serverTimestamp(),
          'isSafe': true,
        });

        // Stop vibration + notify contacts user is safe
        _notifService.stopVibration();
        _notifService.notifyContactsUserSafe(
          ownerUid: _session!.ownerUid,
          ownerName: _session!.ownerName,
        );
      }
    } catch (_) {}

    // Reset timer to same duration
    _setTimer(_totalSeconds);

    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _isSafe = false);
  }

  // ── End session ───────────────────────────────────────────────────────────
  Future<void> _endSession() async {
    if (_isEnding) return;
    setState(() => _isEnding = true);
    HapticFeedback.mediumImpact();
    _countdownTimer?.cancel();

    try {
      // Notify contacts session ended
      if (_session != null) {
        _notifService.notifySessionEnded(
          ownerUid: _session!.ownerUid,
          ownerName: _session!.ownerName,
        );
      }

      await _sessionService.endSession();

      final uid = _auth.currentUser?.uid;
      if (uid != null && _session != null) {
        final snap = await _db
            .collection('users')
            .doc(uid)
            .collection('contacts')
            .where('sessionId', isEqualTo: _session!.sessionId)
            .get();
        for (final doc in snap.docs) {
          await doc.reference.update({
            'isActive': false,
            'lastSeen': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (_) {}

    _navigateHome();
  }

  void _navigateHome() {
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _sessionSub?.cancel();
    _ringAnim.dispose();
    _safeAnim.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isConnected = _session?.receiverJoined == true;
    final contactName = _session?.receiverName ?? 'Waiting…';

    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F3F8),
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            margin: const EdgeInsets.all(8),
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
        title: const Text(
          'Active Session',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A2E),
          ),
        ),
        centerTitle: true,
        actions: [
          GestureDetector(
            onTap: () => Navigator.of(context).pushNamed(AppRoutes.settings),
            child: Container(
              margin: const EdgeInsets.all(8),
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
                Icons.settings_rounded,
                size: 18,
                color: Color(0xFF1A1A2E),
              ),
            ),
          ),
        ],
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
                children: [
                  // Connected badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: isConnected
                          ? AppColors.success.withValues(alpha:0.10)
                          : AppColors.primary.withValues(alpha:0.10),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.5, end: 1.0),
                          duration: const Duration(milliseconds: 800),
                          curve: Curves.easeInOut,
                          builder: (_, v, _) => Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color:
                                  (isConnected
                                          ? AppColors.success
                                          : AppColors.primary)
                                      .withValues(alpha:v),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isConnected
                              ? 'Connected to $contactName'
                              : 'Waiting for connection…',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isConnected
                                ? AppColors.success
                                : AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),
                  _buildTimerCircle(),
                  const SizedBox(height: 20),

                  // Live badge + Change timer
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.crop_square_rounded,
                              size: 14,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'LIVE NFC SHARING ACTIVE',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: _showTimerPicker,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha:0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha:0.3),
                            ),
                          ),
                          child: Row(
                            children: const [
                              Icon(
                                Icons.timer_rounded,
                                size: 14,
                                color: AppColors.primary,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Change',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // I am Safe button
                  ScaleTransition(
                    scale: _safeScale,
                    child: GestureDetector(
                      onTap: _isSafe ? null : _iAmSafe,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 22,
                          horizontal: 22,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: _isSafe
                                ? [
                                    AppColors.success,
                                    AppColors.success.withValues(alpha:0.8),
                                  ]
                                : [
                                    AppColors.primary,
                                    AppColors.primary.withValues(alpha:0.85),
                                  ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  (_isSafe
                                          ? AppColors.success
                                          : AppColors.primary)
                                      .withValues(alpha:0.35),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isSafe ? '✓ You are Safe!' : 'I am Safe',
                                  style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _isSafe
                                      ? 'Contact notified • Timer reset'
                                      : 'Confirms status & resets timer',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 12,
                                    color: Colors.white.withValues(alpha:0.85),
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha:0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _isSafe
                                    ? Icons.check_circle_rounded
                                    : Icons.shield_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // End Session
                  GestureDetector(
                    onTap: _isEnding ? null : _showEndConfirm,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 20,
                        horizontal: 22,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha:0.04),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'End Session',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1A1A2E),
                                ),
                              ),
                              Text(
                                'Stop sharing your location',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                            ],
                          ),
                          _isEnding
                              ? const SizedBox(
                                  width: 26,
                                  height: 26,
                                  child: CircularProgressIndicator(
                                    color: AppColors.primary,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.cancel_rounded,
                                    color: Colors.grey.shade400,
                                    size: 22,
                                  ),
                                ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 12,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Your location is encrypted & visible only to your contact.',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                 ],
               ),
             ),
           ),
         );
       }

  // ── Timer circle ──────────────────────────────────────────────────────────
  Widget _buildTimerCircle() {
    final isLow = _timerProgress < 0.2 && _timerRunning;
    final color = _isSafe
        ? AppColors.success
        : isLow
        ? AppColors.sos
        : AppColors.primary;

    return SizedBox(
      width: 250,
      height: 250,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _ringAnim,
            builder: (_, _) => Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha:0.04 + _ringAnim.value * 0.05),
              ),
            ),
          ),

          SizedBox(
            width: 220,
            height: 220,
            child: CircularProgressIndicator(
              value: _timerProgress,
              strokeWidth: 6,
              backgroundColor: color.withValues(alpha:0.12),
              valueColor: AlwaysStoppedAnimation(color),
              strokeCap: StrokeCap.round,
            ),
          ),

          Container(
            width: 190,
            height: 190,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha:0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
          ),

          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isSafe)
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.success,
                  size: 36,
                )
              else
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 300),
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: _timerDisplay.length > 5 ? 38 : 46,
                    fontWeight: FontWeight.w700,
                    color: color,
                    height: 1.0,
                  ),
                  child: Text(_timerRunning ? _timerDisplay : '--:--'),
                ),
              const SizedBox(height: 4),
              Text(
                _isSafe
                    ? 'SAFE ✓'
                    : _timerRunning
                    ? 'REMAINING'
                    : 'TAP CHANGE TO SET',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade400,
                  letterSpacing: 1.5,
                ),
              ),
              if (isLow && !_isSafe) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.sos.withValues(alpha:0.10),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: const Text(
                    '⚠ Time low',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.sos,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── End confirm dialog ────────────────────────────────────────────────────
  void _showEndConfirm() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'End Session?',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'This will stop sharing your location with your contact.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.grey.shade500,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _endSession();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.sos,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'End Session',
              style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
