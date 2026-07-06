// test/risk/feature_extractor_phase4_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tapguard/data/services/risk/context_collector.dart';
import 'package:tapguard/data/services/risk/feature_extractor.dart';
import 'package:tapguard/data/services/risk/yamnet_bridge.dart';

ContextSnapshot _ctx() => ContextSnapshot(
      at: DateTime.now(),
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

void main() {
  group('RiskFeatures (Phase 4 audio fields)', () {
    test('feature count is 35 (was 30)', () {
      final fx = RiskFeatures.neutral;
      expect(fx.toList().length, 35);
      expect(fx.toList().length, RiskFeatures.expectedCount);
    });

    test('copyWith updates audio fields', () {
      final fx = RiskFeatures.neutral.copyWith(
        audioVerbalAggression: 0.9,
        audioGlassBreaking: 0.5,
      );
      expect(fx.audioVerbalAggression, 0.9);
      expect(fx.audioGlassBreaking, 0.5);
      expect(fx.audioVehicleImpact, 0.0);
    });

    test('FeatureExtractor.build accepts an audio score', () {
      final fx = FeatureExtractor().build(
        motion: null,
        location: null,
        context: _ctx(),
        keywordHit: 0,
        audio: const AudioEventScore(
          verbalAggression: 0.7,
          glassBreaking: 0,
          vehicleImpact: 0,
          explosion: 0,
          alarm: 0,
          topClassScore: 0.7,
          topClassName: 'Scream',
        ),
      );
      expect(fx.audioVerbalAggression, 0.7);
      expect(fx.audioAlarm, 0.0);
    });

    test('AudioEventScore.neutral has all zeros', () {
      const n = AudioEventScore.neutral;
      expect(n.verbalAggression, 0);
      expect(n.glassBreaking, 0);
      expect(n.vehicleImpact, 0);
      expect(n.explosion, 0);
      expect(n.alarm, 0);
      expect(n.maxConcern, 0);
    });

    test('AudioEventScore.maxConcern returns the largest concern', () {
      const s = AudioEventScore(
        verbalAggression: 0.3,
        glassBreaking: 0.8,
        vehicleImpact: 0.1,
        explosion: 0.0,
        alarm: 0.4,
        topClassScore: 0.8,
        topClassName: 'Glass',
      );
      expect(s.maxConcern, 0.8);
    });
  });
}
