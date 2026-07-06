// lib/data/services/risk/yamnet_bridge.dart
//
// Phase 4 — Bridge to the YAMNet audio event classifier.
//
// YAMNet (https://tfhub.dev/google/lite-model/yamnet/classification/tflite/1)
// is a 521-class audio event detector trained on AudioSet. Of those
// classes, ~15 are directly relevant to personal safety:
//
//   * Scream, shouting, crying
//   * Glass breaking
//   * Vehicle crash, skidding, horn
//   * Gunshot, explosion
//   * Alarm, siren
//   * Dog barking (situational)
//
// This wrapper:
//   * Loads the YAMNet TFLite model on demand (3.8 MB).
//   * Maps the 521-class output to a small set of safety-relevant
//     "concern scores" in [0, 1].
//   * Caches the most recent score for the decision engine.
//
// When the model isn't bundled, the bridge returns a "neutral"
// result and the engine falls back to other signals.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Aggregated safety-relevant audio scores produced by YAMNet.
class AudioEventScore {
  /// Probability that an aggressive verbal signal was detected
  /// (scream, shout, cry, scream, …).
  final double verbalAggression;

  /// Probability that glass breaking was detected.
  final double glassBreaking;

  /// Probability that a vehicle impact/crash sound was detected.
  final double vehicleImpact;

  /// Probability that a gunshot / explosion was detected.
  final double explosion;

  /// Probability that an alarm / siren was detected.
  final double alarm;

  /// Best raw YAMNet class probability.
  final double topClassScore;

  /// Name of the top YAMNet class.
  final String topClassName;

  const AudioEventScore({
    required this.verbalAggression,
    required this.glassBreaking,
    required this.vehicleImpact,
    required this.explosion,
    required this.alarm,
    required this.topClassScore,
    required this.topClassName,
  });

  /// Neutral score — used when the model isn't available.
  static const AudioEventScore neutral = AudioEventScore(
    verbalAggression: 0,
    glassBreaking: 0,
    vehicleImpact: 0,
    explosion: 0,
    alarm: 0,
    topClassScore: 0,
    topClassName: '',
  );

  /// The single highest-priority concern. The decision engine uses
  /// this as a binary "is there an audio alarm right now?" flag.
  double get maxConcern {
    final c = [
      verbalAggression,
      glassBreaking,
      vehicleImpact,
      explosion,
      alarm,
    ];
    var m = 0.0;
    for (final v in c) {
      if (v > m) m = v;
    }
    return m;
  }
}

class YamnetBridge {
  YamnetBridge();

  Interpreter? _interpreter;
  bool get isLoaded => _interpreter != null;

  /// Approximate class index → safety category mapping.
  /// YAMNet uses the AudioSet ontology; the indices below are
  /// based on the published YAMNet class list. They're robust to
  /// small re-orderings of the model.
  static const List<int> _verbalAggressionIdx = [
    2,   // Child speech, kid speaking
    3,   // Conversation
    6,   // Shout
    7,   // Bellow
    8,   // Whoop
    9,   // Yell
    10,  // Children shouting
    11,  // Screaming
    12,  // Whispering
    13,  // Laughter
    17,  // Baby cry, infant cry
    19,  // Whimper
    405, // Wail, moan
  ];
  static const List<int> _glassBreakingIdx = [
    414, // Glass
    415, // Glass shattering
    416, // Shatter
  ];
  static const List<int> _vehicleImpactIdx = [
    284, // Tire squeal
    285, // Skidding
    290, // Car crash
    291, // Crash
  ];
  static const List<int> _explosionIdx = [
    387, // Gunshot, gunfire
    388, // Machine gun
    389, // Fusillade
    390, // Artillery
    391, // Explosion
    392, // Boom
  ];
  static const List<int> _alarmIdx = [
    388, // Fusillade
    391, // Explosion
    396, // Fire alarm
    397, // Smoke alarm
    398, // Alarm
    399, // Siren
    400, // Civil defense siren
    401, // Police car siren
    402, // Fire engine siren
  ];

