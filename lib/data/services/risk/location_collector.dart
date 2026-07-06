// lib/data/services/risk/location_collector.dart
//
// Phase 1 — Subscribes to GPS at 1 Hz and emits a `LocationSample`
// with computed features:
//   * current speed
//   * distance from each "frequent place" (home, work, etc.)
//   * entropy of recent positions (high = roaming, low = stationary)
//
// In Phase 3 the `UserBaseline` clusters the user's GPS history into
// a small set of frequent places and the location collector is kept
// in sync via `frequentPlaces = ...`.

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'user_baseline.dart';

class LocationSample {
  final DateTime at;
  final double lat;
  final double lng;
  final double speed; // m/s
  final double accuracy; // m
  final double distanceFromHome; // m
  final double? distanceFromNearestFrequent; // m
  final double entropy;

  const LocationSample({
    required this.at,
    required this.lat,
    required this.lng,
    required this.speed,
    required this.accuracy,
    required this.distanceFromHome,
    required this.distanceFromNearestFrequent,
    required this.entropy,
  });

  @override
  String toString() =>
      'LocationSample(speed: ${speed.toStringAsFixed(1)} m/s, '
      'fromHome: ${distanceFromHome.toStringAsFixed(0)} m, '
      'entropy: ${entropy.toStringAsFixed(2)})';
}

class LocationCollector {
  LocationCollector();

  StreamSubscription<Position>? _sub;
  final List<Position> _recent = [];
  static const int _historySize = 20;

  /// User's declared home (or any single frequent place). Updated
  /// from settings; defaults to null.
  FrequentPlace? home;

  /// Additional frequent places — populated from the
  /// `UserBaseline`'s clustering pass. Phase 3 keeps this list
  /// in sync with the persistent baseline.
  List<FrequentPlace> frequentPlaces = <FrequentPlace>[];

  final _ctrl = StreamController<LocationSample>.broadcast();
  Stream<LocationSample> get sampleStream => _ctrl.stream;

  bool _running = false;
  bool get isRunning => _running;

  Future<bool> start() async {
    if (_running) return true;

    if (!await Geolocator.isLocationServiceEnabled()) {
      debugPrint('[LocationCollector] GPS is off');
      return false;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever ||
        perm == LocationPermission.denied) {
      debugPrint('[LocationCollector] permission denied');
      return false;
    }

    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // 1 update / ~5m of movement
      ),
    ).listen(_onPosition, onError: (e) {
      debugPrint('[LocationCollector] stream error: $e');
    });
    _running = true;
    return true;
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _sub?.cancel();
    _sub = null;
    _recent.clear();
  }

  void dispose() {
    stop();
    _ctrl.close();
  }

  void setHome(double lat, double lng) {
    final now = DateTime.now();
    home = FrequentPlace(
      id: 'home',
      label: 'Home',
      lat: lat,
      lng: lng,
      radiusMeters: 100.0,
      visitCount: 1,
      firstSeen: now,
      lastSeen: now,
    );
  }

  // ── Internal ──────────────────────────────────────────────────────────
  void _onPosition(Position p) {
    _recent.add(p);
    if (_recent.length > _historySize) {
      _recent.removeAt(0);
    }

    final fromHome = home == null
        ? double.nan
        : _haversine(p.latitude, p.longitude, home!.lat, home!.lng);

    double? fromNearest;
    if (frequentPlaces.isNotEmpty) {
      var minDist = double.infinity;
      for (final place in frequentPlaces) {
        final d = _haversine(p.latitude, p.longitude, place.lat, place.lng);
        if (d < minDist) minDist = d;
      }
      fromNearest = minDist;
    }

    final entropy = _entropy();

    _ctrl.add(LocationSample(
      at: DateTime.fromMillisecondsSinceEpoch(p.timestamp.millisecondsSinceEpoch),
      lat: p.latitude,
      lng: p.longitude,
      speed: p.speed,
      accuracy: p.accuracy,
      distanceFromHome: fromHome,
      distanceFromNearestFrequent: fromNearest,
      entropy: entropy,
    ));
  }

  /// Spatial entropy in [0, 1]. 0 = stayed in one spot; 1 = roaming.
  double _entropy() {
    if (_recent.length < 4) return 0.0;
    // Use the bounding-box diagonal normalized by the radius covered
    double minLat = _recent.first.latitude;
    double maxLat = _recent.first.latitude;
    double minLng = _recent.first.longitude;
    double maxLng = _recent.first.longitude;
    for (final p in _recent) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    final span = _haversine(minLat, minLng, maxLat, maxLng);
    // Cap at 5 km
    return (span / 5000.0).clamp(0.0, 1.0);
  }

  /// Great-circle distance in meters.
  static double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0; // earth radius in meters
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLng = (lng2 - lng1) * math.pi / 180.0;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }
}
