// test/risk/baseline_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tapguard/data/services/risk/baseline_store.dart';
import 'package:tapguard/data/services/risk/user_baseline.dart';

void main() {
  group('MemoryBaselineStore', () {
    test('starts empty', () async {
      final s = MemoryBaselineStore();
      await s.open();
      expect(await s.hasData(), false);
      final data = await s.load();
      expect(data.totalSamples, 0);
      expect(data.frequentPlaces, isEmpty);
      expect(data.hourlyProfiles.length, 24);
    });

    test('save / load round-trip', () async {
      final s = MemoryBaselineStore();
      await s.open();
      final data = UserBaselineData(
        frequentPlaces: <FrequentPlace>[],
        hourlyProfiles: List.generate(24, (h) => HourlyMotionProfile(hour: h)),
        totalSamples: 42,
        updatedAt: DateTime(2026, 1, 1),
      );
      await s.save(data);
      expect(await s.hasData(), true);
      final loaded = await s.load();
      expect(loaded.totalSamples, 42);
      expect(loaded.updatedAt, DateTime(2026, 1, 1));
    });

    test('close is idempotent', () async {
      final s = MemoryBaselineStore();
      await s.open();
      await s.close();
      await s.close(); // should not throw
    });
  });
}