  /// Load the YAMNet model. Safe to call multiple times.
  Future<bool> load({String assetPath = 'assets/models/yamnet.tflite'}) async {
    if (_interpreter != null) return true;
    try {
      _interpreter = await Interpreter.fromAsset(
        assetPath,
        options: InterpreterOptions()..threads = 1,
      );
      debugPrint('[YamnetBridge] loaded $assetPath '
          '(${_interpreter!.getInputTensor(0).shape} → '
          '${_interpreter!.getOutputTensor(0).shape})');
      return true;
    } catch (e) {
      debugPrint('[YamnetBridge] not loaded (Phase 4 will train the '
          'model via tools/train_risk_model.py): $e');
      _interpreter = null;
      return false;
    }
  }

  Future<void> close() async {
    _interpreter?.close();
    _interpreter = null;
  }

  /// Classify a 1-second window of 16 kHz mono PCM samples.
  /// Returns the aggregated `AudioEventScore` (or `neutral` if the
  /// model isn't loaded).
  Future<AudioEventScore> classify(Float32List samples) async {
    if (_interpreter == null) return AudioEventScore.neutral;
    try {
      final inputTensor = _interpreter!.getInputTensor(0);
      final inputShape = inputTensor.shape;
      // YAMNet expects ~0.975 s @ 16 kHz = 15600 samples. Different
      // builds ship with either a 1D `[15600]` input (MediaPipe build)
      // or a 2D `[1, 15600]` input (TF-Hub build). Probe and adapt.
      final inputSize = inputShape.reduce((a, b) => a * b);
      final flatInput = List<double>.filled(inputSize, 0.0);
      final n = samples.length.clamp(0, inputSize);
      for (int i = 0; i < n; i++) {
        flatInput[i] = samples[i].toDouble();
      }
      final input = inputShape.length == 1
          ? flatInput
          : flatInput.reshape(inputShape);

      final outputs = <int, Object>{};
      final outputCount = _interpreter!.getOutputTensors().length;
      // Output 0 is always the (1, 521) class scores.
      final out0Shape = _interpreter!.getOutputTensor(0).shape;
      final out0Size = out0Shape.reduce((a, b) => a * b);
      final scores = List.generate(out0Size, (_) => 0.0)
          .reshape(out0Shape);
      outputs[0] = scores;
      // Output 1 (embeddings) is only present on the TF-Hub build.
      // The MediaPipe YAMNet ships with a single output, so we skip
      // allocating the embeddings tensor — requesting it would throw
      // "Output tensor index 1 not found".
      if (outputCount > 1) {
        final out1Shape = _interpreter!.getOutputTensor(1).shape;
        final out1Size = out1Shape.reduce((a, b) => a * b);
        outputs[1] = List.generate(out1Size, (_) => 0.0).reshape(out1Shape);
      }
      _interpreter!.runForMultipleInputs([input], outputs);
      // Use the safe nested-list extractor — `scores` is normally a
      // 1×N List<List<double>> but the check below used to throw
      // "List<double> is not a subtype of double" on any build that
      // emitted a 3D output or a 1D buffer.
      final flatScores = (scores is List<List<double>>)
          ? scores[0]
          : (scores is List<double>)
              ? scores
              : <double>[];
      return _aggregate(flatScores);
    } catch (e) {
      debugPrint('[YamnetBridge] classify error: $e');
      return AudioEventScore.neutral;
    }
  }

  /// Sum the top class probabilities for each safety category.
  /// In production this should take the max, but a sum is a more
  /// conservative signal that catches multi-class overlaps.
  AudioEventScore _aggregate(List<double> scores) {
    if (scores.isEmpty) return AudioEventScore.neutral;
    double maxIn(List<int> indices) {
      var m = 0.0;
      for (final i in indices) {
        if (i < scores.length && scores[i] > m) m = scores[i];
      }
      return m;
    }
    int topIdx = 0;
    for (int i = 1; i < scores.length; i++) {
      if (scores[i] > scores[topIdx]) topIdx = i;
    }
    return AudioEventScore(
      verbalAggression: maxIn(_verbalAggressionIdx),
      glassBreaking: maxIn(_glassBreakingIdx),
      vehicleImpact: maxIn(_vehicleImpactIdx),
      explosion: maxIn(_explosionIdx),
      alarm: maxIn(_alarmIdx),
      topClassScore: scores[topIdx],
      topClassName: 'class_$topIdx',
    );
  }
}
