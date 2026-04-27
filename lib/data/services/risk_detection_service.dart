// lib/data/services/risk_detection_service.dart
//
// Context-Aware Risk Detection Engine
// ==================================
// A rule-based scoring model that continuously evaluates user safety risk.
//
// RISK SCORING FORMULA:
//   Risk Score = Time Score + Location Score + Movement Score + Inactivity Score
//
// THRESHOLDS:
//   LOW  RISK  → score < 15  → No action needed
//   MEDIUM RISK → score 15–24 → Show "Are you safe?" warning
//   HIGH RISK  → score >= 25 → Auto-trigger SOS + live tracking + alert contacts
//
// INPUTS (collected every evaluation cycle):
//   Time        → Hour of day (night hours = higher risk)
//   Location    → GPS speed + movement type (stationary / walking / running / sudden)
//   Movement    → Accelerometer-derived motion pattern
//   Inactivity  → Seconds since last user interaction (tap / scroll / etc.)
//
// HOW IT WORKS:
//   1. RiskDetectionService.startMonitoring() → starts periodic evaluation every 10s
//   2. On each evaluation cycle → collects GPS + inactivity data → calculates score
//   3. Score → RiskLevel → fires appropriate response
//   4. Shake detection runs continuously → immediate HIGH RISK on violent shake
//
// USAGE:
//   final risk = RiskDetectionService();
//   risk.startMonitoring();
//   risk.riskStream.listen((result) {
//     if (result.shouldTriggerSos) { ... }
//     if (result.shouldWarn)      { showWarningDialog(); }
//   });
//   risk.recordInteraction(); // call on every user touch/tap
//   risk.stopMonitoring();

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shake/shake.dart';

/// Risk levels in increasing severity order.
enum RiskLevel { low, medium, high }

/// Result returned after each risk evaluation cycle.
class RiskResult {
  final RiskLevel level;
  final double score;
  final Map<String, dynamic> factors;
  final DateTime evaluatedAt;

  const RiskResult({
    required this.level,
    required this.score,
    required this.factors,
    required this.evaluatedAt,
  });

  /// True if user should see a "Are you safe?" warning dialog.
  bool get shouldWarn => level == RiskLevel.medium;

  /// True if SOS should be automatically triggered.
  bool get shouldTriggerSos => level == RiskLevel.high;

  @override
  String toString() =>
      'RiskResult(level: $level, score: ${score.toStringAsFixed(1)}, factors: $factors)';
}

class RiskDetectionService {
  static final RiskDetectionService _i = RiskDetectionService._();
  factory RiskDetectionService() => _i;
  RiskDetectionService._() {
    _shakeDetector = ShakeDetector.autoStart(
      onPhoneShake: _onShakeDetected,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONSTANTS — risk weights and thresholds
  // ═══════════════════════════════════════════════════════════════════════════

  /// Time-of-day weights by hour (0–23).
  /// Higher values = riskier time of day (e.g. late night / early morning).
  static const Map<int, int> _timeWeights = {
    0: 9, 1: 9, 2: 9, 3: 9,             // 12am–3am: very high
    4: 8, 5: 7,                          // 4am–5am: high
    6: 4, 7: 2,                          // 6am–7am: moderate
    8: 1, 9: 1, 10: 1, 11: 1,           // 8am–11am: low
    12: 1, 13: 1, 14: 1, 15: 1, 16: 1,   // noon–4pm: low
    17: 1,                               // 5pm: low
    18: 2, 19: 3,                        // 6pm–7pm: slight rise
    20: 5, 21: 7,                        // 8pm–9pm: moderate
    22: 8, 23: 9,                        // 10pm–11pm: high
  };

  /// Speed thresholds in metres/second.
  static const double _speedStationary = 0.5;
  static const double _speedWalking    = 1.5;
  static const double _speedRunning     = 3.5;
  static const double _speedSudden      = 6.0;

  /// Score contributions for movement state.
  static const double _moveStationary = 3.0;
  static const double _moveWalking    = 1.0;
  static const double _moveRunning    = 5.0;
  static const double _moveSudden     = 9.0;

  /// Inactivity thresholds in seconds.
  static const int _warningInactivitySecs = 120;  // 2 minutes  → warning
  static const int _highInactivitySecs    = 300;  // 5 minutes → high risk

  /// Risk score thresholds.
  static const double _mediumThreshold = 15.0;
  static const double _highThreshold   = 25.0;

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════════

  final _resultCtrl    = StreamController<RiskResult>.broadcast();
  late final ShakeDetector _shakeDetector;

  Stream<RiskResult> get riskStream      => _resultCtrl.stream;
  RiskResult?        get lastResult     => _lastResult;
  bool               get isMonitoring   => _isMonitoring;
  bool               get sosTriggered   => _sosTriggered;

  bool               _isMonitoring = false;
  bool               _sosTriggered = false;
  Timer?             _evalTimer;
  Position?          _lastPosition;
  DateTime?          _lastInteraction;
  DateTime?          _sessionStart;
  RiskResult?        _lastResult;

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start continuous risk monitoring.
  /// Evaluation runs every 10 seconds. Shake detection runs continuously.
  Future<void> startMonitoring() async {
    if (_isMonitoring) return;
    _isMonitoring  = true;
    _sosTriggered = false;
    _sessionStart = DateTime.now();
    _lastInteraction = DateTime.now();

    _startShakeDetection();

    // Run first evaluation after 3 seconds, then every 10 seconds
    await Future.delayed(const Duration(seconds: 3));
    if (_isMonitoring) await _evaluate();

    _evalTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) async { if (_isMonitoring) await _evaluate(); },
    );
  }

