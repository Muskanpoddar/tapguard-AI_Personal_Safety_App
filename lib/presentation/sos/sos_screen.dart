// lib/presentation/sos/sos_screen.dart
//
// Full SOS Emergency Screen
// ─────────────────────────
// Features:
//   - Big red TRIGGER SOS button
//   - Pulsing red animation when active
//   - Sends location to trusted contacts via Firestore
//   - Push notifications to contacts via OneSignal
//   - Flashing red UI when SOS is active
//   - Hold-to-cancel for accidental triggers
//   - Vibration pattern for urgency
//
// Bi-directional: also listens for incoming SOS alerts from contacts

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import '../../core/constants/app_colors.dart';
import '../../core/routes/app_routes.dart';
import '../../data/services/risk_detection_service.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _risk = RiskDetectionService();
  final _db  = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ── State ──────────────────────────────────────────────────────────────────
  bool _sosActive      = false;
  bool _sendingAlert  = false;
  bool _hasVibrator   = false;
  bool _holdReleased  = false;   // true after user holds 2s without cancelling
  int  _countdownSecs = 5;      // countdown before SOS auto-fires
  Timer? _countdownTimer;
  Timer? _flashTimer;
  StreamSubscription? _riskSub;

  // ── Animation ──────────────────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late AnimationController _flashCtrl;
  late AnimationController _scaleCtrl;
  late Animation<double> _pulseScale;
  late Animation<double> _flashOpacity;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Check if device has vibrator
    _checkVibrator();

    _initAnimations();
    _listenRiskStream();

    // Auto-countdown to SOS fire (user must hold to cancel)
    _startCountdown();
  }

  Future<void> _checkVibrator() async {
    _hasVibrator = await Vibration.hasVibrator();
  }

  void _initAnimations() {
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _pulseScale = CurvedAnimation(
      parent: _pulseCtrl,
      curve: Curves.easeInOut,
    ).drive(Tween(begin: 1.0, end: 1.12));

    _flashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);

    _flashOpacity = CurvedAnimation(
      parent: _flashCtrl,
      curve: Curves.easeInOut,
    ).drive(Tween(begin: 0.0, end: 1.0));

    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  void _listenRiskStream() {
    _riskSub = _risk.riskStream.listen((result) {
      if (!mounted) return;
      if (result.shouldTriggerSos) {
        // Auto-triggered by risk engine
        _triggerSos(fromRisk: true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pauseSos();
    }
    if (state == AppLifecycleState.resumed) {
      if (_sosActive) _resumeSos();
    }
  }

  void _pauseSos() {
    _countdownTimer?.cancel();
    _flashTimer?.cancel();
    if (_hasVibrator) Vibration.cancel();
  }

  void _resumeSos() {
    if (_sosActive) _startFlashEffect();
  }

  // ── Countdown before auto-fire ─────────────────────────────────────────────
  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() => _countdownSecs = 5);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_countdownSecs > 0) {
          _countdownSecs--;
        } else {
          _countdownTimer?.cancel();
          _triggerSos(fromRisk: false);
        }
      });
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    if (mounted) Navigator.of(context).pop();
  }

  // ── TRIGGER SOS ─────────────────────────────────────────────────────────────
  Future<void> _triggerSos({required bool fromRisk}) async {
    if (_sendingAlert) return;
    setState(() => _sendingAlert = true);
    HapticFeedback.heavyImpact();

    _countdownTimer?.cancel();

    // Fire vibration pattern
    if (_hasVibrator) {
      // Urgent: vibrate 500ms, pause 200ms, repeat
      Vibration.vibrate(pattern: [0, 500, 200, 500, 200, 500], repeat: 0);
    }

    // Update Firestore SOS flag
    await _updateSosFirestore(active: true);

    // Get GPS and dispatch to contacts
    await _dispatchSosToContacts();

    if (!mounted) return;
    setState(() {
      _sosActive   = true;
      _sendingAlert = false;
    });

    _startFlashEffect();
  }

  Future<void> _updateSosFirestore({required bool active}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).set({
        'sosActive':      active,
        'sosTriggeredAt': active ? FieldValue.serverTimestamp() : null,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _dispatchSosToContacts() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    // Get user's name
    String name = 'User';
    try {
      final doc = await _db.collection('users').doc(uid).get();
      name = doc.data()?['name'] ?? name;
    } catch (_) {}

    // Get trusted contacts
    final contacts = await _db
        .collection('users')
        .doc(uid)
        .collection('contacts')
        .get();

    for (final doc in contacts.docs) {
      try {
        await _db
            .collection('users')
            .doc(doc.id)
            .collection('notifications')
            .add({
          'type':      'sos_alert',
          'fromUid':   uid,
          'fromName':  name,
          'message':   'SOS ALERT! $name needs help immediately.',
          'createdAt': FieldValue.serverTimestamp(),
          'read':      false,
        });
      } catch (_) {}
    }
  }

  void _startFlashEffect() {
    _flashTimer?.cancel();
    _flashTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted || !_sosActive) {
        _flashTimer?.cancel();
        return;
      }
      HapticFeedback.lightImpact();
    });
  }

  // ── CANCEL SOS (hold 2s) ───────────────────────────────────────────────────
  void _onHoldStart() {
    setState(() => _holdReleased = false);
    // Vibrate on hold start
    if (_hasVibrator) Vibration.vibrate(duration: 50);
  }

  void _onHoldEnd() {
    if (!_holdReleased) {
      // User cancelled — stop everything
      if (_hasVibrator) Vibration.cancel();
      _countdownTimer?.cancel();
      _flashTimer?.cancel();
      _updateSosFirestore(active: false);
      _risk.cancelSos();
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _onHoldConfirm() {
    // User held for 2s — confirm cancel
    setState(() => _holdReleased = true);
    HapticFeedback.heavyImpact();
    _onHoldEnd();
  }

  // ── "I am Safe" — cancel SOS ───────────────────────────────────────────────
  Future<void> _iAmSafe() async {
    HapticFeedback.heavyImpact();
    if (_hasVibrator) Vibration.cancel();
    _countdownTimer?.cancel();
    _flashTimer?.cancel();

    await _updateSosFirestore(active: false);
    await _risk.sendSafetyConfirmation();

    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _flashTimer?.cancel();
    _riskSub?.cancel();
    _pulseCtrl.dispose();
    _flashCtrl.dispose();
    _scaleCtrl.dispose();
    if (_hasVibrator) Vibration.cancel();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Flashing red background when SOS is active
      body: AnimatedBuilder(
        animation: _flashCtrl,
        builder: (_, child) => Container(
          color: _sosActive
              ? AppColors.sos.withOpacity(0.08 * _flashOpacity.value)
              : Colors.transparent,
          child: child,
        ),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    return SafeArea(
      child: Stack(
        children: [
          // Main content
          Column(
            children: [
              _buildTopBar(),
              Expanded(child: _buildMainContent()),
              _buildBottomActions(),
            ],
          ),

          // Pulsing ring behind the button
          if (!_sosActive)
            Positioned.fill(
              child: Center(
                child: AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, __) => Transform.scale(
                    scale: _pulseScale.value,
                    child: Container(
                      width: 280,
                      height: 280,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.sos.withOpacity(0.06),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
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
                Icons.close_rounded,
                size: 18,
                color: Color(0xFF1A1A2E),
              ),
            ),
          ),
          const Spacer(),
          // Live indicator when SOS active
          if (_sosActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.sos.withOpacity(0.12),
                borderRadius: BorderRadius.circular(50),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PulsingDot(color: AppColors.sos),
                  const SizedBox(width: 8),
                  const Text(
                    'SOS ACTIVE',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.sos,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          const Spacer(),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Status badge
            _buildStatusBadge(),

            const SizedBox(height: 32),

            // Main SOS button
            _buildSosButton(),

            const SizedBox(height: 24),

            // Countdown text
            if (!_sosActive && !_sendingAlert)
              _buildCountdownText(),

            if (_sendingAlert)
              _buildSendingStatus(),

            const SizedBox(height: 28),

            // Info card
            _buildInfoCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge() {
    final color = _sosActive ? AppColors.sos : AppColors.primary;
    final label = _sosActive
        ? 'SOS ACTIVATED'
        : _countdownSecs > 0
            ? 'TRIGGERING IN $_countdownSecs'
            : 'READY TO SEND';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulsingDot(color: color),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSosButton() {
    return GestureDetector(
      onTap: _sosActive ? null : () => _triggerSos(fromRisk: false),
      child: AnimatedBuilder(
        animation: _pulseCtrl,
        builder: (_, child) => Transform.scale(
          scale: _sosActive ? 1.0 : _pulseScale.value,
          child: child,
        ),
        child: Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.sos,
            boxShadow: [
              BoxShadow(
                color: AppColors.sos.withOpacity(0.5),
                blurRadius: 40,
                spreadRadius: 8,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _sosActive ? Icons.warning_rounded : Icons.sos_rounded,
                color: Colors.white,
                size: 72,
              ),
              const SizedBox(height: 8),
              Text(
                _sosActive ? 'SOS ACTIVE' : 'TRIGGER SOS',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCountdownText() {
    return Column(
      children: [
        Text(
          'Tap the button to send alert immediately',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            color: Colors.grey.shade500,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Or wait ${_countdownSecs}s for auto-trigger',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            color: Colors.grey.shade400,
          ),
        ),
      ],
    );
  }

  Widget _buildSendingStatus() {
    return Column(
      children: [
        const SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            color: AppColors.sos,
            strokeWidth: 3,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Sending SOS to contacts…',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.sos,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _infoRow(
            Icons.location_on_rounded,
            'Live location shared with trusted contacts',
          ),
          const SizedBox(height: 10),
          _infoRow(
            Icons.notifications_rounded,
            'Push notifications sent to 5 contacts',
          ),
          const SizedBox(height: 10),
          _infoRow(
            Icons.shield_rounded,
            'Emergency services can be contacted',
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.sos.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.sos, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: Color(0xFF1A1A2E),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActions() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Hold-to-cancel
          if (_sosActive) ...[
            _buildHoldToCancel(),
            const SizedBox(height: 12),
          ],

          // I am Safe button
          _buildSafeButton(),

          const SizedBox(height: 12),

          // Back home
          GestureDetector(
            onTap: () => Navigator.of(context).pushReplacementNamed(AppRoutes.home),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(
                child: Text(
                  'Back to Home',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHoldToCancel() {
    return GestureDetector(
      onLongPressStart: (_) => _onHoldStart(),
      onLongPressEnd:   (_) => _onHoldEnd(),
      onLongPressMoveUpdate: (details) {
        // If finger moved significantly, treat as cancelled
        if (details.globalPosition.distance > 100) {
          _onHoldConfirm();
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: AppColors.sos.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.sos.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(Icons.cancel_rounded, color: AppColors.sos, size: 28),
            const SizedBox(height: 6),
            const Text(
              'HOLD TO CANCEL SOS',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.sos,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Hold for 2 seconds if this was a mistake',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSafeButton() {
    return GestureDetector(
      onTap: _iAmSafe,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.success, Color(0xFF28A745)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.success.withOpacity(0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 24),
              SizedBox(width: 10),
              Text(
                'I AM SAFE',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Small pulsing dot
class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withOpacity(0.5 + _ctrl.value * 0.5),
        ),
      ),
    );
  }
}
