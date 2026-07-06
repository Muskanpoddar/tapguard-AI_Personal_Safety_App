// lib/data/services/risk/user_baseline.dart
//
// Phase 3 — On-device personalization.
//
// Responsibilities:
//   * Cluster the user's GPS history into a small set of "frequent
//     places" (home, work, gym, …) using a simple grid-based
//     approach (DBSCAN would be ideal but requires a third-party
//     package).
//   * Maintain a per-hour-of-day motion profile (typical speed +
//     typical spatial entropy) so the engine can flag "you're moving
//     differently at this hour than usual".
//   * Persist across app restarts via a `BaselineStore` (Hive in
//     production, in-memory in tests).
//   * Compute an anomaly score for the current sample — used by the
//     decision engine to weight the final risk.
//
// The baseline converges over the first session or two of use. Until
// enough samples are observed the anomaly score is conservative
// (returns 0). The default ready threshold is [kReadyThreshold]
// (25 samples ≈ a few minutes of normal use).

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'baseline_store.dart';
import 'location_collector.dart';

/// A user-defined "frequent place" — a circular area on the map.
@immutable
class FrequentPlace {
  final String id;
  final String label;
  final double lat;
  final double lng;
  final double radiusMeters;
  final int visitCount;
  final DateTime firstSeen;
  final DateTime lastSeen;

  const FrequentPlace({
    required this.id,
    required this.label,
    required this.lat,
    required this.lng,
    required this.radiusMeters,
    required this.visitCount,
    required this.firstSeen,
    required this.lastSeen,
  });

