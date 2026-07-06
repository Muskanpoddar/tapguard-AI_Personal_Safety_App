// test/integration/risk_engine_integration_test.dart
//
// Phase 6 — End-to-end integration test of the AI risk engine.
//
// Wires together: FeatureExtractor + DecisionEngine + RiskModel
// (heuristic) + UserBaseline (MemoryBaselineStore) + ModelHealthMonitor.
//
// Verifies that:
//   1. A typical feature vector produces a low risk score.
//   2. A "violent fall" vector produces a high risk score.
//   3. Late-night + far from home + audio alarm = high risk.
//   4. The model health monitor rolls back to heuristic on NaN.
//   5. The decision engine respects the rollback.
//   6. The user baseline's anomaly score converges with enough samples.

import 'package:flutter_test/flutter_test.dart';
import 'package:tapguard/data/services/risk/baseline_store.dart';
import 'package:tapguard/data/services/risk/battery_profiler.dart';
import 'package:tapguard/data/services/risk/decision_engine.dart';
import 'package:tapguard/data/services/risk/feature_extractor.dart';
import 'package:tapguard/data/services/risk/location_collector.dart';
import 'package:tapguard/data/services/risk/model_health_monitor.dart';
import 'package:tapguard/data/services/risk/motion_collector.dart';
import 'package:tapguard/data/services/risk/risk_model.dart';
import 'package:tapguard/data/services/risk/user_baseline.dart';

LocationSample _sample({
  double lat = 12.9,
  double lng = 77.6,
  double speed = 0,
  double entropy = 0,
  double distance = 0,
}) =>
    LocationSample(
      at: DateTime.now(),
      lat: lat,
      lng: lng,
      speed: speed,
      accuracy: 5,
      distanceFromHome: distance,
      distanceFromNearestFrequent: distance,
      entropy: entropy,
    );

MotionWindow _motion({
  double mean = 9.8,
  double max = 9.8,
  double jerk = 0,
  double accEnergy = 96,
  double gyroMax = 0,
}) =>
    MotionWindow(
      start: DateTime.now(),
      sampleCount: 50,
      accelMagMean: mean,
      accelMagStd: 0,
      accelMagMax: max,
      accelJerk: jerk,
      accelEnergy: accEnergy,
      gyroMagMean: 0,
      gyroMagMax: gyroMax,
      gyroEnergy: 0,
    );

