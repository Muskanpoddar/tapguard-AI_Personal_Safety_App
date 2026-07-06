// lib/presentation/session/live_session_screen.dart
//
// Bidirectional live session screen — replaces the standalone
// ActiveSessionScreen + LiveMapScreen for the QR-pairing flow.
//
// Layout:
//   ┌─────────────────────────────────────┐
//   │  Map (flutter_map, OpenStreetMap)   │  ← shows BOTH parties
//   │   • owner pin (you)                 │     live via Firestore
//   │   • receiver pin (other)            │     snapshots()
//   │   • dashed line between them        │
//   └─────────────────────────────────────┘
//   ┌─────────────────────────────────────┐
//   │  Check-in panel                     │  ← 2-minute countdown
//   │   • "Are you safe?"                 │     vibration on start
//   │   • circular timer (mm:ss)          │     vibration on I'm Safe
//   │   • "I'm Safe" button (primary)     │     auto-SOS on expiry
//   │   • "End Session" button (secondary)│
//   └─────────────────────────────────────┘
//
// Auto-escalation: when the 2-minute countdown hits 00:00 without
// the user tapping "I'm Safe", the screen triggers
// SosService.triggerSos() — which fires OneSignal push notifications
// to every trusted contact AND opens the SMS composer with the
// danger message draft. The screen then enters a recovery state
// showing "Auto-SOS triggered — trusted contacts notified" with
// an "I'm Safe (cancel SOS)" button.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vibration/vibration.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/session_model.dart';
import '../../data/services/notification_service.dart';
import '../../data/services/session_service.dart';
import '../../data/services/sos_service.dart';

class LiveSessionScreen extends StatefulWidget {
  const LiveSessionScreen({super.key});

  @override
  State<LiveSessionScreen> createState() => _LiveSessionScreenState();
}

