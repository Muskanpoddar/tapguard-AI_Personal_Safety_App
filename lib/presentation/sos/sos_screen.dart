// lib/presentation/sos/sos_screen.dart
//
// SOS Emergency Screen — pure UI.
//
// All dispatch/cancel business logic lives in `SosService` and is
// orchestrated by `sosControllerProvider` (`SosState` machine).
// This file owns:
//   * The big red TRIGGER SOS button + pulsing animation
//   * Flashing red background + vibration when SOS is active
//   * Hold-to-cancel gesture (accidental trigger guard)
//   * "I Am Safe" button
//   * Risk-detection auto-trigger subscription
//
// Bi-directional: also listens for incoming SOS alerts from contacts
// (handled elsewhere — `NotificationService`).

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibration/vibration.dart';
import '../../core/constants/app_colors.dart';
import '../../data/services/risk_detection_service.dart';
import '../../data/services/sos_service.dart';
import '../../providers/profile_provider.dart';
import '../../providers/sos_provider.dart';

class SosScreen extends ConsumerStatefulWidget {
  const SosScreen({super.key});

  @override
  ConsumerState<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends ConsumerState<SosScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _risk = RiskDetectionService();

  // Local UI state
  bool _hasVibrator = false;
  bool _holdReleased = false;
  Timer? _flashTimer;
  StreamSubscription? _riskSub;

  /// Rolling buffer of dispatch events for the live log widget.
  final List<DispatchEvent> _dispatchLog = [];
  StreamSubscription? _dispatchSub;

