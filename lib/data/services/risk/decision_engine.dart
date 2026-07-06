// lib/data/services/risk/decision_engine.dart
//
// Phase 1 — Combines the outputs of the model + personalization + a
// small set of hard rules into a final `RiskResult`. The shape of
// the result is identical to the legacy rule-based engine so the
// rest of the app doesn't change.
//
// Weights (locked, can be tuned in Phase 4):
//   model 0.45 + anomaly 0.30 + keyword 0.15 + rules 0.10

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'feature_extractor.dart';
import 'location_collector.dart';
import 'model_health_monitor.dart';
import 'motion_collector.dart';
import 'risk_model.dart';
import 'user_baseline.dart';

enum RiskLevel { low, medium, high }

class RiskResult {
  final RiskLevel level;
  final double score; // 0..1
  final Map<String, dynamic> factors;
  final DateTime evaluatedAt;
  final double modelScore;
  final double anomalyScore;
  final double keywordScore;
  final double rulesScore;

  const RiskResult({
    required this.level,
    required this.score,
    required this.factors,
    required this.evaluatedAt,
    required this.modelScore,
    required this.anomalyScore,
    required this.keywordScore,
    required this.rulesScore,
  });

  bool get shouldWarn => level == RiskLevel.medium;
  bool get shouldTriggerSos => level == RiskLevel.high;

  @override
  String toString() =>
      'RiskResult(${level.name}, score=${score.toStringAsFixed(2)}, '
      'model=${modelScore.toStringAsFixed(2)}, '
      'anom=${anomalyScore.toStringAsFixed(2)}, '
      'kw=${keywordScore.toStringAsFixed(2)}, '
      'rules=${rulesScore.toStringAsFixed(2)})';
}

class DecisionEngine {
  DecisionEngine({
    RiskModel? model,
    UserBaseline? baseline,
    this.healthMonitor,
  })  : _model = model ?? RiskModel(),
        _baseline = baseline ?? UserBaseline();

  final RiskModel _model;
  final UserBaseline _baseline;

  /// Optional — when set, the engine skips the model output and
  /// uses the heuristic if the monitor has rolled back.
  final ModelHealthMonitor? healthMonitor;

  // Weights
  static const double _wModel = 0.45;
  static const double _wAnomaly = 0.30;
  static const double _wKeyword = 0.15;
  static const double _wRules = 0.10;

  // Thresholds — tuned for conservative behaviour:
  //   - 0.40 → "are you safe?" warning
  //   - 0.70 → auto-trigger SOS
  // These will be re-tuned in Phase 4 with real data.
  static const double _tMedium = 0.40;
  static const double _tHigh = 0.70;

  DateTime? _lastInteraction;
  DateTime? _sessionStart;

  void recordInteraction() {
    _lastInteraction = DateTime.now();
  }

  void startSession() {
    _sessionStart = DateTime.now();
    _lastInteraction ??= DateTime.now();
  }

