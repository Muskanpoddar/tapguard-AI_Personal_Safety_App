// test/widget/contributing_factors_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapguard/data/services/risk/decision_engine.dart';
import 'package:tapguard/presentation/safety_status/widgets/contributing_factors_widget.dart';

RiskResult _buildResult({
  double score = 0.6,
  RiskLevel level = RiskLevel.medium,
  double modelScore = 0.5,
  double anomalyScore = 0.6,
  double keywordScore = 0.0,
  double rulesScore = 0.3,
  Map<String, dynamic>? motion,
  bool anomalyPersonalized = true,
}) {
  return RiskResult(
    score: score,
    level: level,
    evaluatedAt: DateTime.now(),
    modelScore: modelScore,
    anomalyScore: anomalyScore,
    keywordScore: keywordScore,
    rulesScore: rulesScore,
    factors: {
      'model': modelScore,
      'anomaly': anomalyScore,
      'anomaly_personalized': anomalyPersonalized,
      'keyword': keywordScore,
      'rules': rulesScore,
      'weights': {
        'model': 0.45,
        'anomaly': 0.30,
        'keyword': 0.15,
        'rules': 0.10,
      },
      'motion': motion ??
          {
            'violent': 0,
            'fast': 0,
            'jittery': 0,
            'stationary': 1,
            'accelMax': 9.8,
            'jerk': 0,
            'gyroMax': 0,
          },
      'location': {
        'speed': 0,
        'distanceFromHome': 0,
        'entropy': 0,
      },
      'context': {
        'lateNight': 0,
        'battery': 0.8,
        'online': 1,
      },
    },
  );
}

void main() {
  group('ContributingFactorsWidget', () {
    testWidgets('renders "Why this score?" header',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ContributingFactorsWidget(
            result: _buildResult(modelScore: 0.6, anomalyScore: 0.5),
          ),
        ),
      ));
      expect(find.text('Why this score?'), findsOneWidget);
    });

    testWidgets('lists at most 3 factor rows', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ContributingFactorsWidget(
            result: _buildResult(
              modelScore: 0.7,
              anomalyScore: 0.6,
              keywordScore: 0.5,
              rulesScore: 0.4,
              motion: {
                'violent': 0.8,
                'fast': 0.7,
                'jittery': 0.6,
                'stationary': 0,
                'accelMax': 30,
                'jerk': 5,
                'gyroMax': 10,
              },
            ),
          ),
        ),
      ));
      // 3 factor rows max, but only 3 _FactorRow widgets. Look for
      // the percentage label pattern.
      final matches = find.byWidgetPredicate((w) =>
          w is Text && (w.data?.contains('%') ?? false));
      expect(matches, findsNWidgets(3));
    });

    testWidgets('uses "Off-baseline (vs your routine)" label when personalized',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ContributingFactorsWidget(
            result: _buildResult(
              anomalyScore: 0.8,
              anomalyPersonalized: true,
            ),
          ),
        ),
      ));
      expect(
        find.text('Off-baseline (vs your routine)'),
        findsOneWidget,
      );
    });

    testWidgets('uses generic "Anomaly" label when not personalized',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ContributingFactorsWidget(
            result: _buildResult(
              anomalyScore: 0.8,
              anomalyPersonalized: false,
            ),
          ),
        ),
      ));
      expect(find.text('Anomaly'), findsOneWidget);
    });

    testWidgets('renders nothing when all factors are below threshold',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ContributingFactorsWidget(
            result: _buildResult(
              modelScore: 0.02,
              anomalyScore: 0.02,
              keywordScore: 0.02,
              rulesScore: 0.02,
            ),
          ),
        ),
      ));
      expect(find.text('Why this score?'), findsNothing);
    });
  });
}
