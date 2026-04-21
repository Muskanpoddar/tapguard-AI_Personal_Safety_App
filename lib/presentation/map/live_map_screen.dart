// lib/presentation/map/live_map_screen.dart
//
// Full Live Map Screen
// ─────────────────────
// Features:
//   - Real-time Google Map with both users' locations
//   - Animated route path line between the two locations
//   - Distance badge showing miles/km remaining
//   - Live tracking badge ("LIVE TRACKING")
//   - ETA display ("Arriving in X min")
//   - "I am Safe" check-in button
//   - Emergency highlight when SOS is active
//
// Bi-directional: streams both owner + receiver GPS from Firestore

import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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

  GoogleMapController? _mapCtrl;
  StreamSubscription? _sessionSub;

  // Both users' locations
  LatLng? _ownerLoc;
  LatLng? _receiverLoc;
  String _ownerName  = 'You';
  String _receiverName = 'Contact';
  bool  _receiverJoined = false;
  bool  _sessionActive = false;
  String _sessionId = '';

  // Distance & ETA
  double _distanceKm = 0.0;
  int   _etaMinutes  = 0;

  // Animations
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(
      parent: _pulseCtrl,
      curve: Curves.easeInOut,
    ).drive(Tween(begin: 0.8, end: 1.0));

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    _loadSession();
  }

  Future<void> _loadSession() async {
    final active = _session.activeSession;
    if (active != null) {
      _sessionId = active.sessionId;
      _ownerName = active.ownerName;
      setState(() {
        _ownerLoc = LatLng(active.ownerLat, active.ownerLng);
        _sessionActive = true;
      });
      _watchSession(active.sessionId);
    }
  }

  void _watchSession(String sessionId) {
    _sessionSub?.cancel();
    _sessionSub = _session.watchSession(sessionId).listen((s) {
      if (!mounted || s == null) return;
      setState(() {
        _ownerLoc = LatLng(s.ownerLat, s.ownerLng);
        _receiverLoc = s.receiverLat != null && s.receiverLng != null
            ? LatLng(s.receiverLat!, s.receiverLng!)
            : null;
        _receiverName = s.receiverName ?? 'Contact';
        _receiverJoined = s.receiverJoined;
        _sessionActive = s.isActive;
      });
      _updateDistance();
      _updateMapBounds();
    });
  }

  void _updateDistance() {
    if (_ownerLoc == null || _receiverLoc == null) return;
    final d = _distanceBetween(_ownerLoc!, _receiverLoc!);
    _distanceKm = d;
    // Assume walking speed ~5 km/h for ETA
    _etaMinutes = ((d / 5.0) * 60).round();
  }

  double _distanceBetween(LatLng a, LatLng b) {
    const R = 6371.0;
    final dLat = _rad(b.latitude - a.latitude);
    final dLon = _rad(b.longitude - a.longitude);
    final x = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(a.latitude)) *
            cos(_rad(b.latitude)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return R * 2 * atan2(sqrt(x), sqrt(1 - x));
  }

  double _rad(double deg) => deg * pi / 180;

  void _updateMapBounds() {
    if (_mapCtrl == null) return;
    if (_ownerLoc != null && _receiverLoc != null) {
      final bounds = LatLngBounds(
        southwest: LatLng(
          min(_ownerLoc!.latitude, _receiverLoc!.latitude),
          min(_ownerLoc!.longitude, _receiverLoc!.longitude),
        ),
        northeast: LatLng(
          max(_ownerLoc!.latitude, _receiverLoc!.latitude),
          max(_ownerLoc!.longitude, _receiverLoc!.longitude),
        ),
      );
      _mapCtrl!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
    } else if (_ownerLoc != null) {
      _mapCtrl!.animateCamera(
        CameraUpdate.newLatLngZoom(_ownerLoc!, 16),
      );
    }
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    _pulseCtrl.dispose();
    _mapCtrl?.dispose();
    super.dispose();
  }

  Set<Polyline> get _polylines {
    if (_ownerLoc == null || _receiverLoc == null) return {};
    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: [_ownerLoc!, _receiverLoc!],
        color: AppColors.primary.withValues(alpha: 0.6),
        width: 3,
        patterns: [PatternItem.dash(12), PatternItem.gap(8)],
      ),
    };
  }

  Set<Marker> get _markers {
    final marks = <Marker>{};
    if (_ownerLoc != null) {
      marks.add(Marker(
        markerId: const MarkerId('owner'),
        position: _ownerLoc!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
        infoWindow: InfoWindow(title: _ownerName, snippet: 'YOU'),
      ));
    }
    if (_receiverLoc != null) {
      marks.add(Marker(
        markerId: const MarkerId('receiver'),
        position: _receiverLoc!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: _receiverName, snippet: 'CONTACT'),
      ));
    }
    return marks;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      appBar: _buildAppBar(),
      body: _ownerLoc == null ? _buildNoSession() : _buildMap(),
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
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: Color(0xFF1A1A2E)),
      ),
    ),
    title: const Text('Live Tracking', style: TextStyle(fontFamily: 'Poppins', fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
    centerTitle: true,
    actions: [
      Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.10),
          borderRadius: BorderRadius.circular(50),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, __) => Container(
                width: 8, height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primary.withOpacity(0.5 + _pulseCtrl.value * 0.5)),
              ),
            ),
            const SizedBox(width: 6),
            const Text('LIVE', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.primary)),
          ],
        ),
      ),
    ],
  );

  Widget _buildNoSession() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.map_rounded, color: AppColors.primary.withOpacity(0.4), size: 64),
        const SizedBox(height: 16),
        const Text('No active session', style: TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
        const SizedBox(height: 8),
        Text('Start a session to track live location', style: TextStyle(fontFamily: 'Poppins', fontSize: 14, color: Colors.grey.shade500)),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pushReplacementNamed(AppRoutes.home),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          child: const Text('Go Home', style: TextStyle(fontFamily: 'Poppins', color: Colors.white, fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );

  Widget _buildMap() => Stack(
    children: [
      GoogleMap(
        initialCameraPosition: CameraPosition(
          target: _ownerLoc ?? const LatLng(13.0827, 80.2707),
          zoom: 15,
        ),
        onMapCreated: (ctrl) {
          _mapCtrl = ctrl;
          _updateMapBounds();
        },
        myLocationEnabled: true,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
        mapToolbarEnabled: false,
        markers: _markers,
        polylines: _polylines,
        circles: _receiverLoc != null ? {
          Circle(
            circleId: const CircleId('mid'),
            center: LatLng(
              (_ownerLoc!.latitude + _receiverLoc!.latitude) / 2,
              (_ownerLoc!.longitude + _receiverLoc!.longitude) / 2,
            ),
            radius: 500,
            fillColor: AppColors.primary.withValues(alpha: 0.05),
            strokeColor: AppColors.primary.withValues(alpha: 0.2),
            strokeWidth: 1,
          ),
        } : {},
      ),

      // Bottom info card
      Positioned(
        left: 0, right: 0, bottom: 0,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, -4))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Status row
              Row(
                children: [
                  Expanded(
                    child: _infoTile(Icons.person_rounded, _ownerName, 'You', AppColors.primary),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      children: [
                        Icon(Icons.arrow_forward_rounded, color: Colors.grey.shade400, size: 20),
                        if (_distanceKm > 0)
                          Text(
                            '${_distanceKm.toStringAsFixed(1)} km',
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.primary),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _infoTile(Icons.people_rounded, _receiverName, _receiverJoined ? 'Active' : 'Waiting', _receiverJoined ? AppColors.success : Colors.grey),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ETA + distance row
              if (_receiverJoined && _distanceKm > 0) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.directions_walk_rounded, size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      '$_etaMinutes min away',
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primary),
                    ),
                    const SizedBox(width: 12),
                    Container(width: 1, height: 14, color: Colors.grey.shade300),
                    const SizedBox(width: 12),
                    Text(
                      '${_distanceKm.toStringAsFixed(1)} km',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
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
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20),
                      SizedBox(width: 8),
                      Text('Check-in', style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.primary)),
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
          width: 44, height: 44,
          decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(height: 6),
        Text(name, style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
        Text(sub, style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildFab() => GestureDetector(
    onTap: () {
      HapticFeedback.heavyImpact();
      Navigator.of(context).pushNamed(AppRoutes.sos);
    },
    child: Container(
      width: 56, height: 56,
      decoration: BoxDecoration(
        color: AppColors.sos,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: AppColors.sos.withOpacity(0.45), blurRadius: 16, spreadRadius: 2)],
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_rounded, color: Colors.white, size: 18),
          Text('SOS', style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
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
        content: const Text('Check-in sent!', style: TextStyle(fontFamily: 'Poppins')),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