  /// Decide the next risk result. Called once per second.
  Future<RiskResult> decide({
    required RiskFeatures features,
    required MotionWindow? motion,
    required double keywordConfidence,
    required LocationSample? location,
  }) async {
    final now = DateTime.now();

    // 1. Model — A/B aware. When the model is loaded we get both
    //    scores; the engine uses the model score, but the heuristic
    //    is also recorded in the factors for A/B analysis.
    final inference = await _model.inferWithCompare(features);
    var modelScore = inference.activeScore;
    final heuristicScore = inference.heuristicScore;
    final usedModel = inference.usedModel;

    // 1a. Phase 6 — if the health monitor has rolled back, force
    //     the heuristic score and tag the result.
    final rolledBack = healthMonitor?.forceHeuristic ?? false;
    if (rolledBack) {
      modelScore = heuristicScore;
    }

    // 2. Anomaly — pulled from the user baseline (real personalization)
    //    when the baseline is ready, else fall back to the
    //    feature-only heuristic so the engine works on day 1.
    double anomalyScore;
    if (_baseline.isReady && location != null) {
      anomalyScore = _baseline.anomaly(location);
    } else {
      anomalyScore = _anomalyFromFeatures(features);
    }

    // 3. Keyword
    final keywordScore = keywordConfidence.clamp(0.0, 1.0);

    // 4. Hard rules
    final rulesScore = _hardRules(features, motion, now);

    final total = modelScore * _wModel +
        anomalyScore * _wAnomaly +
        keywordScore * _wKeyword +
        rulesScore * _wRules;

    final RiskLevel level;
    if (total >= _tHigh) {
      level = RiskLevel.high;
    } else if (total >= _tMedium) {
      level = RiskLevel.medium;
    } else {
      level = RiskLevel.low;
    }

    final factors = <String, dynamic>{
      'model': modelScore,
      'model_heuristic': heuristicScore,
      'used_model': usedModel,
      'rolled_back': rolledBack,
      'anomaly': anomalyScore,
      'anomaly_personalized': _baseline.isReady,
      'baseline_samples': _baseline.totalSamples,
      'baseline_ready': _baseline.isReady,
      'keyword': keywordScore,
      'rules': rulesScore,
      'weights': {
        'model': _wModel,
        'anomaly': _wAnomaly,
        'keyword': _wKeyword,
        'rules': _wRules,
      },
      'motion': {
        'accelMean': features.accelMagMean,
        'accelMax': features.accelMagMax,
        'jerk': features.accelJerk,
        'gyroMax': features.gyroMagMax,
        'stationary': features.isStationary,
        'violent': features.isViolent,
        'fast': features.isFast,
        'jittery': features.isJittery,
      },
      'location': {
        'speed': features.speed,
        'distanceFromHome': features.distanceFromHome,
        'distanceFromNearestFrequent': features.distanceFromNearestFrequent,
        'entropy': features.entropy,
      },
      'context': {
        'lateNight': features.lateNight,
        'battery': features.batteryLevel,
        'online': features.isOnline,
      },
      'audio': {
        'verbalAggression': features.audioVerbalAggression,
        'glassBreaking': features.audioGlassBreaking,
        'vehicleImpact': features.audioVehicleImpact,
        'explosion': features.audioExplosion,
        'alarm': features.audioAlarm,
      },
    };

    if (kDebugMode) {
      debugPrint(
        '[DecisionEngine] score=${total.toStringAsFixed(2)} '
        'model=${modelScore.toStringAsFixed(2)} '
        'anom=${anomalyScore.toStringAsFixed(2)} '
        'kw=${keywordScore.toStringAsFixed(2)} '
        'rules=${rulesScore.toStringAsFixed(2)} '
        '${usedModel ? "[model]" : "[heuristic]"} '
        '${_baseline.isReady ? "[personalized]" : "[cold-start]"} '
        '${rolledBack ? "[rolled-back]" : ""}',
      );
    }

    return RiskResult(
      level: level,
      score: total.clamp(0.0, 1.0),
      factors: factors,
      evaluatedAt: now,
      modelScore: modelScore,
      anomalyScore: anomalyScore,
      keywordScore: keywordScore,
      rulesScore: rulesScore,
    );
  }

  // ── Anomaly from feature vector (Phase 1) ──────────────────────────────
  double _anomalyFromFeatures(RiskFeatures f) {
    final speedZ = _zScore(f.speed, 1.2, 1.5);
    final entropyZ = _zScore(f.entropy, 0.1, 0.2);
    final distZ = _zScore(f.distanceFromHome, 200.0, 5000.0);
    final maxZ = math.max(0.0, math.max(speedZ, math.max(entropyZ, distZ)));
    return (1 - math.exp(-maxZ)).clamp(0.0, 1.0);
  }

  // ── Hard rules (Phase 1) ──────────────────────────────────────────────
  double _hardRules(RiskFeatures f, MotionWindow? m, DateTime now) {
    double score = 0.0;

    // Late-night + away from home
    if (f.lateNight > 0 && f.distanceFromHome > 1000) {
      score += 0.4;
    } else if (f.lateNight > 0) {
      score += 0.15;
    }

    // Inactivity > 5 min after the session started
    if (_sessionStart != null && _lastInteraction != null) {
      final idleSecs = now.difference(_lastInteraction!).inSeconds;
      if (idleSecs > 300) {
        score += 0.4;
      } else if (idleSecs > 120) {
        score += 0.2;
      }
    }

    // Violent motion (fall, impact)
    if (m != null && m.isViolent) {
      score += 0.6;
    }

    // Very high jerk alone (panic run)
    if (f.accelJerk > 4.0 && f.accelMagMax > 15.0) {
      score += 0.3;
    }

    // Phase 4 — YAMNet audio events. A strong distress audio
    // signal (scream, glass, crash, alarm) is a strong indicator
    // even before the model has been retrained.
    final audioMax = [
      f.audioVerbalAggression,
      f.audioGlassBreaking,
      f.audioVehicleImpact,
      f.audioExplosion,
      f.audioAlarm,
    ].reduce((a, b) => a > b ? a : b);
    if (audioMax > 0.7) {
      score += 0.6;
    } else if (audioMax > 0.4) {
      score += 0.3;
    }

    return score.clamp(0.0, 1.0);
  }

  static double _zScore(double x, double mean, double std) {
    if (x.isNaN) return 0.0;
    return ((x - mean).abs() / std);
  }
}