  /// Stop monitoring.
  Future<void> stopMonitoring() async {
    _isMonitoring = false;
    _evalTimer?.cancel();
    _evalTimer = null;
    _shakeDetector.stopListening();
  }

  /// Call this on every user interaction (tap, scroll, key press).
  /// Resets the inactivity timer.
  void recordInteraction() {
    _lastInteraction = DateTime.now();
  }

  /// Manually trigger SOS immediately.
  Future<void> triggerSosManually() async {
    if (_sosTriggered) return;
    _sosTriggered = true;
    final result = RiskResult(
      level: RiskLevel.high,
      score: 100.0,
      factors: {'trigger': 'manual', 'timestamp': DateTime.now().toIso8601String()},
      evaluatedAt: DateTime.now(),
    );
    _lastResult = result;
    _resultCtrl.add(result);
    await _dispatchSos(result);
  }

  /// Cancel an active SOS.
  Future<void> cancelSos() async {
    _sosTriggered = false;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'sosActive': false,
        'sosTriggeredAt': null,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// "I am safe" — resets inactivity + cancels SOS + notifies contacts.
  Future<void> sendSafetyConfirmation() async {
    recordInteraction();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Cancel SOS in user doc
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'lastSafeAt': FieldValue.serverTimestamp(),
        'sosActive': false,
        'sosTriggeredAt': null,
      }, SetOptions(merge: true));
    } catch (_) {}

    _sosTriggered = false;

    // Notify all trusted contacts — write to each contact's own notifications collection
    final contacts = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('contacts')
        .get();

    for (final doc in contacts.docs) {
      final contactUid = doc.data()['uid'] as String? ?? doc.id;
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(contactUid)
            .collection('notifications')
            .add({
          'type': 'safety_confirmation',
          'fromUid': uid,
          'message': '${FirebaseAuth.instance.currentUser?.displayName ?? 'User'} is safe',
          'createdAt': FieldValue.serverTimestamp(),
          'read': false,
        });
      } catch (_) {}
    }
  }

  void dispose() {
    stopMonitoring();
    _resultCtrl.close();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INTERNAL METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  void _startShakeDetection() {
    _shakeDetector.startListening();
  }

  void _onShakeDetected([ShakeEvent? event]) {
    if (_sosTriggered) return;
    _sosTriggered = true;

    final result = RiskResult(
      level: RiskLevel.high,
      score: 100.0,
      factors: {
        'trigger': 'shake_detected',
        'timestamp': DateTime.now().toIso8601String(),
      },
      evaluatedAt: DateTime.now(),
    );

    _lastResult = result;
    _resultCtrl.add(result);
    _dispatchSos(result);
  }

  Future<void> _evaluate() async {
    if (!_isMonitoring || _sosTriggered) return;

    final factors = <String, dynamic>{};
    double score = 0.0;

    // ── 1. TIME ───────────────────────────────────────────────────────────────
    final now = DateTime.now();
    final hour = now.hour;
    final timeWeight = _timeWeights[hour] ?? 1;
    // Time score = just the weight directly (1–9 scale, not multiplied)
    factors['hour']       = hour;
    factors['timeWeight'] = timeWeight;
    factors['timeScore']  = timeWeight.toDouble();
    score += timeWeight.toDouble();

    // ── 2. MOVEMENT / SPEED ───────────────────────────────────────────────────
    double moveScore = 0.0;
    double speed = 0.0;
    String moveType = 'unknown';

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        ),
      );
      _lastPosition = pos;
      speed = pos.speed;

      if (speed < _speedStationary) {
        moveType = 'stationary';
        moveScore = _moveStationary;
      } else if (speed < _speedWalking) {
        moveType = 'slow';
        moveScore = 2.0;
      } else if (speed < _speedRunning) {
        moveType = 'walking';
        moveScore = _moveWalking;
      } else if (speed < _speedSudden) {
        moveType = 'running';
        moveScore = _moveRunning;
      } else {
        moveType = 'sudden_motion';
        moveScore = _moveSudden;
      }
    } catch (_) {
      moveType = 'unknown';
      moveScore = 2.0; // assume moderate risk when location unavailable
      speed = 0.0;
    }

    factors['speed']      = speed;
    factors['moveType']   = moveType;
    factors['moveScore']  = moveScore;
    score += moveScore;

    // ── 3. INACTIVITY ──────────────────────────────────────────────────────────
    double inactScore = 0.0;
    if (_lastInteraction != null) {
      final inactiveSecs = DateTime.now().difference(_lastInteraction!).inSeconds;
      if (inactiveSecs >= _highInactivitySecs) {
        inactScore = 8.0;
      } else if (inactiveSecs >= _warningInactivitySecs) {
        inactScore = 4.0;
      }
      factors['inactiveSecs'] = inactiveSecs;
      factors['inactScore']   = inactScore;
      score += inactScore;
    }

    // ── 4. SESSION DURATION (longer alone = slightly higher risk) ──────────────
    double durScore = 0.0;
    if (_sessionStart != null) {
      final sessionMins = DateTime.now().difference(_sessionStart!).inMinutes;
      if (sessionMins >= 120)      { durScore = 6.0; }
      else if (sessionMins >= 60)  { durScore = 4.0; }
      else if (sessionMins >= 30)  { durScore = 2.0; }
      factors['sessionMins'] = sessionMins;
      factors['durScore']   = durScore;
      score += durScore;
    }

    // ── DETERMINE RISK LEVEL ─────────────────────────────────────────────────
    RiskLevel level;
    if (score >= _highThreshold) {
      level = RiskLevel.high;
    } else if (score >= _mediumThreshold) {
      level = RiskLevel.medium;
    } else {
      level = RiskLevel.low;
    }

    final result = RiskResult(
      level: level,
      score: score,
      factors: factors,
      evaluatedAt: DateTime.now(),
    );

    _lastResult = result;

    if (level == RiskLevel.high && !_sosTriggered) {
      _sosTriggered = true;
      _dispatchSos(result);
    }

    _resultCtrl.add(result);
  }

  
  /// Dispatch SOS alert to Firestore + all trusted contacts.
  Future<void> _dispatchSos(RiskResult result) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Update SOS flag in user doc
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'sosActive':      true,
        'sosTriggeredAt': FieldValue.serverTimestamp(),
        'sosLocation': (_lastPosition != null)
            ? GeoPoint(_lastPosition!.latitude, _lastPosition!.longitude)
            : null,
        'sosRiskFactors': result.factors,
      }, SetOptions(merge: true));
    } catch (_) {}

    // Get trusted contacts
    final contacts = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('contacts')
        .get();

    for (final doc in contacts.docs) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(doc.id)
            .collection('notifications')
            .add({
          'type':       'sos_alert',
          'fromUid':    uid,
          'fromName':   FirebaseAuth.instance.currentUser?.displayName ?? 'User',
          'message':    'SOS ALERT! Trusted contact needs help.',
          'location':   _lastPosition != null
              ? '${_lastPosition!.latitude},${_lastPosition!.longitude}'
              : null,
          'createdAt':   FieldValue.serverTimestamp(),
          'read':        false,
        });
      } catch (_) {}
    }
  }

  /// Save preferences to SharedPreferences.
  Future<void> savePreferences({
    required bool shakeDetectionEnabled,
    required int autoTimeoutMinutes,
    required int locationAccuracyLevel,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('risk.shake_detection', shakeDetectionEnabled);
    await prefs.setInt('risk.auto_timeout', autoTimeoutMinutes);
    await prefs.setInt('risk.location_accuracy', locationAccuracyLevel);
  }

  /// Load preferences from SharedPreferences.
  Future<Map<String, dynamic>> loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'shakeDetection': prefs.getBool('risk.shake_detection') ?? true,
      'autoTimeout': prefs.getInt('risk.auto_timeout') ?? 120,
      'locationAccuracy': prefs.getInt('risk.location_accuracy') ?? 1,
    };
  }
}
