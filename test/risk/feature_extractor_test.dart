// test/risk/feature_extractor_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tapguard/data/services/risk/context_collector.dart';
import 'package:tapguard/data/services/risk/feature_extractor.dart';
import 'package:tapguard/data/services/risk/motion_collector.dart';

ContextSnapshot _ctx({DateTime? at}) => ContextSnapshot(
      at: at ?? DateTime(2026, 1, 1, 14, 30),
      hourSin: 0,
      hourCos: 1,
      dowSin: 0,
      dowCos: 1,
      batteryLevel: 0.8,
      isCharging: false,
      isOnline: true,
      isOnWifi: true,
      isOnCellular: false,
    );

MotionWindow _motion({
  double mean = 9.8,
  double std = 0.0,
  double max = 9.8,
  double jerk = 0.0,
  double accEnergy = 96.0,
  double gyroMax = 0.0,
  double gyroMean = 0.0,
  double gyroEnergy = 0.0,
  int n = 50,
}) =>
    MotionWindow(
      start: DateTime.now(),
      sampleCount: n,
      accelMagMean: mean,
      accelMagStd: std,
      accelMagMax: max,
      accelJerk: jerk,
      gyroMagMean: gyroMean,
      gyroMagMax: gyroMax,
      accelEnergy: accEnergy,
      gyroEnergy: gyroEnergy,
    );

void main() {
  group('FeatureExtractor', () {
    test('feature count matches the model input size', () {
      final fx = FeatureExtractor().build(
        motion: null,
        location: null,
        context: _ctx(),
        keywordHit: 0,
      );
      expect(fx.toList().length, RiskFeatures.expectedCount);
    });

    test('isStationary flips on near-zero motion', () {
      final fx = FeatureExtractor().build(
        motion: _motion(mean: 0.2, accEnergy: 0.5),
        location: null,
        context: _ctx(),
        keywordHit: 0,
      );
      expect(fx.isStationary, 1.0);
    });

    test('isViolent flags high max + high jerk + high gyro', () {
      final fx = FeatureExtractor().build(
        motion: _motion(max: 30, jerk: 5, gyroMax: 10),
        location: null,
        context: _ctx(),
        keywordHit: 0,
      );
      expect(fx.isViolent, 1.0);
    });

    test('lateNight flag is on between 22:00 and 05:00', () {
      final night = _ctx(at: DateTime(2026, 1, 1, 2, 0));
      final day = _ctx(at: DateTime(2026, 1, 1, 14, 0));
      final fxNight = FeatureExtractor().build(
        motion: null, location: null, context: night, keywordHit: 0,
      );
      final fxDay = FeatureExtractor().build(
        motion: null, location: null, context: day, keywordHit: 0,
      );
      expect(fxNight.lateNight, 1.0);
      expect(fxDay.lateNight, 0.0);
    });

    test('keyword hit propagates', () {
      final fx = FeatureExtractor().build(
        motion: null,
        location: null,
        context: _ctx(),
        keywordHit: 0.92,
      );
      expect(fx.keywordHit, closeTo(0.92, 0.001));
    });
  });
}
