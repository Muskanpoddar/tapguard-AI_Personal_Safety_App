// test/risk/battery_profiler_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tapguard/data/services/risk/battery_profiler.dart';

void main() {
  group('BatteryProfiler', () {
    test('starts and stops cleanly', () {
      final p = BatteryProfiler();
      expect(p.isRunning, false);
      p.start();
      expect(p.isRunning, true);
      p.stop();
      expect(p.isRunning, false);
    });

    test('snapshot contains all four sensors', () {
      final p = BatteryProfiler();
      p.start();
      final snap = p.snapshot();
      expect(snap.sensors.keys, containsAll(['motion', 'location', 'audio', 'context']));
    });

    test('total uptime grows over time', () async {
      final p = BatteryProfiler();
      p.start();
      await Future.delayed(const Duration(milliseconds: 50));
      final snap = p.snapshot();
      expect(snap.totalUptime.inMilliseconds, greaterThan(30));
      p.stop();
    });

    test('estimated drain is 0 for short uptimes', () {
      final p = BatteryProfiler();
      p.start();
      final snap = p.snapshot();
      // < 60s → no estimate yet
      expect(snap.estimatedDrainPercentPerHour(), 0.0);
    });

    test('markSensorStarted / markSensorStopped tracks state', () {
      final p = BatteryProfiler();
      p.start();
      p.markSensorStopped('audio');
      expect(p.snapshot().sensors['audio']!.isRunning, false);
      p.markSensorStarted('audio');
      expect(p.snapshot().sensors['audio']!.isRunning, true);
    });
  });
}
