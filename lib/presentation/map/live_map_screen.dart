// lib/presentation/map/live_map_screen.dart
//
// Full Live Map Screen — flutter_map (OpenStreetMap)
// ─────────────────────────────────────────────────────
// Features:
//   - Real-time map with both users' locations (no Google API key needed)
//   - Dashed route line between the two locations
//   - Distance + ETA display
//   - "I am Safe" check-in button
//   - Bi-directional: streams both owner + receiver GPS from Firestore
//
// Uses OpenStreetMap tiles — completely free, no API key required.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/constants/app_colors.dart';
import '../../core/routes/app_routes.dart';
import '../../data/services/session_service.dart';

class LiveMapScreen extends StatefulWidget {
  const LiveMapScreen({super.key});

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen>
    with TickerProviderStateMixin {
  final _session = SessionService();
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  final _mapCtrl = MapController();
  StreamSubscription? _sessionSub;

  // Both users' locations
  LatLng? _ownerLoc;
  LatLng? _receiverLoc;
  String _ownerName = 'You';
  String _receiverName = 'Contact';
  bool _receiverJoined = false;
  
  String _sessionId = '';
  bool _amOwner = true;
  bool _loadingSession = true; // true until _loadSession finishes

  // Distance & ETA
  double _distanceKm = 0.0;
  int _etaMinutes = 0;

  // Animations
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

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

    final active = _session.activeSession;

    if (active != null) {
      _sessionId = active.sessionId;
      _ownerName = active.ownerName;
      _ownerLoc = LatLng(active.ownerLat, active.ownerLng);
      final myUid = _auth.currentUser?.uid;
      _amOwner = myUid == null || myUid == active.ownerUid;
    }

    if (_sessionId.isEmpty) {
      try {
        final uid = _auth.currentUser?.uid;
        if (uid == null || !mounted) return;

        final ownerSnap = await _db.collection('sessions')
            .where('ownerUid', isEqualTo: uid)
            .where('isActive', isEqualTo: true)
            .limit(1)
            .get();

        if (!mounted) return;

        if (ownerSnap.docs.isNotEmpty) {
          final d = ownerSnap.docs.first.data();
          _sessionId = ownerSnap.docs.first.id;
          final lat = d['ownerLat'] as double?;
          final lng = d['ownerLng'] as double?;
          if (lat != null && lng != null) {
            _ownerLoc = LatLng(lat, lng);
          }
          _ownerName = d['ownerName'] as String? ?? 'You';
          if (d['receiverLat'] != null && d['receiverLng'] != null) {
            _receiverLoc = LatLng(
              d['receiverLat'] as double,
              d['receiverLng'] as double,
            );
            _receiverName = d['receiverName'] as String? ?? 'Contact';
            _receiverJoined = d['receiverJoined'] == true;
          }
        } else {
          final recvSnap = await _db.collection('sessions')
              .where('receiverUid', isEqualTo: uid)
              .where('isActive', isEqualTo: true)
              .limit(1)
              .get();

          if (!mounted) return;

          if (recvSnap.docs.isNotEmpty) {
            final d = recvSnap.docs.first.data();
            _sessionId = recvSnap.docs.first.id;
            _amOwner = false;
            final ownerLat = d['ownerLat'] as double?;
            final ownerLng = d['ownerLng'] as double?;
            if (ownerLat != null && ownerLng != null) {
              _ownerLoc = LatLng(ownerLat, ownerLng);
            }
            _ownerName = d['ownerName'] as String? ?? 'Contact';
            if (d['receiverLat'] != null && d['receiverLng'] != null) {
              _receiverLoc = LatLng(
                d['receiverLat'] as double,
                d['receiverLng'] as double,
              );
            }
            _receiverName = _auth.currentUser?.displayName ?? 'You';
            _receiverJoined = d['receiverJoined'] == true;
          }
        }
      } catch (e) {
        debugPrint('loadSession error: $e');
      }
    }

    if (_sessionId.isNotEmpty && mounted) {
      try {
        final snap = await _db.collection('sessions').doc(_sessionId).get();
        if (!mounted || !snap.exists) return;
        final d = snap.data()!;
        setState(() {
          final lat = d['ownerLat'] as double?;
          final lng = d['ownerLng'] as double?;
          if (lat != null && lng != null) {
            _ownerLoc = LatLng(lat, lng);
          }
          _ownerName = d['ownerName'] as String? ?? _ownerName;
          if (d['receiverLat'] != null && d['receiverLng'] != null) {
            _receiverLoc = LatLng(
              d['receiverLat'] as double,
              d['receiverLng'] as double,
            );
            _receiverName = d['receiverName'] as String? ?? 'Contact';
            _receiverJoined = d['receiverJoined'] == true;
          }
        });
      } catch (e) {
        debugPrint('loadSession Firestore error: $e');
      }
      if (mounted && _sessionId.isNotEmpty) {
        _watchSession(_sessionId);
      }
    }

    if (mounted) {
      setState(() => _loadingSession = false);
    }
  }

