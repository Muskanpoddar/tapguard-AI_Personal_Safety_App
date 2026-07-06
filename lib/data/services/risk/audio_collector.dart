// lib/data/services/risk/audio_collector.dart
//
// Phase 2 — Streams the microphone via the `record` package at 16 kHz
// mono PCM and feeds a rolling 1-second window through a small
// "keyword spotter" TFLite model. When a wake word (default: "help",
// "stop", "danger") is detected, a `KeywordHit` is emitted and a
// 10-second audio analysis window is opened for YAMNet (Phase 4).
//
// When `assets/models/keyword_spotter.tflite` isn't present, the
// collector runs without inference (no hits emitted) and the rest
// of the engine falls back to motion + location + time signals.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'yamnet_bridge.dart';

/// Result of a successful wake-word detection.
class KeywordHit {
  final String keyword;
  final double confidence;
  final DateTime at;

  const KeywordHit({
    required this.keyword,
    required this.confidence,
    required this.at,
  });

  @override
  String toString() =>
      'KeywordHit($keyword @ ${confidence.toStringAsFixed(2)} at $at)';
}

class AudioCollector {
  AudioCollector({
    this.sampleRate = 16000,
    this.windowDuration = const Duration(seconds: 1),
  });

  final int sampleRate;
  final Duration windowDuration;

  // Pre-roll: how long to keep audio after a hit so YAMNet has context
  static const Duration _postHitWindow = Duration(seconds: 10);

  // Keyword labels — must match the order of the model's softmax output
  static const List<String> _keywordLabels = [
    'silence',
    'help',
    'stop',
    'danger',
  ];
  // Minimum softmax confidence required to count as a hit
  static const double _hitThreshold = 0.75;

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;
  Timer? _flushTimer;

  // Rolling 1-second window of PCM samples
  final List<int> _windowPcm = [];
  DateTime? _hitUntil; // if non-null, we're in a post-hit analysis window

  Interpreter? _kwModel;
  bool get modelLoaded => _kwModel != null;

  final _keywordCtrl = StreamController<KeywordHit>.broadcast();
  final _audioCtrl = StreamController<Uint8List>.broadcast();
  final _audioScoreCtrl = StreamController<AudioEventScore>.broadcast();

  Stream<KeywordHit> get keywordStream => _keywordCtrl.stream;
  Stream<Uint8List> get analysisStream => _audioCtrl.stream;
  /// Phase 4 — fires on every YAMNet classification (currently once
  /// per second while in a post-hit window).
  Stream<AudioEventScore> get audioScoreStream => _audioScoreCtrl.stream;
  bool _running = false;
  bool get isRunning => _running;

  // Phase 4 — YAMNet bridge. Loaded on demand.
  final YamnetBridge yamnet = YamnetBridge();
  bool get yamnetLoaded => yamnet.isLoaded;
  AudioEventScore _latestAudioScore = AudioEventScore.neutral;
  AudioEventScore get latestAudioScore => _latestAudioScore;

  /// Words the spotter listens for. Read-only for now (the user can
  /// disable individual keywords in Privacy settings — coming in a
  /// later phase).
  List<String> get activeKeywords =>
      _keywordLabels.where((k) => k != 'silence').toList();

  /// Try to load the keyword spotter model. Safe to call before
  /// [start] — if the model is missing, [modelLoaded] is `false` and
  /// no hits will ever be emitted.
  Future<bool> loadKeywordModel({
    String assetPath = 'assets/models/keyword_spotter.tflite',
  }) async {
    try {
      _kwModel = await Interpreter.fromAsset(
        assetPath,
        options: InterpreterOptions()..threads = 1,
      );
      final inShape = _kwModel!.getInputTensor(0).shape;
      final outShape = _kwModel!.getOutputTensor(0).shape;
      debugPrint('[AudioCollector] keyword model loaded: $assetPath '
          '($inShape → $outShape)');
      // Defensive: if the output tensor has a 0-rank dim the
      // interpreter's `run` validation will reject every output
      // buffer we try to allocate. The previous build had output
      // shape [0, 4] (batch=0 dynamic) — exploded every 1s and
      // tripped the ANR watchdog. Detect that case up-front so we
      // never even try to run the model.
      if (outShape.contains(0)) {
        _kwModel!.close();
        _kwModel = null;
        debugPrint('[AudioCollector] keyword model has degenerate output '
            'shape $outShape — keyword detection disabled for this '
            'session (replace assets/models/keyword_spotter.tflite with '
            'a model whose output rank-0 dim is fixed > 0)');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('[AudioCollector] keyword model not available '
          '(collector will run without keyword detection): $e');
      _kwModel = null;
      return false;
    }
  }

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<bool> start() async {
    if (_running) return true;
    final granted = await _recorder.hasPermission();
    if (!granted) {
      debugPrint('[AudioCollector] mic permission denied');
      return false;
    }
    try {
      final stream = await _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
        ),
      );
      _sub = stream.listen(_onPcm, onError: (e) {
        debugPrint('[AudioCollector] stream error: $e');
      });
      _flushTimer = Timer.periodic(windowDuration, (_) => _flush());
      _running = true;
      return true;
    } catch (e) {
      debugPrint('[AudioCollector] start failed: $e');
      return false;
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _flushTimer?.cancel();
    _flushTimer = null;
    await _sub?.cancel();
    _sub = null;
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
    _windowPcm.clear();
    _hitUntil = null;
  }

