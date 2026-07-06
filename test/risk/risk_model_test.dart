// test/risk/risk_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tapguard/data/services/risk/feature_extractor.dart';
import 'package:tapguard/data/services/risk/risk_model.dart';

void main() {
  group('RiskModel (Phase 2 — A/B inference)', () {
    test('heuristic mode returns a finite score for neutral features', () async {
      final m = RiskModel(heuristicOnly: true);
      final score = await m.infer(RiskFeatures.neutral);
      expect(score.isFinite, true);
      expect(score, inInclusiveRange(0.0, 1.0));
    });

    test('heuristic scores higher for violent motion', () async {
      final m = RiskModel(heuristicOnly: true);
      final violent = RiskFeatures.neutral.copyWith(
        isViolent: 1.0,
        accelMagMax: 30,
        accelJerk: 5,
        gyroMagMax: 12,
      );
      final calm = RiskFeatures.neutral;
      final sViolent = await m.infer(violent);
      final sCalm = await m.infer(calm);
      expect(sViolent, greaterThan(sCalm));
    });

    test('inferWithCompare returns both scores and a flag', () async {
      final m = RiskModel(heuristicOnly: true);
      final result = await m.inferWithCompare(
        RiskFeatures.neutral.copyWith(keywordHit: 0.95),
      );
      // In heuristic mode, model and heuristic are equal and usedModel is false
      expect(result.modelScore, closeTo(result.heuristicScore, 0.0001));
      expect(result.usedModel, false);
      expect(result.activeScore, closeTo(result.heuristicScore, 0.0001));
    });

    test('keyword hit alone pushes the heuristic toward medium', () async {
      final m = RiskModel(heuristicOnly: true);
      final result = await m.infer(
        RiskFeatures.neutral.copyWith(keywordHit: 0.9),
      );
      // 0.30 contribution from keyword, plus any baseline
      expect(result, greaterThan(0.25));
    });

    test('isLoaded is false when no model is bundled and heuristicOnly=true',
        () async {
      final m = RiskModel(heuristicOnly: true);
      final loaded = await m.load();
      expect(m.isLoaded, false);
      expect(loaded, false);
    });

    test('load() does not throw when the model file is missing', () async {
      final m = RiskModel();
      // Should silently return false (heuristic fallback active)
      final loaded = await m.load();
      expect(loaded, false);
      expect(m.isLoaded, false);
    });
  });
}
