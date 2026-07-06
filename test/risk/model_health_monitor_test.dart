// test/risk/model_health_monitor_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tapguard/data/services/risk/model_health_monitor.dart';
import 'package:tapguard/data/services/risk/risk_model.dart';

RiskInference _inf(double model, [double h = 0.3]) => RiskInference(
      modelScore: model,
      heuristicScore: h,
      usedModel: true,
      at: DateTime.now(),
    );

void main() {
  group('ModelHealthMonitor', () {
    test('starts healthy', () {
      final m = ModelHealthMonitor();
      expect(m.current.isHealthy, true);
      expect(m.forceHeuristic, false);
    });

    test('NaN output triggers rollback', () {
      final m = ModelHealthMonitor();
      final ok = m.record(
        inference: _inf(double.nan),
        trainingStore: null,
      );
      expect(ok, false);
      expect(m.forceHeuristic, true);
      expect(m.current.reason, RollbackReason.nanOutput);
    });

    test('infinity output triggers rollback', () {
      final m = ModelHealthMonitor();
      m.record(
        inference: _inf(double.infinity),
        trainingStore: null,
      );
      expect(m.forceHeuristic, true);
    });

    test('sustained divergence triggers rollback', () {
      final m = ModelHealthMonitor(
        divergenceThreshold: 0.4,
        divergenceStreak: 3,
      );
      // Model says 0.9, heuristic says 0.1 → divergence 0.8 > 0.4
      for (int i = 0; i < 3; i++) {
        m.record(
          inference: _inf(0.9, 0.1),
          trainingStore: null,
        );
      }
      expect(m.forceHeuristic, true);
      expect(m.current.reason, RollbackReason.divergence);
    });

    test('small divergence does NOT trigger rollback', () {
      final m = ModelHealthMonitor(
        divergenceThreshold: 0.4,
        divergenceStreak: 3,
      );
      for (int i = 0; i < 10; i++) {
        m.record(
          inference: _inf(0.4, 0.35),
          trainingStore: null,
        );
      }
      expect(m.forceHeuristic, false);
      expect(m.current.consecutiveDivergences, 0);
    });

    test('reset clears state', () {
      final m = ModelHealthMonitor();
      m.record(
        inference: _inf(double.nan),
        trainingStore: null,
      );
      expect(m.forceHeuristic, true);
      m.reset();
      expect(m.forceHeuristic, false);
      expect(m.current.reason, RollbackReason.none);
    });
  });
}