  Future<void> close() async {
    await stop();
    _kwModel?.close();
    _kwModel = null;
    await yamnet.close();
    _keywordCtrl.close();
    _audioCtrl.close();
    _audioScoreCtrl.close();
  }

  // ── Internal: ingest PCM, flush every 1s ──────────────────────────────
  void _onPcm(Uint8List bytes) {
    if (!_running) return;
    // Append 16-bit PCM samples (little-endian)
    for (int i = 0; i + 1 < bytes.length; i += 2) {
      final s = bytes[i] | (bytes[i + 1] << 8);
      _windowPcm.add(s);
    }
  }

  void _flush() {
    if (_windowPcm.isEmpty) return;

    // Always forward the raw PCM during a post-hit window
    final inPostHit =
        _hitUntil != null && DateTime.now().isBefore(_hitUntil!);
    if (inPostHit) {
      final out = Uint8List(_windowPcm.length * 2);
      final bd = ByteData.view(out.buffer);
      for (int i = 0; i < _windowPcm.length; i++) {
        bd.setInt16(i * 2, _windowPcm[i], Endian.little);
      }
      _audioCtrl.add(out);
    }

    // Run the keyword model on the rolling window
    if (_kwModel != null) {
      try {
        final input = _prepareInput();
        final outputShape = _kwModel!.getOutputTensor(0).shape;
        final outputSize = outputShape.reduce((a, b) => a * b);
        if (outputSize <= 0) {
          // Defensive — same shape-degenerate case as above. Auto-
          // disable so we stop emitting the error every 1s tick.
          _kwModel!.close();
          _kwModel = null;
          throw FormatException(
            'keyword_spotter output shape is degenerate; model disabled',
          );
        }
        final raw = List<double>.filled(outputSize, 0.0).reshape(outputShape);
        _kwModel!.run(input, raw);
        // Robust first-scalar walk — output rank can be 1D/2D/3D.
        final double firstProb = _firstScalar(raw);
        final flat = (raw is List<List<double>>)
            ? raw[0]
            : (raw is List<double>)
                ? raw
                : <double>[firstProb];
        if (flat.length != _keywordLabels.length) {
          debugPrint(
            '[AudioCollector] keyword model output size '
            '${flat.length} != labels ${_keywordLabels.length}',
          );
          return;
        }
        _maybeEmitHit(flat);
      } catch (e) {
        debugPrint('[AudioCollector] keyword inference error: $e');
      }
    }

    // Run YAMNet on the rolling window during a post-hit window
    if (inPostHit && yamnet.isLoaded) {
      _runYamnetAsync();
    }

    _windowPcm.clear();
  }

  /// Run YAMNet in the background and emit the result on the score
  /// stream. The 35-feature vector fed to the risk model includes
  /// the latest `AudioEventScore`.
  Future<void> _runYamnetAsync() async {
    try {
      final n = _windowPcm.length;
      final input = Float32List(n);
      for (int i = 0; i < n; i++) {
        input[i] = _windowPcm[i] / 32768.0;
      }
      final score = await yamnet.classify(input);
      _latestAudioScore = score;
      _audioScoreCtrl.add(score);
    } catch (e) {
      debugPrint('[AudioCollector] YAMNet inference error: $e');
    }
  }

  /// Prepare a [1, sampleRate, 1] float32 input from the rolling PCM
  /// window. Pads with zeros or truncates to exactly `sampleRate`
  /// samples. Returns a 3D tensor so it matches the keyword-spotter
  /// Conv1D input shape `[batch, time, channels]`.
  List<List<List<double>>> _prepareInput() {
    final samples = List<double>.filled(sampleRate, 0.0);
    final n = _windowPcm.length.clamp(0, sampleRate);
    for (int i = 0; i < n; i++) {
      // Normalize int16 to [-1, 1]
      samples[i] = _windowPcm[i] / 32768.0;
    }
    return [
      [samples],
    ];
  }

  void _maybeEmitHit(List<double> probs) {
    if (probs.length != _keywordLabels.length) {
      debugPrint(
        '[AudioCollector] keyword model output size '
        '${probs.length} != labels ${_keywordLabels.length}',
      );
      return;
    }
    int bestIdx = 0;
    double bestVal = probs[0];
    for (int i = 1; i < probs.length; i++) {
      if (probs[i] > bestVal) {
        bestVal = probs[i];
        bestIdx = i;
      }
    }
    if (bestIdx == 0) return; // silence
    if (bestVal < _hitThreshold) return;
    final keyword = _keywordLabels[bestIdx];
    _hitUntil = DateTime.now().add(_postHitWindow);
    _keywordCtrl.add(KeywordHit(
      keyword: keyword,
      confidence: bestVal,
      at: DateTime.now(),
    ));
    if (kDebugMode) {
      debugPrint('[AudioCollector] keyword hit: $keyword '
          '(${(bestVal * 100).toStringAsFixed(1)}%)');
    }
  }

  /// Public hook for tests to simulate a hit.
  void publishHit(String keyword, double confidence) {
    _hitUntil = DateTime.now().add(_postHitWindow);
    _keywordCtrl.add(KeywordHit(
      keyword: keyword,
      confidence: confidence,
      at: DateTime.now(),
    ));
  }

  /// Walk into a possibly-nested List to extract its first scalar.
  /// Defensive helper for TFLite outputs whose rank we can't predict.
  double _firstScalar(dynamic v) {
    while (v is List) {
      if (v.isEmpty) return 0.0;
      v = v[0];
    }
    return (v is num) ? v.toDouble() : 0.0;
  }
}
