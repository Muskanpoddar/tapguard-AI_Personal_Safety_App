// test/risk/user_baseline_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tapguard/data/services/risk/baseline_store.dart';
import 'package:tapguard/data/services/risk/location_collector.dart';
import 'package:tapguard/data/services/risk/user_baseline.dart';

LocationSample _sample({
  double speed = 0,
  double distance = 0,
  double entropy = 0,
  double lat = 12.9,
  double lng = 77.6,
  DateTime? at,
}) =>
    LocationSample(
      at: at ?? DateTime.now(),
      lat: lat,
      lng: lng,
      speed: speed,
      accuracy: 5,
      distanceFromHome: distance,
      distanceFromNearestFrequent: distance,
      entropy: entropy,
    );

UserBaselineData _seedData({
  int totalSamples = 250,
  double homeSpeed = 1.0,
  double homeEntropy = 0.05,
  double homeLat = 12.9,
  double homeLng = 77.6,
}) {
  final now = DateTime.now();
  return UserBaselineData(
    frequentPlaces: [
      FrequentPlace(
        id: 'home',
        label: 'Home',
        lat: homeLat,
        lng: homeLng,
        radiusMeters: 100,
        visitCount: 50,
        firstSeen: now,
        lastSeen: now,
      ),
    ],
    hourlyProfiles: List.generate(
      24,
      (h) => HourlyMotionProfile(
        hour: h,
        typicalSpeed: homeSpeed,
        typicalEntropy: homeEntropy,
        sampleCount: 50,
      ),
    ),
    totalSamples: totalSamples,
    updatedAt: now,
  );
}

void main() {
  group('UserBaseline (Phase 3 — personalized)', () {
    test('cold start: not ready until enough samples', () {
      final b = UserBaseline();
      expect(b.isReady, false);
    });

    test('seeding test data makes the baseline ready', () {
      final b = UserBaseline();
      b.seedForTest(_seedData());
      expect(b.isReady, true);
      expect(b.totalSamples, 250);
    });

    test('anomaly is zero for a typical sample when ready', () {
      final b = UserBaseline();
      b.seedForTest(_seedData());
      final a = b.anomaly(_sample(
        speed: 1.1,
        entropy: 0.06,
        lat: 12.9001,
        lng: 77.6001,
      ));
      expect(a, lessThan(0.2));
    });

    test('anomaly is high for an unusual sample when ready', () {
      final b = UserBaseline();
      b.seedForTest(_seedData());
      final a = b.anomaly(_sample(
        speed: 25.0,
        entropy: 0.9,
        lat: 13.5, // ~70 km from home
        lng: 78.0,
      ));
      expect(a, greaterThan(0.5));
    });

    test('MemoryBaselineStore round-trips baseline data', () async {
      final store = MemoryBaselineStore();
      await store.open();
      final data = _seedData(totalSamples: 300);
      await store.save(data);
      final loaded = await store.load();
      expect(loaded.totalSamples, 300);
      expect(loaded.frequentPlaces.length, 1);
      expect(loaded.frequentPlaces.first.label, 'Home');
      await store.close();
    });

    test('observe() adds a new frequent place after enough visits', () async {
      final b = UserBaseline();
      await b.load();
      // Drop 10 samples in the same grid cell — should create a
      // frequent place.
      for (int i = 0; i < 10; i++) {
        await b.observe(_sample(
          lat: 12.91,
          lng: 77.61,
          speed: 0.5,
          entropy: 0.05,
        ));
      }
      expect(b.frequentPlaces.length, greaterThanOrEqualTo(1));
      expect(b.frequentPlaces.first.label, isNotEmpty);
      expect(b.totalSamples, 10);
    });

    test('observe() evicts least-visited place when at the cap', () async {
      final b = UserBaseline();
      await b.load();
      // Build up 5 different grid cells (the cap)
      for (int p = 0; p < 5; p++) {
        for (int i = 0; i < 5; i++) {
          await b.observe(_sample(
            lat: 12.9 + (p * 0.01),
            lng: 77.6 + (p * 0.01),
            speed: 1.0,
            entropy: 0.05,
          ));
        }
      }
      expect(b.frequentPlaces.length, lessThanOrEqualTo(5));
    });

    test('observe() updates hourly profile', () async {
      final b = UserBaseline();
      await b.load();
      final at = DateTime(2026, 1, 1, 14, 30);
      for (int i = 0; i < 30; i++) {
        await b.observe(_sample(
          speed: 1.5,
          entropy: 0.1,
          at: at,
        ));
      }
      expect(b.hourlyProfiles[14].sampleCount, 30);
      // EMA with alpha=0.02 converges ~half-way after 30 samples
      expect(b.hourlyProfiles[14].typicalSpeed, closeTo(1.36, 0.05));
    });
  });
}