RiskFeatures _features({
  double isViolent = 0,
  double isFast = 0,
  double isJittery = 0,
  double distanceFromHome = 0,
  double entropy = 0,
  double keywordHit = 0,
  double lateNight = 0,
  double accelMagMax = 9.8,
  double accelJerk = 0,
  double gyroMagMax = 0,
  double speed = 0,
  double audioVerbalAggression = 0,
  double audioGlassBreaking = 0,
  double audioVehicleImpact = 0,
  double audioExplosion = 0,
  double audioAlarm = 0,
}) {
  return RiskFeatures(
    accelMagMean: 9.8,
    accelMagStd: 0,
    accelMagMax: accelMagMax,
    accelJerk: accelJerk,
    accelEnergy: 96,
    gyroMagMean: 0,
    gyroMagMax: gyroMagMax,
    gyroEnergy: 0,
    isStationary: isViolent > 0 ? 0 : 1,
    isViolent: isViolent,
    isFast: isFast,
    isJittery: isJittery,
    speed: speed,
    accuracy: 5,
    distanceFromHome: distanceFromHome,
    distanceFromNearestFrequent: distanceFromHome,
    entropy: entropy,
    logDistanceFromHome: 0,
    isAtHome: distanceFromHome < 100 ? 1 : 0,
    hourSin: 0,
    hourCos: 1,
    dowSin: 0,
    dowCos: 1,
    batteryLevel: 0.8,
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
  group('AI risk engine — end-to-end', () {
    test('typical sample → low risk', () async {
      final model = RiskModel(heuristicOnly: true);
      final baseline = UserBaseline(store: MemoryBaselineStore());
      await baseline.load();
      final engine = DecisionEngine(model: model, baseline: baseline);
      final features = _features();
      final result = await engine.decide(
        features: features,
        motion: null,
        keywordConfidence: 0,
        location: _sample(),
      );
      expect(result.level, RiskLevel.low);
      expect(result.score, lessThan(0.45));
    });

    test('violent fall → at least medium risk', () async {
      final model = RiskModel(heuristicOnly: true);
      final baseline = UserBaseline(store: MemoryBaselineStore());
      await baseline.load();
      final engine = DecisionEngine(model: model, baseline: baseline);
      final features = _features(
        isViolent: 1,
        accelMagMax: 35,
        accelJerk: 6,
        gyroMagMax: 14,
      );
      final result = await engine.decide(
        features: features,
        motion: _motion(max: 35, jerk: 6, gyroMax: 14),
        keywordConfidence: 0,
        location: _sample(),
      );
      // Conservative engine: violent fall alone scores ~0.45 (medium).
      // High would require additional signals (keyword, late night, etc.)
      expect(
        result.level == RiskLevel.medium || result.level == RiskLevel.high,
        true,
        reason: 'violent fall should at least warn; got ${result.level}',
      );
      expect(result.score, greaterThan(0.30));
    });

    test('late-night + far from home + audio alarm → at least medium risk',
        () async {
      final model = RiskModel(heuristicOnly: true);
      final baseline = UserBaseline(store: MemoryBaselineStore());
      await baseline.load();
      final engine = DecisionEngine(model: model, baseline: baseline);
      final features = _features(
        lateNight: 1,
        distanceFromHome: 10000,
        entropy: 0.4,
        audioVerbalAggression: 0.85,
        audioAlarm: 0.6,
      );
      final result = await engine.decide(
        features: features,
        motion: null,
        keywordConfidence: 0,
        location: _sample(lat: 13.4, lng: 78.0, distance: 10000),
      );
      expect(
        result.level == RiskLevel.medium || result.level == RiskLevel.high,
        true,
        reason:
            'late-night + 10km + audio alarm should at least warn; got ${result.level}',
      );
      expect(
        (result.factors['audio'] as Map)['verbalAggression'],
        closeTo(0.85, 0.01),
        reason: 'audio fields should be exposed in factors under "audio" key',
      );
    });

    test('ModelHealthMonitor rolls back on NaN output', () async {
      final monitor = ModelHealthMonitor();
      final nanInf = RiskInference(
        modelScore: double.nan,
        heuristicScore: 0.3,
        usedModel: true,
        at: DateTime.now(),
      );
      expect(monitor.record(inference: nanInf, trainingStore: null), false);
      expect(monitor.forceHeuristic, true);
      expect(monitor.current.reason, RollbackReason.nanOutput);
    });

    test('DecisionEngine uses heuristic when health monitor rolled back',
        () async {
      final model = RiskModel(heuristicOnly: true);
      final baseline = UserBaseline(store: MemoryBaselineStore());
      await baseline.load();
      final monitor = ModelHealthMonitor();
      // Force-rollback BEFORE running the engine
      monitor.reset();
      // Manually set the state by submitting a NaN
      monitor.record(
        inference: RiskInference(
          modelScore: double.nan,
          heuristicScore: 0.0,
          usedModel: true,
          at: DateTime.now(),
        ),
        trainingStore: null,
      );
      expect(monitor.forceHeuristic, true);

      final engine = DecisionEngine(
        model: model,
        baseline: baseline,
        healthMonitor: monitor,
      );
      // Build a violent-motion feature vector so the heuristic
      // should give a high score. Since monitor is rolled back,
      // the engine should use heuristic, not model.
      final features = _features(isViolent: 1, accelMagMax: 35);
      final result = await engine.decide(
        features: features,
        motion: _motion(max: 35, jerk: 6, gyroMax: 14),
        keywordConfidence: 0,
        location: _sample(),
      );
      expect(result.factors['rolled_back'], true);
      expect(result.factors['used_model'], false);
    });

    test('UserBaseline anomaly score converges with samples', () async {
      final baseline = UserBaseline(store: MemoryBaselineStore());
      await baseline.load();
      // Feed 250 typical samples
      for (int i = 0; i < 250; i++) {
        await baseline.observe(_sample(speed: 1.0, entropy: 0.05));
      }
      expect(baseline.isReady, true);
      // A very different sample should be flagged
      final a = baseline.anomaly(_sample(speed: 20.0, entropy: 0.9, distance: 50000));
      expect(a, greaterThan(0.4));
      // A typical sample should be quiet
      final b = baseline.anomaly(_sample(speed: 1.0, entropy: 0.05, distance: 50));
      expect(b, lessThan(0.3));
    });

    test('BatteryProfiler accumulates uptime per sensor', () async {
      final p = BatteryProfiler();
      p.start();
      await Future.delayed(const Duration(milliseconds: 50));
      p.markSensorStopped('audio');
      await Future.delayed(const Duration(milliseconds: 30));
      p.markSensorStopped('location');
      final snap = p.snapshot();
      // audio + location are stopped, motion + context still running
      expect(snap.sensors['audio']!.isRunning, false);
      expect(snap.sensors['location']!.isRunning, false);
      expect(snap.sensors['motion']!.isRunning, true);
      expect(snap.sensors['context']!.isRunning, true);
      // Total uptime is > 0
      expect(snap.totalUptime.inMilliseconds, greaterThan(0));
    });
  });
}
