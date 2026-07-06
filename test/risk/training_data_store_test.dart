// test/risk/training_data_store_test.dart
//
// Phase 4 — tests for the user-feedback training-example store.

import 'package:flutter_test/flutter_test.dart';
import 'package:tapguard/data/services/risk/risk_training_example.dart';
import 'package:tapguard/data/services/risk/training_data_store.dart';

void main() {
  group('TrainingDataStats', () {
    test('isReadyForRetraining requires >=50 positive and >=50 negative',
        () {
      const stats = TrainingDataStats(
        total: 200,
        positiveCount: 60,
        negativeCount: 140,
        bySource: {},
      );
      expect(stats.isReadyForRetraining, true);
    });

    test('isReadyForRetraining is false when either side is low', () {
      const stats = TrainingDataStats(
        total: 30,
        positiveCount: 5,
        negativeCount: 25,
        bySource: {},
      );
      expect(stats.isReadyForRetraining, false);
    });
  });

  group('RiskTrainingExample', () {
    test('TrainingSource has the 5 expected keys', () {
      expect(TrainingSource.all, containsAll([
        TrainingSource.iAmSafe,
        TrainingSource.sosFired,
        TrainingSource.shakeSos,
        TrainingSource.audioAlarm,
        TrainingSource.manualTest,
      ]));
    });
  });
}
