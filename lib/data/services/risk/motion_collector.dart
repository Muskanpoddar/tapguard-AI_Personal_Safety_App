// lib/data/services/risk/motion_collector.dart
//
// Phase 1 — Collects accelerometer + gyroscope at native rate (~50 Hz on
// modern phones), buffers 1-second windows, and emits a `MotionWindow`
// per second with aggregate statistics.
//
// Phase 2 will feed these windows into a TFLite Human Activity
// Recognition model. For now the engine consumes the summary stats
// (magnitude, jerk, energy) directly.

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// One second of motion data, summarized.
class MotionWindow {
  final DateTime start;
  final int sampleCount;

  // Accelerometer stats (m/s²)
  final double accelMagMean;
  final double accelMagStd;
  final double accelMagMax;
  final double accelJerk; // mean |Δmag| between samples

  // Gyroscope stats (rad/s)
  final double gyroMagMean;
  final double gyroMagMax;

  // Energy approximation (sum of squared magnitudes)
  final double accelEnergy;
  final double gyroEnergy;

  const MotionWindow({
    required this.start,
    required this.sampleCount,
    required this.accelMagMean,
    required this.accelMagStd,
    required this.accelMagMax,
    required this.accelJerk,
    required this.gyroMagMean,
    required this.gyroMagMax,
    required this.accelEnergy,
    required this.gyroEnergy,
  });

  /// A "still" window — low magnitude, low energy, low jerk.
  bool get isStationary => accelMagMean < 0.5 && accelEnergy < 1.0;

  /// A "violent shake" candidate — high magnitude + high jerk.
  bool get isViolent =>
      accelMagMax > 25.0 && accelJerk > 3.0 && gyroMagMax > 8.0;

  @override
  String toString() =>
      'MotionWindow(samples: $sampleCount, accMean: ${accelMagMean.toStringAsFixed(2)}, '
      'accMax: ${accelMagMax.toStringAsFixed(2)}, jerk: ${accelJerk.toStringAsFixed(2)}, '
      'gyroMax: ${gyroMagMax.toStringAsFixed(2)})';
}

class MotionCollector {
  MotionCollector({this.windowDuration = const Duration(seconds: 1)});

  final Duration windowDuration;

  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  final List<_Sample> _buffer = [];
  Timer? _flushTimer;
  DateTime? _windowStart;

  final _ctrl = StreamController<MotionWindow>.broadcast();
  Stream<MotionWindow> get windowStream => _ctrl.stream;

  bool _running = false;
  bool get isRunning => _running;

  void start() {
    if (_running) return;
    _running = true;
    _windowStart = DateTime.now();
    _buffer.clear();

    _accelSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 20), // ~50 Hz
    ).listen(_onAccel, onError: (e) {
      debugPrint('[MotionCollector] accel error: $e');
    });

    _gyroSub = gyroscopeEventStream(
      samplingPeriod: const Duration(milliseconds: 20),
    ).listen(_onGyro, onError: (e) {
      debugPrint('[MotionCollector] gyro error: $e');
    });

    _flushTimer = Timer.periodic(windowDuration, (_) => _flush());
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _flushTimer?.cancel();
    _flushTimer = null;
    await _accelSub?.cancel();
    await _gyroSub?.cancel();
    _accelSub = null;
    _gyroSub = null;
    _buffer.clear();
  }

  void dispose() {
    stop();
    _ctrl.close();
  }

  // ── Internal: append samples to the rolling buffer ──────────────────────
  void _onAccel(AccelerometerEvent e) {
    if (!_running) return;
    _buffer.add(_Sample(
      t: DateTime.now(),
      ax: e.x,
      ay: e.y,
      az: e.z,
      gx: 0,
      gy: 0,
      gz: 0,
    ));
  }

  void _onGyro(GyroscopeEvent e) {
    if (!_running) return;
    // Merge gyroscope into the most recent accel sample if it's
    // within the same window; otherwise add a placeholder.
    if (_buffer.isNotEmpty) {
      final last = _buffer.last;
      _buffer[_buffer.length - 1] = last.copyWith(
        gx: e.x,
        gy: e.y,
        gz: e.z,
      );
    } else {
      _buffer.add(_Sample(
        t: DateTime.now(),
        ax: 0, ay: 0, az: 0,
        gx: e.x, gy: e.y, gz: e.z,
      ));
    }
  }

  // ── Flush: compute aggregates, emit, reset ──────────────────────────────
  void _flush() {
    if (_buffer.isEmpty) {
      _windowStart = DateTime.now();
      return;
    }

    final start = _windowStart ?? DateTime.now();
    final n = _buffer.length;

    // Accelerometer magnitude stats
    final mags = List<double>.generate(n, (i) {
      final s = _buffer[i];
      return math.sqrt(s.ax * s.ax + s.ay * s.ay + s.az * s.az);
    });
    final accMean = _mean(mags);
    final accStd = _std(mags, accMean);
    final accMax = mags.reduce(math.max);

    // Jerk = mean absolute delta in magnitude
    double jerkSum = 0;
    for (int i = 1; i < mags.length; i++) {
      jerkSum += (mags[i] - mags[i - 1]).abs();
    }
    final accJerk = n > 1 ? jerkSum / (n - 1) : 0.0;

    // Gyro magnitude stats
    final gyroMags = List<double>.generate(n, (i) {
      final s = _buffer[i];
      return math.sqrt(s.gx * s.gx + s.gy * s.gy + s.gz * s.gz);
    });
    final gyroMean = _mean(gyroMags);
    final gyroMax = gyroMags.reduce(math.max);

    // Energy (sum of squares)
    final accEnergy = mags.fold<double>(0, (a, m) => a + m * m);
    final gyroEnergy = gyroMags.fold<double>(0, (a, m) => a + m * m);

    _ctrl.add(MotionWindow(
      start: start,
      sampleCount: n,
      accelMagMean: accMean,
      accelMagStd: accStd,
      accelMagMax: accMax,
      accelJerk: accJerk,
      gyroMagMean: gyroMean,
      gyroMagMax: gyroMax,
      accelEnergy: accEnergy,
      gyroEnergy: gyroEnergy,
    ));

    _buffer.clear();
    _windowStart = DateTime.now();
  }

  // ── Stats helpers ──────────────────────────────────────────────────────
  static double _mean(List<double> xs) {
    if (xs.isEmpty) return 0;
    return xs.reduce((a, b) => a + b) / xs.length;
  }

  static double _std(List<double> xs, double mean) {
    if (xs.length < 2) return 0;
    final s = xs.fold<double>(0, (a, v) => a + (v - mean) * (v - mean));
    return math.sqrt(s / (xs.length - 1));
  }
}

class _Sample {
  final DateTime t;
  final double ax, ay, az;
  final double gx, gy, gz;

  _Sample({
    required this.t,
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
  });

  _Sample copyWith({double? gx, double? gy, double? gz}) => _Sample(
        t: t,
        ax: ax,
        ay: ay,
        az: az,
        gx: gx ?? this.gx,
        gy: gy ?? this.gy,
        gz: gz ?? this.gz,
      );
}