  FrequentPlace copyWith({
    int? visitCount,
    DateTime? lastSeen,
    double? lat,
    double? lng,
    double? radiusMeters,
  }) {
    return FrequentPlace(
      id: id,
      label: label,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      visitCount: visitCount ?? this.visitCount,
      firstSeen: firstSeen,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}

/// Per-hour typical motion (one entry per hour of the day).
@immutable
class HourlyMotionProfile {
  final int hour; // 0..23
  final double typicalSpeed;
  final double typicalEntropy;
  final int sampleCount;

  const HourlyMotionProfile({
    required this.hour,
    this.typicalSpeed = 1.2,
    this.typicalEntropy = 0.1,
    this.sampleCount = 0,
  });

  HourlyMotionProfile copyWith({
    double? typicalSpeed,
    double? typicalEntropy,
    int? sampleCount,
  }) {
    return HourlyMotionProfile(
      hour: hour,
      typicalSpeed: typicalSpeed ?? this.typicalSpeed,
      typicalEntropy: typicalEntropy ?? this.typicalEntropy,
      sampleCount: sampleCount ?? this.sampleCount,
    );
  }
}

class UserBaseline {
  /// Number of observations the baseline needs before [isReady] flips
  /// to `true` and the personalised anomaly score is used by the
  /// decision engine.
  ///
  /// Reduced from 200 → 25 so users see the progress indicator move
  /// during their first session rather than waiting ~3 days.
  static const int kReadyThreshold = 25;

  UserBaseline({
    BaselineStore? store,
    int readyThreshold = kReadyThreshold,
  })  : _store = store ?? MemoryBaselineStore(),
        _readyThreshold = readyThreshold;

  final BaselineStore _store;
  final int _readyThreshold;
  bool _opened = false;
  bool _ready = false;

  // Grid-based frequent place detection
  static const double _gridSizeDeg = 0.001; // ~111m
  static const int _maxFrequentPlaces = 5;

  // EMA learning rates
  static const double _speedAlpha = 0.02;
  static const double _entropyAlpha = 0.02;
  static const double _placeVisitAlpha = 0.05;

  UserBaselineData _data = UserBaselineData.fresh();

  /// True once we've collected enough samples to trust the anomaly
  /// score. Threshold is [kReadyThreshold] (25) by default.
  bool get isReady => _ready;

  /// The configured ready threshold. Useful for progress UI.
  int get readyThreshold => _readyThreshold;

  int get totalSamples => _data.totalSamples;
  List<FrequentPlace> get frequentPlaces =>
      List.unmodifiable(_data.frequentPlaces);
  List<HourlyMotionProfile> get hourlyProfiles =>
      List.unmodifiable(_data.hourlyProfiles);

  /// Broadcast stream that fires every time [observe] runs. UI
  /// subscribes to this to refresh "X / N samples" progress without
  /// needing a full Riverpod rebuild of the engine.
  final _changesCtrl = StreamController<void>.broadcast();
  Stream<void> get changes => _changesCtrl.stream;

  /// Number of hours of motion profile that have any samples.
  int get observedHours =>
      _data.hourlyProfiles.where((p) => p.sampleCount > 0).length;

  // ── Lifecycle ──────────────────────────────────────────────────────
  Future<void> load() async {
    if (_opened) return;
    await _store.open();
    _data = await _store.load();
    _opened = true;
    _recomputeReady();
    debugPrint(
      '[UserBaseline] loaded ${_data.totalSamples} samples, '
      '${_data.frequentPlaces.length} frequent places, '
      '$observedHours observed hours',
    );
  }

  Future<void> save() async {
    if (!_opened) return;
    await _store.save(_data);
  }

  Future<void> close() async {
    if (!_opened) return;
    await save();
    await _store.close();
    _opened = false;
    if (!_changesCtrl.isClosed) await _changesCtrl.close();
  }

  void _recomputeReady() {
    _ready = _data.totalSamples >= _readyThreshold;
  }

  // ── Observation API ───────────────────────────────────────────────
  /// Call on every `LocationSample` so the baseline converges.
  Future<void> observe(LocationSample sample) async {
    if (!_opened) await load();

    // 1. Update the hourly motion profile
    final hour = sample.at.hour;
    _data.hourlyProfiles[hour] = _data.hourlyProfiles[hour].copyWith(
          typicalSpeed: _ema(
            _data.hourlyProfiles[hour].typicalSpeed,
            sample.speed.isFinite ? sample.speed : 0,
            _speedAlpha,
          ),
          typicalEntropy: _ema(
            _data.hourlyProfiles[hour].typicalEntropy,
            sample.entropy,
            _entropyAlpha,
          ),
          sampleCount: _data.hourlyProfiles[hour].sampleCount + 1,
        );

    // 2. Update frequent places via grid-based clustering
    _updateFrequentPlaces(sample);

    _data = UserBaselineData(
      frequentPlaces: _data.frequentPlaces,
      hourlyProfiles: _data.hourlyProfiles,
      totalSamples: _data.totalSamples + 1,
      updatedAt: DateTime.now(),
    );
    _recomputeReady();

    // Persist every 50 samples (avoid hammering Hive)
    if (_data.totalSamples % 50 == 0) {
      await save();
    }

    // Notify subscribers (e.g. the Risk Insights screen) so the live
    // "X / N samples" counter updates without needing a Riverpod
    // rebuild of the whole engine.
    if (!_changesCtrl.isClosed) _changesCtrl.add(null);
  }

  void _updateFrequentPlaces(LocationSample sample) {
    // Check if the sample falls inside any existing place's radius
    for (final place in _data.frequentPlaces) {
      final d = _haversine(
        sample.lat,
        sample.lng,
        place.lat,
        place.lng,
      );
      if (d <= place.radiusMeters) {
        // Update existing place: pull center toward sample, increment visits
        final newLat = _ema(place.lat, sample.lat, _placeVisitAlpha);
        final newLng = _ema(place.lng, sample.lng, _placeVisitAlpha);
        final newRadius = math.max(
          place.radiusMeters,
          d + 30.0, // at least 30m wider than the new sample's distance
        );
        final updated = place.copyWith(
          lat: newLat,
          lng: newLng,
          radiusMeters: newRadius,
          visitCount: place.visitCount + 1,
          lastSeen: sample.at,
        );
        final i = _data.frequentPlaces.indexOf(place);
        _data.frequentPlaces[i] = updated;
        return;
      }
    }

    // New grid cell — add as a candidate
    final gridKey = _gridKey(sample.lat, sample.lng);
    final existingIdx = _data.frequentPlaces.indexWhere(
      (p) => _gridKey(p.lat, p.lng) == gridKey,
    );
    if (existingIdx >= 0) {
      // Same grid cell, different spot — merge
      final existing = _data.frequentPlaces[existingIdx];
      _data.frequentPlaces[existingIdx] = existing.copyWith(
        lat: _ema(existing.lat, sample.lat, _placeVisitAlpha),
        lng: _ema(existing.lng, sample.lng, _placeVisitAlpha),
        visitCount: existing.visitCount + 1,
        lastSeen: sample.at,
      );
      return;
    }

    // Brand new place
    if (_data.frequentPlaces.length >= _maxFrequentPlaces) {
      // Evict the least-visited place to make room
      _data.frequentPlaces.sort((a, b) => a.visitCount.compareTo(b.visitCount));
      _data.frequentPlaces.removeAt(0);
    }
    _data.frequentPlaces.add(
      FrequentPlace(
        id: 'place_${DateTime.now().microsecondsSinceEpoch}',
        label: _autoLabel(_data.frequentPlaces.length),
        lat: sample.lat,
        lng: sample.lng,
        radiusMeters: 75.0,
        visitCount: 1,
        firstSeen: sample.at,
        lastSeen: sample.at,
      ),
    );
  }

  String _autoLabel(int existingCount) {
    const labels = ['Home', 'Work', 'Gym', 'School', 'Other'];
    return labels[existingCount.clamp(0, labels.length - 1)];
  }

  // ── Anomaly score (called by DecisionEngine) ──────────────────────
  /// Returns an anomaly score in [0, 1]. 0 = typical, 1 = very
  /// unusual. Conservative before the baseline is ready.
  double anomaly(LocationSample sample) {
    if (!_ready) return 0.0;
    final hour = sample.at.hour;
    final hourly = _data.hourlyProfiles[hour];
    final hasHourly = hourly.sampleCount > 20;

    final speedZ = hasHourly
        ? _zScore(sample.speed, hourly.typicalSpeed, 1.5)
        : 0.0;
    final entropyZ = hasHourly
        ? _zScore(sample.entropy, hourly.typicalEntropy, 0.2)
        : 0.0;
    final distZ = _distanceZScore(sample);

    final maxZ = math.max(0.0, math.max(speedZ, math.max(entropyZ, distZ)));
    return (1 - math.exp(-maxZ)).clamp(0.0, 1.0);
  }

  double _distanceZScore(LocationSample sample) {
    if (_data.frequentPlaces.isEmpty) {
      // No baseline yet — assume 200m typical
      return _zScore(_minDistanceToPlaces(sample), 200.0, 5000.0);
    }
    return _zScore(_minDistanceToPlaces(sample), 100.0, 3000.0);
  }

  double _minDistanceToPlaces(LocationSample sample) {
    if (_data.frequentPlaces.isEmpty) return double.infinity;
    var minDist = double.infinity;
    for (final place in _data.frequentPlaces) {
      final d = _haversine(sample.lat, sample.lng, place.lat, place.lng);
      if (d < minDist) minDist = d;
    }
    return minDist;
  }

  // ── Utility ──────────────────────────────────────────────────────
  static double _ema(double prev, double current, double alpha) {
    if (current.isNaN) return prev;
    return (1 - alpha) * prev + alpha * current;
  }

  static double _zScore(double x, double mean, double std) {
    if (x.isNaN) return 0.0;
    if (std == 0) return 0.0;
    return (x - mean).abs() / std;
  }

  static String _gridKey(double lat, double lng) {
    final gx = (lat / _gridSizeDeg).round();
    final gy = (lng / _gridSizeDeg).round();
    return '$gx:$gy';
  }

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

  // ── Test helpers ──────────────────────────────────────────────────
  @visibleForTesting
  void reset() {
    _data = UserBaselineData.fresh();
    _ready = false;
  }

  @visibleForTesting
  void seedForTest(UserBaselineData data) {
    _data = data;
    _opened = true;
    _recomputeReady();
  }
}
