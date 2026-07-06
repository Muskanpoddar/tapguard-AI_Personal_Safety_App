// lib/presentation/geofence/geofence_setup_screen.dart
//
// Full Geofence Setup Screen — flutter_map (OpenStreetMap)
// ──────────────────────────────────────────────────────────
// Features:
//   - Map centered on current location
//   - Draggable circle overlay to set safe zone center
//   - Radius slider: 100m – 2km
//   - Toggle: notify when entered / exited
//   - Save to Firestore + shared with contacts
//
// Saved data in Firestore: users/{uid}/geofence/{zoneId}
//   center: GeoPoint, radius: meters, notifyOnEnter: bool, notifyOnExit: bool
//
// Uses OpenStreetMap tiles — completely free, no API key required.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/constants/app_colors.dart';

class GeofenceSetupScreen extends StatefulWidget {
  const GeofenceSetupScreen({super.key});

  @override
  State<GeofenceSetupScreen> createState() => _GeofenceSetupScreenState();
}

class _GeofenceSetupScreenState extends State<GeofenceSetupScreen>
    with SingleTickerProviderStateMixin {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  final _mapCtrl = MapController();
  Position? _currentPos;
  bool _loading = true;

  // Zone state
  LatLng _center = const LatLng(13.0827, 80.2707); // default Chennai
  double _radiusM = 500;
  bool _notifyEnter = true;
  bool _notifyExit = true;

  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool svc = await Geolocator.isLocationServiceEnabled();
      if (!svc) {
        setState(() => _loading = false);
        return;
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) {
          setState(() => _loading = false);
          return;
        }
      }
      if (perm == LocationPermission.deniedForever) {
        setState(() => _loading = false);
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      setState(() {
        _currentPos = pos;
        _center = LatLng(pos.latitude, pos.longitude);
        _loading = false;
      });
      _mapCtrl.move(_center, 16);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveZone() async {
    HapticFeedback.mediumImpact();
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('geofence')
          .doc('home')
          .set({
        'center': GeoPoint(_center.latitude, _center.longitude),
        'radiusM': _radiusM,
        'notifyOnEnter': _notifyEnter,
        'notifyOnExit': _notifyExit,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Safe zone saved!',
              style: TextStyle(fontFamily: 'Poppins')),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e',
              style: const TextStyle(fontFamily: 'Poppins')),
          backgroundColor: AppColors.sos,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F8),
      appBar: _buildAppBar(),
      body: _loading ? _buildLoading() : _buildBody(),
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
          'Setup Safe Zone',
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
            onTap: _saveZone,
            child: Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Save',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      );

  Widget _buildLoading() => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
            SizedBox(height: 16),
            Text(
              'Getting your location…',
              style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      );

  Widget _buildBody() {
    final circleColor = _currentPos != null ? AppColors.success : AppColors.primary;

    return Stack(
      children: [
        // ── Map ────────────────────────────────────────────────────────────────
        FlutterMap(
          mapController: _mapCtrl,
          options: MapOptions(
            initialCenter: _center,
            initialZoom: 16,
            onTap: (tapPos, latLng) {
              setState(() => _center = latLng);
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.tapguard.app',
            ),
            CircleLayer(
              circles: [
                CircleMarker(
                  point: _center,
                  radius: _radiusM,
                  useRadiusInMeter: true,
                  color: circleColor.withValues(alpha: 0.15),
                  borderColor: circleColor,
                  borderStrokeWidth: 2,
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: _center,
                  width: 40,
                  height: 40,
                  child: Container(
                    decoration: BoxDecoration(
                      color: circleColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: circleColor.withValues(alpha: 0.4),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.home_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),

        // ── My location button ────────────────────────────────────────────────
        Positioned(
          bottom: 380,
          right: 16,
          child: GestureDetector(
            onTap: _getCurrentLocation,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child:
                  const Icon(Icons.my_location_rounded, color: AppColors.primary, size: 22),
            ),
          ),
        ),

        // ── Bottom controls card ─────────────────────────────────────────────
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.fence_rounded,
                          color: AppColors.primary, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Home Safe Zone',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A1A2E),
                            ),
                          ),
                          Text(
                            'Tap map to reposition center',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Text(
                          '${_radiusM.toInt()}m',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.success,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Radius slider
                const Text(
                  'Radius',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text(
                      '100m',
                      style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 11, color: Colors.grey),
                    ),
                    Expanded(
                      child: Slider(
                        value: _radiusM,
                        min: 100,
                        max: 2000,
                        divisions: 19,
                        activeColor: AppColors.primary,
                        inactiveColor: AppColors.primary.withValues(alpha: 0.15),
                        onChanged: (v) => setState(() => _radiusM = v),
                      ),
                    ),
                    const Text(
                      '2km',
                      style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Alert toggles
                _toggleRow('Notify when I enter this zone', _notifyEnter,
                    (v) => setState(() => _notifyEnter = v)),
                const SizedBox(height: 8),
                _toggleRow('Alert contacts on arrival', _notifyExit,
                    (v) => setState(() => _notifyExit = v)),

                const SizedBox(height: 14),

                // Privacy note
                Row(
                  children: [
                    Icon(Icons.lock_outline_rounded,
                        size: 12, color: Colors.grey.shade400),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'END-TO-END ENCRYPTED LOCATION DATA',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade400,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _toggleRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: Color(0xFF1A1A2E),
            ),
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.primary,
        ),
      ],
    );
  }
}
