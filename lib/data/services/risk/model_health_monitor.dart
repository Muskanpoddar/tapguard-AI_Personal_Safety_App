// lib/data/services/risk/model_health_monitor.dart
//
// Phase 6 — Watches the TFLite model's output for signs of trouble
// (NaN, drift, runaway values) and forces a rollback to the
// hand-tuned heuristic when the model misbehaves.
//
// Triggers rollback when:
//   1. Output is NaN or infinity.
//   2. Output is constantly the same value (e.g. always 0.5) —
//      indicates a stuck model.
//   3. The model diverges from the heuristic by more than
//      `divergenceThreshold` for more than `divergenceStreak`
//      consecutive evaluations — indicates the model is giving
//      nonsensical scores.
//   4. The training-data positive/negative ratio is wildly off
//      (more than 10:1) — indicates the user-feedback loop is
//      mis-firing.

import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'risk_model.dart';
import 'training_data_store.dart';

enum RollbackReason {
  none,
  nanOutput,
  stuckOutput,
  divergence,
  trainingImbalance,
}

class ModelHealth {
  final bool isHealthy;
  final RollbackReason reason;
  final int consecutiveDivergences;
  final int stuckStreak;
  final DateTime lastCheckedAt;

  const ModelHealth({
    required this.isHealthy,
    required this.reason,
    required this.consecutiveDivergences,
    required this.stuckStreak,
    required this.lastCheckedAt,
  });

  @override
  String toString() =>
      'ModelHealth(healthy: $isHealthy, reason: ${reason.name}, '
      'consecutiveDiv: $consecutiveDivergences, stuck: $stuckStreak)';
}

class ModelHealthMonitor {
  ModelHealthMonitor({
    this.divergenceThreshold = 0.45,
    this.divergenceStreak = 10,
    this.stuckThreshold = 30,
    this.stuckWindow = 50,
  });

  /// How far the model score can drift from the heuristic
  /// before we treat it as suspicious.
  final double divergenceThreshold;

  /// How many consecutive suspicious evaluations before we
  /// force-rollback to the heuristic.
  final int divergenceStreak;

  /// If the model returns the same value this many times in
  /// `stuckWindow` evaluations, treat it as stuck.
  final int stuckThreshold;
  final int stuckWindow;

  final Queue<double> _recent = Queue<double>();
  int _consecutiveDivergences = 0;
  int _stuckStreak = 0;
  RollbackReason _reason = RollbackReason.none;
  DateTime _lastChecked = DateTime.now();
  bool _forceHeuristic = false;

  bool get forceHeuristic => _forceHeuristic;
  ModelHealth get current => ModelHealth(
        isHealthy: _reason == RollbackReason.none,
        reason: _reason,
        consecutiveDivergences: _consecutiveDivergences,
        stuckStreak: _stuckStreak,
        lastCheckedAt: _lastChecked,
      );

  /// Record one evaluation. Returns `true` if the model output
  /// was accepted, `false` if it should be discarded (roll back
  /// to heuristic).
  bool record({
    required RiskInference inference,
    required TrainingDataStore? trainingStore,
  }) {
    _lastChecked = DateTime.now();
    final modelScore = inference.modelScore;
    final heuristic = inference.heuristicScore;

    // 1. NaN / infinity
    if (modelScore.isNaN || modelScore.isInfinite) {
      _forceHeuristic = true;
      _reason = RollbackReason.nanOutput;
      debugPrint('[ModelHealthMonitor] NaN model output — rolling back');
      return false;
    }

    // 2. Stuck output — track recent values
    _recent.addLast(modelScore);
    if (_recent.length > stuckWindow) _recent.removeFirst();
    if (_recent.length >= stuckWindow) {
      final allSame = _recent.every((v) => (v - modelScore).abs() < 0.001);
      if (allSame) {
        _stuckStreak++;
        if (_stuckStreak >= stuckThreshold) {
          _forceHeuristic = true;
          _reason = RollbackReason.stuckOutput;
          debugPrint('[ModelHealthMonitor] stuck output — rolling back');
          return false;
        }
      } else {
        _stuckStreak = 0;
      }
    }

    // 3. Divergence from heuristic
    final divergence = (modelScore - heuristic).abs();
    if (divergence > divergenceThreshold) {
      _consecutiveDivergences++;
      if (_consecutiveDivergences >= divergenceStreak) {
        _forceHeuristic = true;
        _reason = RollbackReason.divergence;
        debugPrint('[ModelHealthMonitor] divergent from heuristic '
            '($divergence > $divergenceThreshold) for '
            '$_consecutiveDivergences evaluations — rolling back');
        return false;
      }
    } else {
      _consecutiveDivergences = 0;
    }

    // 4. Training data imbalance
    if (trainingStore != null) {
      final stats = trainingStore.stats();
      if (stats.total >= 20) {
        final ratio = stats.positiveCount == 0
            ? 0.0
            : (stats.negativeCount == 0
                ? double.infinity
                : stats.negativeCount / stats.positiveCount);
        if (ratio < 0.1 || ratio > 10) {
          _forceHeuristic = true;
          _reason = RollbackReason.trainingImbalance;
          debugPrint(
            '[ModelHealthMonitor] training imbalance (ratio=$ratio) — rolling back',
          );
          return false;
        }
      }
    }

    return true;
  }

  /// Reset the monitor (e.g. after the user clears their data).
  void reset() {
    _recent.clear();
    _consecutiveDivergences = 0;
    _stuckStreak = 0;
    _reason = RollbackReason.none;
    _forceHeuristic = false;
  }
}
