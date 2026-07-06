// lib/data/services/risk/risk_model.dart
//
// Phase 2 — Loads `assets/models/risk_classifier.tflite` if present and
// runs inference. When the model is unavailable, falls back to a
// hand-tuned heuristic that mimics the model's output.
//
// A/B logging: when the model IS loaded, both the model score and the
// heuristic score are computed and logged. The model score is what
// the decision engine uses; the heuristic is recorded for comparison.

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'feature_extractor.dart';

class RiskModel {
  RiskModel({this.heuristicOnly = false});

  /// Set `heuristicOnly` to `true` in tests to force the heuristic path
  /// (so tests don't depend on whether a TFLite model is bundled).
  final bool heuristicOnly;

  Interpreter? _interpreter;
  bool get isLoaded => _interpreter != null;
  int get _inputCount =>
      _interpreter?.getInputTensor(0).shape.reduce((a, b) => a * b) ?? 0;

  /// Initialize and load the TFLite model from assets.
  /// Returns true if loaded, false if falling back to heuristic.
  Future<bool> load({String assetPath = 'assets/models/risk_classifier.tflite'}) async {
    if (heuristicOnly) {
      debugPrint('[RiskModel] heuristicOnly=true — skipping model load');
      return false;
    }
    try {
      final options = InterpreterOptions()..threads = 1;
      _interpreter = await Interpreter.fromAsset(assetPath, options: options);
      debugPrint('[RiskModel] loaded $assetPath '
          '($_inputCount inputs, ${_interpreter!.getOutputTensor(0).shape} output)');
      return true;
    } catch (e) {
      debugPrint(
        '[RiskModel] model not loaded (falling back to heuristic): $e',
      );
      _interpreter = null;
      return false;
    }
  }

  Future<void> close() async {
    _interpreter?.close();
    _interpreter = null;
  }

  /// Run inference on the given feature vector. Returns a
  /// [RiskInference] containing both scores. If the model isn't
  /// loaded, `modelScore` is the same as `heuristicScore` and
  /// `usedModel` is `false`.
  Future<RiskInference> inferWithCompare(RiskFeatures features) async {
    final heuristic = _heuristic(features);
    if (_interpreter == null) {
      return RiskInference(
        modelScore: heuristic,
        heuristicScore: heuristic,
        usedModel: false,
        at: DateTime.now(),
      );
    }
    try {
      final input = features.toList();
      final input2d = [input];
      final outputShape = _interpreter!.getOutputTensor(0).shape;
      final outputSize = outputShape.reduce((a, b) => a * b);

      // Defensive: some exported models report an output shape like
      // `[0, N]` (batch dim = 0, dynamic). The product collapses to 0
      // and the underlying `List.generate(0, ...)` can't back the
      // interpreter — we'd throw on every 1s tick and trip the ANR
      // watchdog. Fall back to heuristic instead.
      if (outputSize <= 0) {
        throw FormatException(
          'risk_classifier.tflite output shape is degenerate '
          '(outputSize=$outputSize for $outputShape) — '
          'retrain the model or replace with one whose output rank-0 '
          'dim is fixed > 0',
        );
      }

      final raw = List<double>.filled(outputSize, 0.0).reshape(outputShape);
      _interpreter!.run(input2d, raw);

      // Robustly walk into a possibly-nested List to get the first
      // scalar. Output rank varies by build (1D, 2D, or 3D for some
      // transformers) and the previous `is List<List<double>>` check
      // was unsafe for any shape deeper than 2D.
      final modelScore = _firstScalar(raw).clamp(0.0, 1.0);
      if (kDebugMode && (modelScore - heuristic).abs() > 0.2) {
        debugPrint(
          '[RiskModel][A/B] model=${modelScore.toStringAsFixed(3)} '
          'heuristic=${heuristic.toStringAsFixed(3)} delta=${(modelScore - heuristic).toStringAsFixed(3)}',
        );
      }
      return RiskInference(
        modelScore: modelScore,
        heuristicScore: heuristic,
        usedModel: true,
        at: DateTime.now(),
      );
    } catch (e) {
      debugPrint('[RiskModel] inference error: $e');
      return RiskInference(
        modelScore: heuristic,
        heuristicScore: heuristic,
        usedModel: false,
        at: DateTime.now(),
      );
    }
  }

  /// Walk into a possibly-nested List to extract its first scalar.
  /// TFLite outputs can be 1D, 2D or 3D depending on the export
  /// format — never assume a fixed rank.
  double _firstScalar(dynamic v) {
    while (v is List) {
      if (v.isEmpty) return 0.0;
      v = v[0];
    }
    return (v is num) ? v.toDouble() : 0.0;
  }

  /// Backward-compatible scalar inference. Returns the active score
  /// (model if loaded, else heuristic).
  Future<double> infer(RiskFeatures features) async {
    final result = await inferWithCompare(features);
    return result.activeScore;
  }

  /// Phase-1 heuristic: combine a few strong signals with the same
  /// shape the trained model will eventually learn. Returns a value
  /// in [0, 1].
  ///
  /// Note: the heuristic is kept in sync with `tools/build_models_minimal.py`
  /// (which trains a model on synthetic data that mirrors these rules) so
  /// the A/B divergence between model and heuristic stays small.
  double _heuristic(RiskFeatures f) {
    double score = 0.0;

    score += f.isViolent * 0.45;
    score += f.isFast * 0.20;
    score += f.isJittery * 0.10;

    if (f.distanceFromHome > 5000 && f.lateNight > 0) {
      score += 0.20;
    } else if (f.distanceFromHome > 2000) {
      score += 0.08;
    }

    if (f.entropy > 0.4) score += 0.10;

    if (f.keywordHit > 0) score += 0.30;

    return math.max(0.0, math.min(1.0, score));
  }
}

/// Result of one inference cycle. Both the model score and the
/// heuristic score are populated so callers can compare them
/// during the A/B phase.
class RiskInference {
  final double modelScore;
  final double heuristicScore;
  final bool usedModel;
  final DateTime at;

  const RiskInference({
    required this.modelScore,
    required this.heuristicScore,
    required this.usedModel,
    required this.at,
  });

  /// The score the decision engine should use.
  double get activeScore => usedModel ? modelScore : heuristicScore;
}
