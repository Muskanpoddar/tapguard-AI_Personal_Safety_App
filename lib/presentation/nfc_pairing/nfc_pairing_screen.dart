// lib/presentation/nfc_pairing/nfc_pairing_screen.dart
//
// REAL FLOW:
// 1. User taps "Start NFC Location Share"
// 2. Firebase Firestore session is created → gets unique shareUrl
// 3. NFC starts scanning for nearby device (hold within 4cm)
// 4. When phones touch → NDEF URL written to receiver's phone
// 5. Receiver gets Android system notification (NO app needed)
// 6. Receiver taps → browser opens with live map
// 7. If receiver has TapGuard → deep link opens app directly
// 8. Sender navigates to Active Session screen

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/routes/app_routes.dart';
import '../../../data/services/nfc_service.dart';
import '../../../data/services/session_service.dart';
import '../../../data/models/session_model.dart';

class NfcPairingScreen extends StatefulWidget {
  const NfcPairingScreen({super.key});

  @override
  State<NfcPairingScreen> createState() => _NfcPairingScreenState();
}

class _NfcPairingScreenState extends State<NfcPairingScreen>
    with TickerProviderStateMixin {

  final NfcService     _nfcService     = NfcService();
  final SessionService _sessionService = SessionService();

  NfcWriteStatus _nfcStatus      = NfcWriteStatus.idle;
  String  _statusMessage         = '';
  String  _errorMessage          = '';
  bool    _isCreatingSession     = false;
  bool    _nfcAvailable          = false;
  SessionModel? _session;

  StreamSubscription<NfcWriteStatus>? _statusSub;
  StreamSubscription<String>?         _errorSub;

  // Animations
  late AnimationController _pulseController;
  late AnimationController _ringController;
  late Animation<double>   _pulseScale;
  late Animation<double>   _ringScale;
  late Animation<double>   _ringOpacity;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _checkNfc();
    _listenNfcStatus();
  }

  void _initAnimations() {
    _pulseController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);

    _ringController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat();

    _pulseScale = CurvedAnimation(
      parent: _pulseController, curve: Curves.easeInOut,
    ).drive(Tween(begin: 0.92, end: 1.08));

    _ringScale = CurvedAnimation(
      parent: _ringController, curve: Curves.easeOut,
    ).drive(Tween(begin: 0.8, end: 1.3));

    _ringOpacity = CurvedAnimation(
      parent: _ringController, curve: Curves.easeOut,
    ).drive(Tween(begin: 0.6, end: 0.0));
  }

  Future<void> _checkNfc() async {
    final available = await _nfcService.isAvailable();
    if (!mounted) return;
    setState(() {
      _nfcAvailable = available;
      if (!available) {
        _statusMessage =
            'NFC is turned off or not supported on this device';
        _errorMessage  =
            'Go to Settings → Connections → NFC and turn it on.';
      }
    });
  }

  void _listenNfcStatus() {
    _statusSub = _nfcService.statusStream.listen((status) {
      if (!mounted) return;
      setState(() {
        _nfcStatus = status;
        switch (status) {
          case NfcWriteStatus.scanning:
            _statusMessage =
                'Hold your phone against\nthe other device (within 4cm)';
            _errorMessage  = '';
            break;
          case NfcWriteStatus.writing:
            _statusMessage = 'Device detected!\nTransferring link…';
            _errorMessage  = '';
            HapticFeedback.mediumImpact();
            break;
          case NfcWriteStatus.success:
            _statusMessage =
                'Done! Your location is now\nbeing shared with them.';
            _errorMessage  = '';
            HapticFeedback.heavyImpact();
            Future.delayed(
              const Duration(seconds: 2), _goToActiveSession);
            break;
          case NfcWriteStatus.error:
          case NfcWriteStatus.unavailable:
            _statusMessage = 'Could not share via NFC';
            break;
          case NfcWriteStatus.idle:
            break;
        }
      });
    });

    _errorSub = _nfcService.errorStream.listen((error) {
      if (!mounted) return;
      setState(() => _errorMessage = error);
    });
  }

  Future<void> _startNfcSharing() async {
    if (!_nfcAvailable) { _showNfcDialog(); return; }

    setState(() {
      _isCreatingSession = true;
      _statusMessage     = 'Creating secure session…';
      _errorMessage      = '';
    });

    try {
      // Step 1 — Create Firebase session
      // TODO: Pass real user name + phone from your auth/profile state
      final session = await _sessionService.createSession(
        ownerName:  'User',
        ownerPhone: '',
      );

      setState(() {
        _session           = session;
        _isCreatingSession = false;
      });

      // Step 2 — Write URL via NFC
      await _nfcService.startWriting(session.shareUrl);

    } catch (e) {
      setState(() {
        _isCreatingSession = false;
        _nfcStatus         = NfcWriteStatus.error;
        _statusMessage     = 'Failed to start';
        _errorMessage      = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _cancel() async {
    await _nfcService.stopSession();
    setState(() {
      _nfcStatus     = NfcWriteStatus.idle;
      _statusMessage = '';
      _errorMessage  = '';
    });
  }

  void _goToActiveSession() {
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(AppRoutes.activeSession);
  }

  void _showNfcDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('NFC is Off',
          style: TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: const Text(
          'TapGuard needs NFC to share your location instantly.\n\n'
          'Go to Settings → Connections → NFC and turn it on.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
              style: TextStyle(fontFamily: 'Poppins', color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10))),
            child: const Text('OK',
              style: TextStyle(
                  fontFamily: 'Poppins', color: Colors.white))),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _errorSub?.cancel();
    _nfcService.stopSession();
    _pulseController.dispose();
    _ringController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isActive  = _nfcStatus == NfcWriteStatus.scanning ||
        _nfcStatus == NfcWriteStatus.writing || _isCreatingSession;
    final isSuccess = _nfcStatus == NfcWriteStatus.success;
    final isError   = _nfcStatus == NfcWriteStatus.error ||
        _nfcStatus == NfcWriteStatus.unavailable;

    final circleColor = isSuccess
        ? AppColors.success
        : isError ? AppColors.sos : AppColors.primary;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F3F8),
        elevation: 0,
        leading: GestureDetector(
          onTap: () async {
            await _cancel();
            if (mounted) Navigator.of(context).pop();
          },
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 16, color: Color(0xFF1A1A2E)),
          ),
        ),
        title: const Text('NFC Location Share',
          style: TextStyle(
            fontFamily: 'Poppins', fontSize: 17,
            fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E),
          )),
        centerTitle: true,
      ),

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(children: [

            const SizedBox(height: 16),

            // How it works
            _buildHowItWorksCard(),

            const SizedBox(height: 28),

            // NFC animation circle
            Expanded(
              child: Center(
                child: Stack(alignment: Alignment.center, children: [
                  // Expanding ring (when active)
                  if (isActive)
                    AnimatedBuilder(
                      animation: _ringController,
                      builder: (_, __) => Transform.scale(
                        scale: _ringScale.value,
                        child: Container(
                          width: 200, height: 200,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.primary
                                  .withOpacity(_ringOpacity.value),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Outer halo
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    width: 200, height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: circleColor.withOpacity(0.08),
                    ),
                  ),

                  // Inner pulsing circle
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (_, child) => Transform.scale(
                      scale: isActive ? _pulseScale.value : 1.0,
                      child: child,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      width: 140, height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: circleColor,
                        boxShadow: [BoxShadow(
                          color: circleColor.withOpacity(0.4),
                          blurRadius: isActive ? 30 : 14,
                          spreadRadius: isActive ? 8 : 2,
                        )],
                      ),
                      child: _isCreatingSession
                          ? const Center(child: SizedBox(
                              width: 36, height: 36,
                              child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 3)))
                          : Icon(
                              isSuccess
                                  ? Icons.check_rounded
                                  : isError
                                      ? Icons.error_outline_rounded
                                      : Icons.wifi_rounded,
                              color: Colors.white, size: 60,
                            ),
                    ),
                  ),
                ]),
              ),
            ),

            // Status text
            if (_statusMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_statusMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isSuccess
                        ? AppColors.success
                        : isError
                            ? AppColors.sos
                            : const Color(0xFF1A1A2E),
                    height: 1.5,
                  )),
              ),

            // Error
            if (_errorMessage.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.sos.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.sos.withOpacity(0.3)),
                ),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Icon(Icons.warning_rounded,
                      color: AppColors.sos, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_errorMessage,
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 12,
                        color: AppColors.sos, height: 1.5,
                      )),
                  ),
                ]),
              ),

            // Session URL copy pill
            if (_session != null && !isSuccess)
              GestureDetector(
                onTap: () {
                  Clipboard.setData(
                      ClipboardData(text: _session!.shareUrl));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: const Text('Link copied!',
                      style: TextStyle(fontFamily: 'Poppins')),
                    backgroundColor: AppColors.primary,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  ));
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.link_rounded,
                        size: 15, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(_session!.shareUrl,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 11,
                          color: AppColors.primary,
                        )),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.copy_rounded,
                        size: 13, color: Colors.grey.shade400),
                  ]),
                ),
              ),

            // Action button
            if (!isSuccess) _buildButton(isActive),

            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }

  // ── How it works card ─────────────────────────────────────────────────────
  Widget _buildHowItWorksCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(children: [
        _step(Icons.shield_rounded, AppColors.primary,
            'Your live location is saved to a private secure session'),
        const SizedBox(height: 10),
        _step(Icons.wifi_rounded, AppColors.primary,
            'Hold your phone within 4cm of ANY nearby phone'),
        const SizedBox(height: 10),
        _step(Icons.notifications_active_rounded, AppColors.success,
            'They get a notification — no app or setup needed'),
        const SizedBox(height: 10),
        _step(Icons.map_rounded, AppColors.success,
            'They tap the link → your live location opens instantly'),
      ]),
    );
  }

  Widget _step(IconData icon, Color color, String text) {
    return Row(children: [
      Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(text,
          style: const TextStyle(
            fontFamily: 'Poppins', fontSize: 12,
            color: Color(0xFF1A1A2E), height: 1.4,
          )),
      ),
    ]);
  }

  // ── Action button ─────────────────────────────────────────────────────────
  Widget _buildButton(bool isActive) {
    if (isActive) {
      return SizedBox(
        width: double.infinity, height: 56,
        child: ElevatedButton(
          onPressed: _cancel,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: AppColors.sos,
            elevation: 0,
            side: BorderSide(color: AppColors.sos.withOpacity(0.4)),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(
                  color: AppColors.sos, strokeWidth: 2.5)),
            const SizedBox(width: 12),
            const Text('Cancel',
              style: TextStyle(fontFamily: 'Poppins',
                  fontSize: 16, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
    }

    return Column(children: [
      SizedBox(
        width: double.infinity, height: 56,
        child: ElevatedButton(
          onPressed: _nfcAvailable
              ? _startNfcSharing : _showNfcDialog,
          style: ElevatedButton.styleFrom(
            backgroundColor: _nfcAvailable
                ? AppColors.primary : Colors.grey.shade400,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_nfcAvailable
                  ? Icons.wifi_rounded : Icons.wifi_off_rounded, size: 20),
              const SizedBox(width: 10),
              Text(
                _nfcAvailable
                    ? (_nfcStatus == NfcWriteStatus.error
                        ? 'Try Again'
                        : 'Start NFC Location Share')
                    : 'Enable NFC in Settings',
                style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 15,
                  fontWeight: FontWeight.w600,
                )),
            ],
          ),
        ),
      ),
      if (_session != null) ...[
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity, height: 48,
          child: OutlinedButton(
            onPressed: () {
              // TODO: Share.share(_session!.shareUrl)
              // Add: share_plus package
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(
                  color: AppColors.primary.withOpacity(0.4), width: 1.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.share_rounded,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text('Share Link Instead',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primary,
                  )),
              ],
            ),
          ),
        ),
      ],
    ]);
  }
}