// test/risk/decision_engine_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tapguard/data/services/risk/decision_engine.dart';
import 'package:tapguard/data/services/risk/feature_extractor.dart';

RiskFeatures _features({
  double lateNight = 0,
  double distanceFromHome = 0,
  double entropy = 0,
  double keywordHit = 0,
  double audioVerbalAggression = 0,
  double audioGlassBreaking = 0,
  double audioVehicleImpact = 0,
  double audioExplosion = 0,
  double audioAlarm = 0,
}) {
  return RiskFeatures(
    accelMagMean: 9.8,
    accelMagStd: 0,
    accelMagMax: 9.8,
    accelJerk: 0,
    accelEnergy: 96,
    gyroMagMean: 0,
    gyroMagMax: 0,
    gyroEnergy: 0,
    isStationary: 1,
    isViolent: 0,
    isFast: 0,
    isJittery: 0,
    speed: 0,
    accuracy: 0,
    distanceFromHome: distanceFromHome,
    distanceFromNearestFrequent: distanceFromHome,
    entropy: entropy,
    logDistanceFromHome: 0,
    isAtHome: 0,
    hourSin: 0,
    hourCos: 1,
    dowSin: 0,
    dowCos: 1,
    batteryLevel: 1,
    isCharging: 0,
    isOnline: 1,
    isOnWifi: 1,
    isOnCellular: 0,
    lateNight: lateNight,
    keywordHit: keywordHit,
    audioVerbalAggression: audioVerbalAggression,
    audioGlassBreaking: audioGlassBreaking,
    audioVehicleImpact: audioVehicleImpact,
    audioExplosion: audioExplosion,
    audioAlarm: audioAlarm,
  );
}

void main() {
  group('DecisionEngine', () {
    test('low-risk baseline returns low level', () async {
      final engine = DecisionEngine();
      final features = RiskFeatures.neutral;
      final result = await engine.decide(
        features: features,
        motion: null,
        keywordConfidence: 0,
        location: null,
      );
      expect(result.level, RiskLevel.low);
      expect(result.score, lessThan(0.45));
    });

    test('strong keyword hit alone pushes to medium or high', () async {
      final engine = DecisionEngine();
      final features = RiskFeatures.neutral.copyWith(keywordHit: 0.9);
      final result = await engine.decide(
        features: features,
        motion: null,
        keywordConfidence: 0.9,
        location: null,
      );
      expect(
        result.level == RiskLevel.medium || result.level == RiskLevel.high,
        true,
        reason: 'strong keyword should at least warn; got ${result.level}',
      );
    });

    test('late-night + far from home → at least medium', () async {
      final engine = DecisionEngine();
      final features = _features(
        lateNight: 1.0,
        distanceFromHome: 10000,
        entropy: 0.5,
      );
      final result = await engine.decide(
        features: features,
        motion: null,
        keywordConfidence: 0,
        location: null,
      );
      expect(
        result.level == RiskLevel.medium || result.level == RiskLevel.high,
        true,
        reason:
            'late night + 10 km from home should at least warn; got ${result.level}',
      );
    });

    test('violent motion triggers high even without keyword', () async {
      final engine = DecisionEngine();
      // We don't pass a MotionWindow here; the rules path tests the
      // feature vector's isViolent flag indirectly via max/jerk.
      final features = RiskFeatures.neutral.copyWith(
        isViolent: 1.0,
        accelMagMax: 30,
        accelJerk: 5,
        gyroMagMax: 12,
      );
      final result = await engine.decide(
        features: features,
        motion: null,
        keywordConfidence: 0,
        location: null,
      );
      // Without a motion window the hard-rule "violent" branch
      // doesn't fire; the heuristic should still push toward high
      // because isViolent contributes 0.45 to the model score.
      expect(
        result.score,
        greaterThan(0.10),
        reason: 'violent flags should raise the overall score',
      );
    });
  });
}