class _LiveSessionScreenState extends State<LiveSessionScreen>
    with TickerProviderStateMixin {
  final _sessionService = SessionService();
  final _sosService = SosService();
  final _notifService = NotificationService();
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  final _mapCtrl = MapController();
  StreamSubscription? _sessionSub;

  // Live session state
  SessionModel? _session;
  String _sessionId = '';
  String _ownerName = 'You';
  String _receiverName = 'Contact';
  bool _amOwner = true;
  bool _loading = true;

  // Locations
  LatLng? _ownerLoc;
  LatLng? _receiverLoc;
  double _distanceKm = 0.0;

  // Check-in state
  static const int _checkInSeconds = 2 * 60; // 2-minute fixed check-in
  int _remainingSeconds = _checkInSeconds;
  bool _sosTriggered = false;
  bool _isSafeFlash = false;
  Timer? _countdownTimer;

  // Animations
  late AnimationController _pulseCtrl;
  late AnimationController _sosPulseCtrl;
  late Animation<double> _sosScale;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _sosPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _sosScale = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _sosPulseCtrl, curve: Curves.easeInOut),
    );

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    _loadSession();
  }

  Future<void> _loadSession() async {
    if (!mounted) return;

    final active = _sessionService.activeSession;
    if (active != null) {
      _sessionId = active.sessionId;
      _ownerName = active.ownerName;
      _ownerLoc = LatLng(active.ownerLat, active.ownerLng);
      final myUid = _auth.currentUser?.uid;
      _amOwner = myUid == null || myUid == active.ownerUid;
      _session = active;
    } else {
      // No in-memory session — this phone is probably the RECEIVER of a
      // session that was created on the owner's phone. Look it up in
      // `users/{myUid}/sharedSessions` (written by the owner when they
      // tapped "Share Live Location").
      _sessionId = await _lookupSharedSessionId() ?? '';
      if (_sessionId.isNotEmpty) {
        _amOwner = false;
        try {
          final snap =
              await _db.collection('sessions').doc(_sessionId).get();
          if (snap.exists && mounted) {
            final d = snap.data()!;
            _ownerName = d['ownerName'] as String? ?? 'Contact';
            final lat = d['ownerLat'] as double?;
            final lng = d['ownerLng'] as double?;
            if (lat != null && lng != null) {
              _ownerLoc = LatLng(lat, lng);
            }
            _receiverName = _auth.currentUser?.displayName ?? 'You';
          }
        } catch (e) {
          debugPrint('sharedSession lookup error: $e');
        }
      }
    }

    if (_sessionId.isNotEmpty) {
      _watchSession(_sessionId);
      // Bi-directional fix: if I'm the receiver, start streaming MY GPS
      // to the session so the owner sees my pin moving in real time.
      if (!_amOwner) {
        _sessionService.startReceiverStream(_sessionId);
      }
      _startCheckIn();
    } else {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Returns the most recent active sessionId from this user's
  /// `sharedSessions` subcollection (written by the owner phone when
  /// they tapped "Share Live Location"). Used by the receiver phone to
  /// discover the session — its in-memory `_active` is empty because it
  /// never called `createSession`.
  Future<String?> _lookupSharedSessionId() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return null;
      final snap = await _db
          .collection('users')
          .doc(uid)
          .collection('sharedSessions')
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      return snap.docs.first.id;
    } catch (e) {
      debugPrint('_lookupSharedSessionId error: $e');
      return null;
    }
  }

  void _watchSession(String sessionId) {
    _sessionSub?.cancel();
    _sessionSub = _sessionService.watchSession(sessionId).listen((s) {
      if (!mounted || s == null) return;
      setState(() {
        _session = s;
        _ownerName = s.ownerName;
        _receiverName = s.receiverName ?? 'Contact';
        _ownerLoc = LatLng(s.ownerLat, s.ownerLng);
        if (s.receiverLat != null && s.receiverLng != null) {
          _receiverLoc = LatLng(s.receiverLat!, s.receiverLng!);
        }
        _loading = false;
      });
      _updateDistance();
      _updateMapBounds();
      if (!s.isActive && mounted) _navigateHome();
    });
  }

  void _updateDistance() {
    if (_ownerLoc == null || _receiverLoc == null) return;
    const Distance dist = Distance();
    _distanceKm = dist.as(LengthUnit.Kilometer, _ownerLoc!, _receiverLoc!);
  }

  void _updateMapBounds() {
    if (_ownerLoc != null && _receiverLoc != null) {
      final bounds = LatLngBounds(
        LatLng(
          _ownerLoc!.latitude < _receiverLoc!.latitude
              ? _ownerLoc!.latitude
              : _receiverLoc!.latitude,
          _ownerLoc!.longitude < _receiverLoc!.longitude
              ? _ownerLoc!.longitude
              : _receiverLoc!.longitude,
        ),
        LatLng(
          _ownerLoc!.latitude > _receiverLoc!.latitude
              ? _ownerLoc!.latitude
              : _receiverLoc!.latitude,
          _ownerLoc!.longitude > _receiverLoc!.longitude
              ? _ownerLoc!.longitude
              : _receiverLoc!.longitude,
        ),
      );
      _mapCtrl.move(bounds.center, 14);
    } else if (_ownerLoc != null) {
      _mapCtrl.move(_ownerLoc!, 16);
    }
  }

  // ── Check-in lifecycle ─────────────────────────────────────────────────────

  /// Start the 2-minute countdown with a single confirmation vibration.
  void _startCheckIn() {
    setState(() {
      _remainingSeconds = _checkInSeconds;
      _sosTriggered = false;
    });
    HapticFeedback.heavyImpact();
    _buzzOnce();
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
          _onCheckInTimeout();
        }
      });
    });
  }

  Future<void> _buzzOnce() async {
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(duration: 250);
    }
  }

  /// Auto-escalation: fire SosService and heavy vibration pattern.
  Future<void> _onCheckInTimeout() async {
    if (_sosTriggered) return;
    setState(() => _sosTriggered = true);

    HapticFeedback.heavyImpact();
    HapticFeedback.heavyImpact();
    _notifService.vibrateTimerEnd();

    if (_session != null) {
      // 1. Send OneSignal push to every trusted contact
      _notifService.alertContactsTimerEnded(
        ownerUid: _session!.ownerUid,
        ownerName: _session!.ownerName,
        sessionId: _session!.sessionId,
      );
      // 2. Trigger full SOS flow (sms: composer + Firestore notifications)
      await _sosService.triggerSos(fromRisk: false);
    }
  }

  // ── I'm Safe (resets check-in) ─────────────────────────────────────────────

  Future<void> _iAmSafe() async {
    if (_sosTriggered) {
      // Cancel active SOS + notify contacts
      await _sosService.cancelSos();
      if (_session != null) {
        _notifService.notifyContactsUserSafe(
          ownerUid: _session!.ownerUid,
          ownerName: _session!.ownerName,
        );
      }
    }
    _notifService.stopVibration();

    HapticFeedback.mediumImpact();
    _buzzOnce();

    setState(() => _isSafeFlash = true);

    try {
      if (_session != null) {
        await _db.collection('sessions').doc(_session!.sessionId).update({
          'lastSafeAt': FieldValue.serverTimestamp(),
          'isSafe': true,
        });
      }
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() => _isSafeFlash = false);
    _startCheckIn();
  }

  // ── End session ───────────────────────────────────────────────────────────

  Future<void> _endSession() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'End Session?',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Live location sharing will stop for both of you.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(fontFamily: 'Poppins', color: AppColors.primary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.sos,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'End',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;

    HapticFeedback.mediumImpact();
    _countdownTimer?.cancel();
    _notifService.stopVibration();

    try {
      if (_session != null) {
        _notifService.notifySessionEnded(
          ownerUid: _session!.ownerUid,
          ownerName: _session!.ownerName,
        );
      }
      await _sessionService.endSession();
      if (_sosTriggered) {
        await _sosService.cancelSos();
      }
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
    _pulseCtrl.dispose();
    _sosPulseCtrl.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════════════════════

  String get _timerDisplay {
    final m = _remainingSeconds ~/ 60;
    final s = _remainingSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  double get _timerProgress => _remainingSeconds / _checkInSeconds;

  List<Polyline> get _polylines {
    if (_ownerLoc == null || _receiverLoc == null) return [];
    return [
      Polyline(
        points: [_ownerLoc!, _receiverLoc!],
        color: AppColors.primary.withValues(alpha: 0.6),
        strokeWidth: 3,
        borderStrokeWidth: 0,
      ),
    ];
  }

  List<Marker> get _markers {
    final marks = <Marker>[];
    if (_amOwner) {
      if (_ownerLoc != null) {
        marks.add(Marker(
          point: _ownerLoc!,
          width: 50,
          height: 50,
          child: _buildMarkerPin(
            icon: Icons.person_rounded,
            color: AppColors.primary,
            label: _ownerName,
            isYou: true,
          ),
        ));
      }
      if (_receiverLoc != null) {
        marks.add(Marker(
          point: _receiverLoc!,
          width: 50,
          height: 50,
          child: _buildMarkerPin(
            icon: Icons.person_rounded,
            color: AppColors.success,
            label: _receiverName,
            isYou: false,
          ),
        ));
      }
    } else {
      if (_ownerLoc != null) {
        marks.add(Marker(
          point: _ownerLoc!,
          width: 50,
          height: 50,
          child: _buildMarkerPin(
            icon: Icons.person_rounded,
            color: AppColors.success,
            label: _ownerName,
            isYou: false,
          ),
        ));
      }
      if (_receiverLoc != null) {
        marks.add(Marker(
          point: _receiverLoc!,
          width: 50,
          height: 50,
          child: _buildMarkerPin(
            icon: Icons.person_rounded,
            color: AppColors.primary,
            label: _receiverName,
            isYou: true,
          ),
        ));
      }
    }
    return marks;
  }

  Widget _buildMarkerPin({
    required IconData icon,
    required Color color,
    required String label,
    required bool isYou,
  }) {
    return SizedBox(
      width: 50,
      height: 56,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 3,
                ),
              ],
            ),
            constraints: const BoxConstraints(maxWidth: 90),
            child: Text(
              isYou ? 'YOU' : label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final otherName = _amOwner ? _receiverName : _ownerName;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      body: SafeArea(
        child: _loading
            ? _buildLoading()
            : Column(
                children: [
                  Expanded(flex: 55, child: _buildMapSection(otherName)),
                  Expanded(flex: 45, child: _buildCheckInPanel(otherName)),
                ],
              ),
      ),
    );
  }

  Widget _buildLoading() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 3,
            ),
            const SizedBox(height: 16),
            Text(
              'Connecting to session…',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      );

  Widget _buildMapSection(String otherName) {
    return Stack(
      children: [
        if (_ownerLoc != null)
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: (_amOwner ? _ownerLoc : _receiverLoc) ?? _ownerLoc!,
              initialZoom: 15,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.tapguard.app',
              ),
              PolylineLayer(polylines: _polylines),
              MarkerLayer(markers: _markers),
            ],
          )
        else
          Container(
            color: Colors.grey.shade200,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.gps_fixed_rounded,
                      color: Colors.grey.shade400, size: 48),
                  const SizedBox(height: 8),
                  Text(
                    'Waiting for GPS…',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Top bar (back + LIVE pill)
        Positioned(
          top: 12,
          left: 12,
          right: 12,
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
                    Icons.arrow_back_ios_new_rounded,
                    size: 16,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (_, _) => Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary.withValues(
                              alpha: 0.5 + _pulseCtrl.value * 0.5),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'LIVE',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Distance chip (bottom-left of map)
        if (_distanceKm > 0)
          Positioned(
            left: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(50),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.straighten_rounded,
                      size: 14, color: Colors.grey.shade700),
                  const SizedBox(width: 4),
                  Text(
                    '${_distanceKm.toStringAsFixed(1)} km apart',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCheckInPanel(String otherName) {
    final timerColor = _sosTriggered
        ? AppColors.sos
        : (_remainingSeconds <= 30 ? AppColors.sos : AppColors.primary);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              if (_sosTriggered)
                _buildSosBanner(otherName)
              else
                _buildCheckInHeader(otherName),

              const SizedBox(height: 20),

              // Circular timer
              SizedBox(
                width: 180,
                height: 180,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_sosTriggered)
                      ScaleTransition(
                        scale: _sosScale,
                        child: Container(
                          width: 180,
                          height: 180,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.sos.withValues(alpha: 0.10),
                          ),
                        ),
                      ),
                    SizedBox(
                      width: 170,
                      height: 170,
                      child: CircularProgressIndicator(
                        value: _sosTriggered ? 1.0 : _timerProgress,
                        strokeWidth: 10,
                        backgroundColor: Colors.grey.shade200,
                        color: timerColor,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isSafeFlash)
                          const Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.success,
                            size: 48,
                          )
                        else if (_sosTriggered)
                          Icon(
                            Icons.warning_amber_rounded,
                            color: AppColors.sos,
                            size: 44,
                          )
                        else
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _timerDisplay,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 44,
                                fontWeight: FontWeight.w800,
                                color: timerColor,
                              ),
                            ),
                          ),
                        if (!_isSafeFlash && !_sosTriggered)
                          Text(
                            'until auto-SOS',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade500,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Primary action
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _iAmSafe,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _sosTriggered ? AppColors.success : AppColors.primary,
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
                        _sosTriggered
                            ? Icons.shield_rounded
                            : Icons.check_circle_rounded,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _sosTriggered ? "I'm Safe (cancel SOS)" : "I'm Safe",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Secondary action
              SizedBox(
                width: double.infinity,
                height: 48,
                child: TextButton(
                  onPressed: _endSession,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey.shade700,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  child: const Text(
                    'End Session',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckInHeader(String otherName) {
    return Column(
      children: [
        Text(
          'Are you safe?',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Colors.grey.shade900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Sharing live location with $otherName.\n'
          'Tap "I\'m Safe" to reset the check-in.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            height: 1.4,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildSosBanner(String otherName) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.sos.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.sos.withValues(alpha: 0.30),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Text(
            '⚠️ Auto-SOS Triggered',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.sos,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'No check-in received — trusted contacts have been notified and an SMS alert has been opened.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              height: 1.3,
              color: Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }
}