  void _watchSession(String sessionId) {
    _sessionSub?.cancel();
    _sessionSub = _session.watchSession(sessionId).listen((s) {
      if (!mounted || s == null) return;
      final myUid = _auth.currentUser?.uid;
      setState(() {
        _amOwner = myUid == null || myUid == s.ownerUid;
        _ownerLoc = LatLng(s.ownerLat, s.ownerLng);
        if (s.receiverLat != null && s.receiverLng != null) {
          _receiverLoc = LatLng(s.receiverLat!, s.receiverLng!);
        }
        _receiverName = s.receiverName ?? 'Contact';
        _receiverJoined = s.receiverJoined;
      });
      _updateDistance();
      _updateMapBounds();
    });
  }

  void _updateDistance() {
    if (_ownerLoc == null || _receiverLoc == null) return;
    const Distance dist = Distance();
    final meters = dist.as(LengthUnit.Kilometer, _ownerLoc!, _receiverLoc!);
    _distanceKm = meters;
    _etaMinutes = ((meters / 5.0) * 60).round();
  }

  void _updateMapBounds() {
    if (_ownerLoc != null && _receiverLoc != null) {
      final bounds = LatLngBounds(
        LatLng(
          _ownerLoc!.latitude < _receiverLoc!.latitude
              ? _ownerLoc!.latitude : _receiverLoc!.latitude,
          _ownerLoc!.longitude < _receiverLoc!.longitude
              ? _ownerLoc!.longitude : _receiverLoc!.longitude,
        ),
        LatLng(
          _ownerLoc!.latitude > _receiverLoc!.latitude
              ? _ownerLoc!.latitude : _receiverLoc!.latitude,
          _ownerLoc!.longitude > _receiverLoc!.longitude
              ? _ownerLoc!.longitude : _receiverLoc!.longitude,
        ),
      );
      _mapCtrl.move(bounds.center, 14);
    } else if (_ownerLoc != null) {
      _mapCtrl.move(_ownerLoc!, 16);
    }
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

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
            child: Text(
              isYou ? 'YOU' : label,
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
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      appBar: _buildAppBar(),
      body: _loadingSession
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(
                    color: AppColors.primary,
                    strokeWidth: 3,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Loading session…',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            )
          : (_ownerLoc == null ? _buildNoSession() : _buildMap()),
      floatingActionButton: _buildFab(),
    );
  }

  AppBar _buildAppBar() => AppBar(
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
        title: const Text(
          'Live Tracking',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A2E),
          ),
        ),
        centerTitle: true,
        actions: [
          Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
      );

  Widget _buildNoSession() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.map_rounded,
              color: AppColors.primary.withValues(alpha: 0.4),
              size: 64,
            ),
            const SizedBox(height: 16),
            const Text(
              'No active session',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start a session to track live location',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Go Home',
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

  Widget _buildMap() => Stack(
        children: [
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
          ),

          // Bottom info card
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Status row
                  Row(
                    children: [
                      Expanded(
                        child: _infoTile(
                          Icons.person_rounded,
                          _amOwner ? _ownerName : _receiverName,
                          _amOwner ? 'You' : 'You',
                          AppColors.primary,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Column(
                          children: [
                            Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.grey.shade400,
                              size: 20,
                            ),
                            if (_distanceKm > 0)
                              Text(
                                '${_distanceKm.toStringAsFixed(1)} km',
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _infoTile(
                          Icons.people_rounded,
                          _amOwner ? _receiverName : _ownerName,
                          _receiverJoined ? 'Active' : 'Waiting',
                          _receiverJoined ? AppColors.success : Colors.grey,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // ETA + distance row
                  if (_receiverJoined && _distanceKm > 0) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.directions_walk_rounded,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$_etaMinutes min away',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          width: 1,
                          height: 14,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${_distanceKm.toStringAsFixed(1)} km',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Check-in button
                  GestureDetector(
                    onTap: _onCheckIn,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.primary,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Check-in',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 15,
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
            ),
          ),
        ],
      );

  Widget _infoTile(IconData icon, String name, String sub, Color color) {
    return Column(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(height: 6),
        Text(
          name,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A2E),
          ),
        ),
        Text(
          sub,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildFab() => GestureDetector(
        onTap: () {
          HapticFeedback.heavyImpact();
          Navigator.of(context).pushNamed(AppRoutes.sos);
        },
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.sos,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.sos.withValues(alpha: 0.45),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi_rounded, color: Colors.white, size: 18),
              Text(
                'SOS',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );

  Future<void> _onCheckIn() async {
    HapticFeedback.mediumImpact();
    final uid = _auth.currentUser?.uid;
    if (uid != null && _sessionId.isNotEmpty) {
      await _db.collection('sessions').doc(_sessionId).update({
        'lastCheckIn': FieldValue.serverTimestamp(),
      });
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Check-in sent!',
          style: TextStyle(fontFamily: 'Poppins'),
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
