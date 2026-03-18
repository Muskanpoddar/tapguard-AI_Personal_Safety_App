// lib/presentation/nfc_pairing/nfc_pairing_screen.dart
//
// REAL FLOW:
// 1. Tap "Start NFC Location Share"
// 2. Firebase session created → gets unique shareUrl
// 3. NFC scans for nearby device (4cm)
// 4. On success → saves contact to Firestore using ContactModel
// 5. Navigates to Active Session screen

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/routes/app_routes.dart';
import '../../../data/models/contact_model.dart';
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
  final _nfc = NfcService();
  final _session = SessionService();
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  NfcWriteStatus _nfcStatus = NfcWriteStatus.idle;
  String _statusMessage = '';
  String _errorMessage = '';
  bool _creatingSession = false;
  bool _savingContact = false;
  bool _nfcAvailable = false;
  SessionModel? _session0;

  StreamSubscription<NfcWriteStatus>? _statusSub;
  StreamSubscription<String>? _errorSub;

  // Animations
  late AnimationController _pulseCtrl;
  late AnimationController _ringCtrl;
  late Animation<double> _pulseScale;
  late Animation<double> _ringScale;
  late Animation<double> _ringOpacity;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _checkNfc();
    _listenNfcStatus();
  }

  void _initAnimations() {
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _pulseScale = CurvedAnimation(
      parent: _pulseCtrl,
      curve: Curves.easeInOut,
    ).drive(Tween(begin: 0.92, end: 1.08));
    _ringScale = CurvedAnimation(
      parent: _ringCtrl,
      curve: Curves.easeOut,
    ).drive(Tween(begin: 0.8, end: 1.3));
    _ringOpacity = CurvedAnimation(
      parent: _ringCtrl,
      curve: Curves.easeOut,
    ).drive(Tween(begin: 0.6, end: 0.0));
  }

  Future<void> _checkNfc() async {
    final ok = await _nfc.isAvailable();
    if (!mounted) return;
    setState(() {
      _nfcAvailable = ok;
      if (!ok) {
        _statusMessage = 'NFC is off or not supported on this device';
        _errorMessage = 'Go to Settings → Connections → NFC and enable it.';
      }
    });
  }

  void _listenNfcStatus() {
    _statusSub = _nfc.statusStream.listen((status) {
      if (!mounted) return;
      setState(() {
        _nfcStatus = status;
        switch (status) {
          case NfcWriteStatus.scanning:
            _statusMessage = 'Hold phones back-to-back\nwithin 4cm';
            _errorMessage = '';
            break;
          case NfcWriteStatus.writing:
            _statusMessage = 'Device detected!\nTransferring link…';
            _errorMessage = '';
            HapticFeedback.mediumImpact();
            break;
          case NfcWriteStatus.success:
            _statusMessage = 'Done! Saving contact…';
            _errorMessage = '';
            HapticFeedback.heavyImpact();
            // Save contact then navigate
            _onNfcSuccess();
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

    _errorSub = _nfc.errorStream.listen((err) {
      if (!mounted) return;
      setState(() => _errorMessage = err);
    });
  }

  // ── Main action: create session + start NFC ───────────────────────────────
  Future<void> _startNfcSharing() async {
    if (!_nfcAvailable) {
      _showNfcDialog();
      return;
    }

    setState(() {
      _creatingSession = true;
      _statusMessage = 'Creating secure session…';
      _errorMessage = '';
    });

    try {
      // Get user name from Firestore profile
      final uid = _auth.currentUser?.uid ?? '';
      String name = 'User';
      String phone = '';

      if (uid.isNotEmpty) {
        final doc = await _db.collection('users').doc(uid).get();
        if (doc.exists) {
          name = doc.data()?['name'] ?? 'User';
          phone = doc.data()?['phone'] ?? '';
        }
      }

      // Create Firebase session → get shareUrl
      final session = await _session.createSession(
        ownerName: name,
        ownerPhone: phone,
      );

      setState(() {
        _session0 = session;
        _creatingSession = false;
        _statusMessage = 'Ready! Tap your phone\nagainst another device.';
      });

      // Start NFC — write shareUrl to nearby device
      await _nfc.startWriting(session.shareUrl);
    } catch (e) {
      setState(() {
        _creatingSession = false;
        _nfcStatus = NfcWriteStatus.error;
        _statusMessage = 'Failed to start';
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ── Called after NFC write succeeds ──────────────────────────────────────
  // Saves receiver as a contact in Firestore using ContactModel
  Future<void> _onNfcSuccess() async {
    if (_session0 == null) {
      _navigateToSession();
      return;
    }

    setState(() {
      _savingContact = true;
      _statusMessage = 'Saving to your contacts…';
    });

    try {
      final myUid = _auth.currentUser?.uid ?? '';
      if (myUid.isEmpty) {
        _navigateToSession();
        return;
      }

      // ── What we know about the receiver ──────────────────────────────
      // At this point we only know they received the NFC link.
      // When they open the link and join the session, their UID gets
      // written to sessions/{sessionId}/receiverUid in Firestore.
      // We wait up to 10 seconds for them to open the link.
      String receiverUid =
          'nfc_contact_${DateTime.now().millisecondsSinceEpoch}';
      String receiverName = 'NFC Contact';
      String receiverPhone = '';

      // Try to fetch receiver info from session doc (if they've joined)
      try {
        final sessionDoc = await _db
            .collection('sessions')
            .doc(_session0!.sessionId)
            .get()
            .timeout(const Duration(seconds: 3));

        final data = sessionDoc.data() ?? {};
        if (data['receiverUid'] != null) {
          receiverUid = data['receiverUid'] as String;
          // Fetch their profile
          final receiverDoc = await _db
              .collection('users')
              .doc(receiverUid)
              .get()
              .timeout(const Duration(seconds: 3));
          if (receiverDoc.exists) {
            receiverName = receiverDoc.data()?['name'] ?? receiverName;
            receiverPhone = receiverDoc.data()?['phone'] ?? '';
          }
        }
      } catch (_) {
        // Non-fatal — save with placeholder, update later when they join
      }

      // ── Build ContactModel using your exact model ─────────────────────
      final contact = ContactModel(
        uid: receiverUid,
        phoneNumber: receiverPhone,
        name: receiverName,
        profileImageUrl: null,
        isEmergencyContact: false,
        priority: 0,
        addedAt: DateTime.now(),
        addedByUid: myUid,
        isVerified: false,
        allowsLocationSharing: true,
      );

      // ── Write to Firestore: users/{myUid}/contacts/{receiverUid} ──────
      await _db
          .collection('users')
          .doc(myUid)
          .collection('contacts')
          .doc(receiverUid)
          .set({
            ...contact.toMap(),
            // Extra real-time fields for home screen
            'isActive': true,
            'lastSeen': FieldValue.serverTimestamp(),
            'isPaired': true,
            'pairedAt': FieldValue.serverTimestamp(),
            'sessionId': _session0!.sessionId,
          }, SetOptions(merge: true));

      // ── Also update the session doc so receiver knows who shared ──────
      await _db.collection('sessions').doc(_session0!.sessionId).update({
        'senderUid': myUid,
        'senderName': contact.addedByUid,
      });

      setState(() {
        _savingContact = false;
        _statusMessage = 'Contact saved! Starting session…';
      });
    } catch (e) {
      // Non-fatal — still navigate even if contact save fails
      setState(() {
        _savingContact = false;
        _statusMessage = 'Session ready!';
      });
    }

    // Wait briefly so user sees the success state
    await Future.delayed(const Duration(milliseconds: 1200));
    _navigateToSession();
  }

  void _navigateToSession() {
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(AppRoutes.activeSession);
  }

  Future<void> _cancel() async {
    await _nfc.stopSession();
    setState(() {
      _nfcStatus = NfcWriteStatus.idle;
      _statusMessage = '';
      _errorMessage = '';
    });
  }

  void _showNfcDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'NFC is Off',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'TapGuard needs NFC to share your location.\n\n'
          'Go to Settings → Connections → NFC and turn it on.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(fontFamily: 'Poppins', color: Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'OK',
              style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _errorSub?.cancel();
    _nfc.stopSession();
    _pulseCtrl.dispose();
    _ringCtrl.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isActive =
        _nfcStatus == NfcWriteStatus.scanning ||
        _nfcStatus == NfcWriteStatus.writing ||
        _creatingSession;
    final isSuccess = _nfcStatus == NfcWriteStatus.success;
    final isError =
        _nfcStatus == NfcWriteStatus.error ||
        _nfcStatus == NfcWriteStatus.unavailable;

    final circleColor = isSuccess
        ? AppColors.success
        : isError
        ? AppColors.sos
        : AppColors.primary;

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
        title: const Text(
          'Connect with a Friend',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A2E),
          ),
        ),
        centerTitle: true,
      ),

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 16),

              // ── How it works card ───────────────────────────────────────
              _buildHowItWorks(),

              const SizedBox(height: 28),

              // ── NFC animation ───────────────────────────────────────────
              Expanded(
                child: Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Expanding ring
                      if (isActive)
                        AnimatedBuilder(
                          animation: _ringCtrl,
                          builder: (_, __) => Transform.scale(
                            scale: _ringScale.value,
                            child: Container(
                              width: 200,
                              height: 200,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.primary.withOpacity(
                                    _ringOpacity.value,
                                  ),
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ),

                      // Outer halo
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: circleColor.withOpacity(0.08),
                        ),
                      ),

                      // Inner pulsing circle
                      AnimatedBuilder(
                        animation: _pulseCtrl,
                        builder: (_, child) => Transform.scale(
                          scale: isActive ? _pulseScale.value : 1.0,
                          child: child,
                        ),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: circleColor,
                            boxShadow: [
                              BoxShadow(
                                color: circleColor.withOpacity(0.4),
                                blurRadius: isActive ? 30 : 14,
                                spreadRadius: isActive ? 8 : 2,
                              ),
                            ],
                          ),
                          child: _creatingSession || _savingContact
                              ? const Center(
                                  child: SizedBox(
                                    width: 36,
                                    height: 36,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 3,
                                    ),
                                  ),
                                )
                              : Icon(
                                  isSuccess
                                      ? Icons.check_rounded
                                      : isError
                                      ? Icons.error_outline_rounded
                                      : Icons.wifi_rounded,
                                  color: Colors.white,
                                  size: 60,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Status text ─────────────────────────────────────────────
              if (_statusMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isSuccess
                          ? AppColors.success
                          : isError
                          ? AppColors.sos
                          : const Color(0xFF1A1A2E),
                      height: 1.5,
                    ),
                  ),
                ),

              // ── Error message ───────────────────────────────────────────
              if (_errorMessage.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.sos.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.sos.withOpacity(0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_rounded,
                        color: AppColors.sos,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: AppColors.sos,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Share URL copy pill ─────────────────────────────────────
              if (_session0 != null && !isSuccess)
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: _session0!.shareUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text(
                          'Link copied!',
                          style: TextStyle(fontFamily: 'Poppins'),
                        ),
                        backgroundColor: AppColors.primary,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.link_rounded,
                          size: 15,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _session0!.shareUrl,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.copy_rounded,
                          size: 13,
                          color: Colors.grey.shade400,
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Action button ───────────────────────────────────────────
              if (!isSuccess) _buildButton(isActive),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ── How it works steps ────────────────────────────────────────────────────
  Widget _buildHowItWorks() {
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
          _step(
            Icons.shield_rounded,
            AppColors.primary,
            'Your live location is saved to a private secure session',
          ),
          const SizedBox(height: 10),
          _step(
            Icons.wifi_rounded,
            AppColors.primary,
            'Hold your phone within 4cm of ANY nearby phone',
          ),
          const SizedBox(height: 10),
          _step(
            Icons.notifications_active_rounded,
            AppColors.success,
            'They get a notification — no app or setup needed',
          ),
          const SizedBox(height: 10),
          _step(
            Icons.people_rounded,
            AppColors.success,
            'They\'re saved to your trusted contacts automatically',
          ),
        ],
      ),
    );
  }

  Widget _step(IconData icon, Color color, String text) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
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

  // ── Action button ─────────────────────────────────────────────────────────
  Widget _buildButton(bool isActive) {
    if (isActive) {
      return SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: _cancel,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: AppColors.sos,
            elevation: 0,
            side: BorderSide(color: AppColors.sos.withOpacity(0.4)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  color: AppColors.sos,
                  strokeWidth: 2.5,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Cancel',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _nfcAvailable ? _startNfcSharing : _showNfcDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: _nfcAvailable
                  ? AppColors.primary
                  : Colors.grey.shade400,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _nfcAvailable ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  _nfcAvailable
                      ? (_nfcStatus == NfcWriteStatus.error
                            ? 'Try Again'
                            : 'Start NFC Location Share')
                      : 'Enable NFC in Settings',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Also allow manual link sharing as fallback
        if (_session0 != null) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: () {
                // TODO: Share.share(_session0!.shareUrl)
                // Add share_plus package for this
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(
                  color: AppColors.primary.withOpacity(0.4),
                  width: 1.5,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.share_rounded, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Share Link Instead',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
