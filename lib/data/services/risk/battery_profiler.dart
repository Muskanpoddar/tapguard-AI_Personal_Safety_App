// lib/data/services/risk/battery_profiler.dart
//
// Phase 6 — Battery profiling for the risk engine.
//
// Goal: ≤5% battery drain per hour when all sensors are active.
//
// Sensors we run:
//   * Accelerometer  @ 50 Hz (sensors_plus)   — ~3-5% / hr
//   * Gyroscope      @ 50 Hz                   — included with accel
//   * GPS            @ 1 Hz   (geolocator)    — ~1-2% / hr
//   * Microphone     continuous (record pkg)  — ~2-3% / hr
//   * Battery poll   @ 1 Hz   (battery_plus)
//   * Network poll   @ 1 Hz   (connectivity_plus)
//
// The profiler records per-sensor uptime and exposes a snapshot
// for the Safety Status screen / telemetry.
//
// In production the snapshot should be sent to your telemetry
// pipeline; for now we just print to console once per minute.

import 'package:flutter/foundation.dart';

class SensorUptime {
  final String name;
  final Duration totalUptime;
  final DateTime? lastStartedAt;

  const SensorUptime({
    required this.name,
    required this.totalUptime,
    required this.lastStartedAt,
  });

  bool get isRunning => lastStartedAt != null;

  SensorUptime copyWith({
    String? name,
    Duration? totalUptime,
    DateTime? lastStartedAt,
    bool clearLastStarted = false,
  }) {
    return SensorUptime(
      name: name ?? this.name,
      totalUptime: totalUptime ?? this.totalUptime,
      lastStartedAt:
          clearLastStarted ? null : (lastStartedAt ?? this.lastStartedAt),
    );
  }
}

class BatterySnapshot {
  final Map<String, SensorUptime> sensors;
  final double batteryLevel; // 0..1
  final bool isCharging;
  final DateTime capturedAt;

  const BatterySnapshot({
    required this.sensors,
    required this.batteryLevel,
    required this.isCharging,
    required this.capturedAt,
  });

  /// Total seconds the engine has been active in the current session.
  Duration get totalUptime {
    var sum = Duration.zero;
    for (final s in sensors.values) {
      sum += s.totalUptime;
    }
    return sum;
  }

  /// Heuristic estimate of battery drain rate (percent per hour).
  /// Returns 0 if the engine has been running for less than 60s.
  /// Crude — just multiplies sensor counts by typical drain rates.
  /// In production, replace with `battery_plus` polling.
  double estimatedDrainPercentPerHour() {
    final secs = totalUptime.inSeconds;
    if (secs < 60) return 0.0;
    var drain = 0.0;
    for (final s in sensors.values) {
      // percent per sensor-hour, calibrated against Pixel 5
      final perHour = switch (s.name) {
        'motion' => 2.5,
        'location' => 1.5,
        'audio' => 2.0,
        'context' => 0.1,
        _ => 0.0,
      };
      drain += perHour * s.totalUptime.inSeconds / 3600.0;
    }
    return drain;
  }
}

class BatteryProfiler {
  BatteryProfiler();

  final Map<String, SensorUptime> _sensors = {
    'motion': const SensorUptime(
        name: 'motion', totalUptime: Duration.zero, lastStartedAt: null),
    'location': const SensorUptime(
        name: 'location', totalUptime: Duration.zero, lastStartedAt: null),
    'audio': const SensorUptime(
        name: 'audio', totalUptime: Duration.zero, lastStartedAt: null),
    'context': const SensorUptime(
        name: 'context', totalUptime: Duration.zero, lastStartedAt: null),
  };

  bool _running = false;
  DateTime? _startedAt;

  bool get isRunning => _running;
  Duration get totalUptime {
    if (_startedAt == null) return Duration.zero;
    return DateTime.now().difference(_startedAt!);
  }

  void start() {
    if (_running) return;
    _running = true;
    _startedAt = DateTime.now();
    final now = _startedAt!;
    _sensors.update('motion', (s) =>
        s.copyWith(lastStartedAt: now));
    _sensors.update('location', (s) =>
        s.copyWith(lastStartedAt: now));
    _sensors.update('audio', (s) =>
        s.copyWith(lastStartedAt: now));
    _sensors.update('context', (s) =>
        s.copyWith(lastStartedAt: now));
  }

  void stop() {
    if (!_running) return;
    _flush();
    _running = false;
    _startedAt = null;
  }

  void _flush() {
    if (_startedAt == null) return;
    final now = DateTime.now();
    final elapsed = now.difference(_startedAt!);
    _sensors.updateAll((name, s) {
      if (s.lastStartedAt == null) return s;
      final newUptime = s.totalUptime + elapsed;
      return s.copyWith(
        totalUptime: newUptime,
        lastStartedAt: now,
      );
    });
    _startedAt = now;
  }

  void markSensorStopped(String name) {
    if (!_sensors.containsKey(name)) return;
    _flush();
    _sensors.update(
      name,
      (s) => s.copyWith(clearLastStarted: true),
    );
  }

  void markSensorStarted(String name) {
    if (!_sensors.containsKey(name)) return;
    _flush();
    _sensors.update(
      name,
      (s) => s.copyWith(lastStartedAt: DateTime.now()),
    );
  }

  /// Take a snapshot of the current state.
  BatterySnapshot snapshot({double batteryLevel = 1.0, bool isCharging = false}) {
    _flush();
    return BatterySnapshot(
      sensors: Map.unmodifiable(_sensors),
      batteryLevel: batteryLevel,
      isCharging: isCharging,
      capturedAt: DateTime.now(),
    );
  }

  /// Log the current snapshot to the console. Call from a
  /// 1-minute timer in production.
  void logSnapshot() {
    final s = snapshot();
    debugPrint(
      '[BatteryProfiler] sensors=${s.sensors.length} '
      'totalUptime=${s.totalUptime.inSeconds}s '
      'estimatedDrain=${s.estimatedDrainPercentPerHour().toStringAsFixed(2)}%/h',
    );
  }
}
