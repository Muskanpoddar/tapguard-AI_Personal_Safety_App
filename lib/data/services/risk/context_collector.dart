// lib/data/services/risk/context_collector.dart
//
// Phase 1 — Provides low-frequency context used by the risk model:
//   * time of day (cyclical)
//   * day of week
//   * battery level
//   * charging state
//   * network type (WiFi / cellular / none)
//
// Refreshes once per second to keep the feature vector in sync with
// the motion + location streams.

import 'dart:async';
import 'dart:math' as math;
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class ContextSnapshot {
  final DateTime at;

  // Time of day (cyclical sin/cos for hour 0-23)
  final double hourSin;
  final double hourCos;

  // Day of week (cyclical sin/cos for 0-6)
  final double dowSin;
  final double dowCos;

  // Battery
  final double batteryLevel; // 0..1
  final bool isCharging;

  // Network
  final bool isOnline;
  final bool isOnWifi;
  final bool isOnCellular;

  const ContextSnapshot({
    required this.at,
    required this.hourSin,
    required this.hourCos,
    required this.dowSin,
    required this.dowCos,
    required this.batteryLevel,
    required this.isCharging,
    required this.isOnline,
    required this.isOnWifi,
    required this.isOnCellular,
  });

  @override
  String toString() =>
      'Context(hour: ${(math.atan2(hourSin, hourCos) * 180 / math.pi / 15).toStringAsFixed(1)}, '
      'battery: ${(batteryLevel * 100).toStringAsFixed(0)}%, '
      'charging: $isCharging, online: $isOnline)';
}

class ContextCollector {
  ContextCollector();

  final Battery _battery = Battery();
  final Connectivity _connectivity = Connectivity();

  ContextSnapshot _last = _neutral();
  Timer? _timer;

  bool _running = false;
  bool get isRunning => _running;

  /// Last fetched snapshot (always available, even before [start]).
  ContextSnapshot get last => _last;

  Future<void> start({Duration interval = const Duration(seconds: 1)}) async {
    if (_running) return;
    _running = true;
    await _refresh();
    _timer = Timer.periodic(interval, (_) => _refresh());
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stop();
  }

  Future<void> _refresh() async {
    try {
      final batt = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      final conn = await _connectivity.checkConnectivity();
      final isOnline = !conn.contains(ConnectivityResult.none);
      final isOnWifi = conn.contains(ConnectivityResult.wifi);
      final isOnCellular = conn.contains(ConnectivityResult.mobile);

      final now = DateTime.now();
      final hour = now.hour + now.minute / 60.0;
      final dow = now.weekday; // 1..7 (Mon..Sun) — convert to 0..6
      final dow0 = dow == 7 ? 0 : dow;

      _last = ContextSnapshot(
        at: now,
        hourSin: math.sin(2 * math.pi * hour / 24),
        hourCos: math.cos(2 * math.pi * hour / 24),
        dowSin: math.sin(2 * math.pi * dow0 / 7),
        dowCos: math.cos(2 * math.pi * dow0 / 7),
        batteryLevel: (batt / 100).clamp(0.0, 1.0),
        isCharging: state == BatteryState.charging ||
            state == BatteryState.full ||
            state == BatteryState.connectedNotCharging,
        isOnline: isOnline,
        isOnWifi: isOnWifi,
        isOnCellular: isOnCellular,
      );
    } catch (e) {
      // If battery/connectivity calls fail, keep the previous snapshot.
    }
  }

  static ContextSnapshot _neutral() {
    final now = DateTime.now();
    return ContextSnapshot(
      at: now,
      hourSin: 0,
      hourCos: 1,
      dowSin: 0,
      dowCos: 1,
      batteryLevel: 1.0,
      isCharging: false,
      isOnline: true,
      isOnWifi: false,
      isOnCellular: false,
    );
  }
}
