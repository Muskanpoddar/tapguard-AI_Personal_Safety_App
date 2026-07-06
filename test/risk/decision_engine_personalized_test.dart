// test/risk/decision_engine_personalized_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tapguard/data/services/risk/baseline_store.dart';
import 'package:tapguard/data/services/risk/decision_engine.dart';
import 'package:tapguard/data/services/risk/feature_extractor.dart';
import 'package:tapguard/data/services/risk/location_collector.dart';
import 'package:tapguard/data/services/risk/risk_model.dart';
import 'package:tapguard/data/services/risk/user_baseline.dart';

UserBaselineData _readyData() {
  final now = DateTime.now();
  return UserBaselineData(
    frequentPlaces: [
      FrequentPlace(
        id: 'home',
        label: 'Home',
        lat: 12.9,
        lng: 77.6,
        radiusMeters: 100,
        visitCount: 100,
        firstSeen: now,
        lastSeen: now,
      ),
    ],
    hourlyProfiles: List.generate(
      24,
      (h) => HourlyMotionProfile(
        hour: h,
        typicalSpeed: 1.0,
        typicalEntropy: 0.05,
        sampleCount: 50,
      ),
    ),
    totalSamples: 500,
    updatedAt: now,
  );
}

LocationSample _sample({double lat = 12.9, double lng = 77.6, double speed = 0}) {
  return LocationSample(
    at: DateTime.now(),
    lat: lat,
    lng: lng,
    speed: speed,
    accuracy: 5,
    distanceFromHome: 0,
    distanceFromNearestFrequent: 0,
    entropy: 0,
  );
}

void main() {
  group('DecisionEngine (personalized anomaly)', () {
    test('anomaly is computed from the baseline when ready', () async {
      final baseline = UserBaseline();
      baseline.seedForTest(_readyData());
      final engine = DecisionEngine(
        model: RiskModel(heuristicOnly: true),
        baseline: baseline,
      );
      final features = RiskFeatures.neutral;

      // 1) Typical sample near home → low total
      final r1 = await engine.decide(
        features: features,
        motion: null,
        keywordConfidence: 0,
        location: _sample(lat: 12.9001, lng: 77.6001),
      );
      expect(r1.score, lessThan(0.5));

      // 2) Very far from home + high speed → much higher
      final r2 = await engine.decide(
        features: features,
        motion: null,
        keywordConfidence: 0,
        location: _sample(lat: 13.7, lng: 78.5, speed: 25.0),
      );
      expect(r2.score, greaterThan(r1.score));
      expect(r2.factors['baseline_ready'], true);
    });

    test('cold-start baseline still works (uses feature-only anomaly)',
        () async {
      final baseline = UserBaseline();
      // No seedForTest — fresh baseline, not ready
      final engine = DecisionEngine(
        model: RiskModel(heuristicOnly: true),
        baseline: baseline,
      );
      final result = await engine.decide(
        features: RiskFeatures.neutral,
        motion: null,
        keywordConfidence: 0,
        location: _sample(),
      );
      expect(result.factors['baseline_ready'], false);
      expect(result.score, inInclusiveRange(0.0, 1.0));
    });
  });
}