  // Animation controllers
  late AnimationController _pulseCtrl;
  late AnimationController _flashCtrl;
  late AnimationController _scaleCtrl;
  late Animation<double> _pulseScale;
  late Animation<double> _flashOpacity;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _checkVibrator();
    _initAnimations();
    _listenRiskStream();
  }

  Future<void> _checkVibrator() async {
    try {
      _hasVibrator = await Vibration.hasVibrator();
    } catch (_) {
      _hasVibrator = false;
    }
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
        // Auto-triggered by the risk engine. Guard against double-fires.
        final current = ref.read(sosControllerProvider);
        if (current == SosState.idle) {
          ref.read(sosControllerProvider.notifier).trigger(fromRisk: true);
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pauseSos();
    }
    if (state == AppLifecycleState.resumed) {
      final isActive = ref.read(sosActiveProvider);
      if (isActive) _startFlashEffect();
    }
  }

  void _pauseSos() {
    _flashTimer?.cancel();
    _tryVibrateCancel();
  }

  // ── Vibration helpers ─────────────────────────────────────────────────────
  void _tryVibratePattern() {
    if (!_hasVibrator) return;
    try {
      Vibration.vibrate(pattern: [0, 500, 200, 500, 200, 500], repeat: 0);
    } catch (_) {}
  }

  void _tryVibrateCancel() {
    if (!_hasVibrator) return;
    try {
      Vibration.cancel();
    } catch (_) {}
  }

  void _tryVibrateDuration(int duration) {
    if (!_hasVibrator) return;
    try {
      Vibration.vibrate(duration: duration);
    } catch (_) {}
  }

  // ── TRIGGER SOS (UI-side orchestration) ──────────────────────────────────
  Future<void> _triggerSosFromTap() async {
    HapticFeedback.heavyImpact();
    _flashTimer?.cancel();
    _tryVibratePattern();

    // Ask for SEND_SMS once — a denial just falls back to Firestore-only
    // dispatch (the existing behaviour), no SOS is blocked.
    final service = ref.read(sosServiceProvider);
    if (!await service.requestSmsPermission()) {
      debugPrint('[SosScreen] SMS permission denied — Firestore-only mode.');
    }

    // Reset log + counter for a fresh dispatch run.
    setState(_dispatchLog.clear);
    ref.read(sosDispatchedCountProvider.notifier).reset();
    _listenDispatchStream();

    // Fire-and-forget — the provider handles state transitions. We just
    // react to them via `ref.listen` in `build()`.
    unawaited(
      ref.read(sosControllerProvider.notifier).trigger(fromRisk: false),
    );
  }

  /// Subscribe to per-contact dispatch events so the log + counter stay
  /// in sync with what the service is doing.
  void _listenDispatchStream() {
    _dispatchSub?.cancel();
    _dispatchSub = ref.read(sosServiceProvider).dispatchStream.listen((e) {
      if (!mounted) return;
      setState(() => _dispatchLog.add(e));
      // Count anything that reached a terminal state (sent / failed /
      // skipped) toward the "X / Y contacts notified" denominator.
      if (e.status != DispatchStatus.sending) {
        ref.read(sosDispatchedCountProvider.notifier).increment();
      }
    });
  }

  // ── CANCEL (hold 2s) ─────────────────────────────────────────────────────
  void _onHoldStart() {
    setState(() => _holdReleased = false);
    _tryVibrateDuration(50);
  }

  void _onHoldEnd() {
    if (!_holdReleased) {
      _tryVibrateCancel();
      _flashTimer?.cancel();
      _risk.cancelSos();
      unawaited(ref.read(sosControllerProvider.notifier).cancel());
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _onHoldConfirm() {
    setState(() => _holdReleased = true);
    HapticFeedback.heavyImpact();
    _onHoldEnd();
  }

  // ── "I Am Safe" ──────────────────────────────────────────────────────────
  Future<void> _iAmSafe() async {
    HapticFeedback.heavyImpact();
    _tryVibrateCancel();
    _flashTimer?.cancel();

    await ref.read(sosControllerProvider.notifier).cancel();
    await _risk.sendSafetyConfirmation();

    if (mounted) Navigator.of(context).pop();
  }

  // ── Side effects when state changes ──────────────────────────────────────
  void _onSosActiveChanged(bool isActive) {
    if (isActive) {
      _startFlashEffect();
    } else {
      _flashTimer?.cancel();
    }
  }

  void _startFlashEffect() {
    _flashTimer?.cancel();
    _flashTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted || !ref.read(sosActiveProvider)) {
        _flashTimer?.cancel();
        return;
      }
      HapticFeedback.lightImpact();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flashTimer?.cancel();
    _riskSub?.cancel();
    _dispatchSub?.cancel();
    _pulseCtrl.dispose();
    _flashCtrl.dispose();
    _scaleCtrl.dispose();
    _tryVibrateCancel();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    // React to provider state changes (side effects, not build output).
    ref.listen<SosState>(sosControllerProvider, (prev, next) {
      final wasActive = prev == SosState.active;
      final isActive = next == SosState.active;
      if (wasActive != isActive) _onSosActiveChanged(isActive);
    });

    final state = ref.watch(sosControllerProvider);
    final isActive = state == SosState.active;
    final isBusy =
        state == SosState.triggering || state == SosState.cancelling;

    return Scaffold(
      // Flashing red background when SOS is active
      body: AnimatedBuilder(
        animation: _flashCtrl,
        builder: (_, child) => Container(
          color: isActive
              ? AppColors.sos.withValues(alpha: 0.08 * _flashOpacity.value)
              : Colors.transparent,
          child: child,
        ),
        child: _buildBody(isActive: isActive, isBusy: isBusy),
      ),
    );
  }

  Widget _buildBody({required bool isActive, required bool isBusy}) {
    return SafeArea(
      child: Stack(
        children: [
          Column(
            children: [
              _buildTopBar(isActive: isActive),
              Expanded(child: _buildMainContent(isActive: isActive, isBusy: isBusy)),
              _buildBottomActions(),
            ],
          ),

          // Pulsing ring behind the button (only when idle).
          // IgnorePointer so the decorative 280×280 hit-area doesn't sit
          // on top of the SOS button inside the Stack and swallow its taps.
          if (!isActive)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (_, _) => Transform.scale(
                      scale: _pulseScale.value,
                      child: Container(
                        width: 280,
                        height: 280,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.sos.withValues(alpha: 0.06),
                        ),
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

  Widget _buildTopBar({required bool isActive}) {
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
                    color: Colors.black.withValues(alpha: 0.06),
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
          if (isActive)
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.sos.withValues(alpha: 0.12),
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
            ),
          const Spacer(),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildMainContent({required bool isActive, required bool isBusy}) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStatusBadge(isActive: isActive),
            const SizedBox(height: 32),
            _buildSosButton(isActive: isActive, isBusy: isBusy),
            if (isBusy || isActive) ...[
              const SizedBox(height: 20),
              _buildDispatchCounter(isActive: isActive, isBusy: isBusy),
              if (_dispatchLog.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildDispatchLog(),
              ],
            ],
            if (isBusy) ...[
              const SizedBox(height: 24),
              const Column(
                children: [
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      color: AppColors.sos,
                      strokeWidth: 3,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Sending SOS to contacts…',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.sos,
                    ),
                  ),
                ],
              ),
            ],
            if (!isBusy && !isActive) ...[
              const SizedBox(height: 28),
              _buildInfoCard(),
            ],
          ],
        ),
      ),
    );
  }

  // ── Live dispatch counter ("X / Y contacts notified") ────────────────────
  Widget _buildDispatchCounter({
    required bool isActive,
    required bool isBusy,
  }) {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final contactsAsync = ref.watch(userContactsProvider(myUid));
    final total = contactsAsync.maybeWhen(
      data: (list) => list.length,
      orElse: () => 0,
    );
    final sent =
        _dispatchLog.where((e) => e.status == DispatchStatus.sent).length;
    final dispatched =
        ref.watch(sosDispatchedCountProvider);
    final allDone = !isBusy && dispatched >= total && total > 0;
    final color = allDone
        ? AppColors.success
        : (isBusy ? AppColors.sos : AppColors.primary);
    final label = allDone
        ? '$sent / $total contacts notified'
        : '$dispatched / $total contacts notified';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulsingDot(color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Live per-contact dispatch log ────────────────────────────────────────
  Widget _buildDispatchLog() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 240),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        physics: const BouncingScrollPhysics(),
        itemCount: _dispatchLog.length,
        separatorBuilder: (_, _) => const Divider(
          height: 12,
          thickness: 0.5,
          color: Color(0x11000000),
        ),
        itemBuilder: (_, i) => _dispatchRow(_dispatchLog[i]),
      ),
    );
  }

  Widget _dispatchRow(DispatchEvent e) {
    final (icon, color, label) = switch (e.status) {
      DispatchStatus.sending => (
          Icons.hourglass_top_rounded,
          Colors.grey.shade500,
          'sending…',
        ),
      DispatchStatus.sent => (
          Icons.check_circle_rounded,
          AppColors.success,
          'SMS sent',
        ),
      DispatchStatus.failed => (
          Icons.error_rounded,
          AppColors.sos,
          e.error ?? 'failed',
        ),
      DispatchStatus.skipped => (
          Icons.block_rounded,
          Colors.grey.shade500,
          e.error ?? 'skipped',
        ),
    };
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            e.contactName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A2E),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge({required bool isActive}) {
    final color = isActive ? AppColors.sos : AppColors.primary;
    final label = isActive ? 'SOS ACTIVATED' : 'READY TO SEND';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: color.withValues(alpha: 0.30)),
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

  Widget _buildSosButton({required bool isActive, required bool isBusy}) {
    return GestureDetector(
      onTap: (isActive || isBusy) ? null : _triggerSosFromTap,
      child: AnimatedBuilder(
        animation: _pulseCtrl,
        builder: (_, child) => Transform.scale(
          scale: isActive ? 1.0 : _pulseScale.value,
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
                color: AppColors.sos.withValues(alpha: 0.5),
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
                isActive ? Icons.warning_rounded : Icons.sos_rounded,
                color: Colors.white,
                size: 72,
              ),
              const SizedBox(height: 8),
              Text(
                isActive ? 'SOS ACTIVE' : 'TRIGGER SOS',
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

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
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
            'Push notifications sent to trusted contacts',
          ),
          const SizedBox(height: 10),
          _infoRow(
            Icons.sms_rounded,
            'SMS sent to contacts with your GPS link',
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
            color: AppColors.sos.withValues(alpha: 0.08),
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
          // Hold-to-cancel (only when active)
          Consumer(
            builder: (context, ref, _) {
              final isActive = ref.watch(sosActiveProvider);
              if (!isActive) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildHoldToCancel(),
              );
            },
          ),

          // I am Safe button
          _buildSafeButton(),

          const SizedBox(height: 12),

          // Back home
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
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
      onLongPressEnd: (_) => _onHoldEnd(),
      onLongPressMoveUpdate: (details) {
        if (details.globalPosition.distance > 100) {
          _onHoldConfirm();
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: AppColors.sos.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.sos.withValues(alpha: 0.3)),
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
              color: AppColors.success.withValues(alpha: 0.35),
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

// ═══════════════════════════════════════════════════════════════════════════
// Small pulsing dot
// ═══════════════════════════════════════════════════════════════════════════
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
      builder: (_, _) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withValues(alpha: 0.5 + _ctrl.value * 0.5),
        ),
      ),
    );
  }
}
