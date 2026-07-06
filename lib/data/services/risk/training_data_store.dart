// lib/data/services/risk/training_data_store.dart
//
// Phase 4 — Persist user-feedback training examples to Hive so the
// risk model can be retrained on real data.
//
// Sources:
//   * `i_am_safe`   — user confirmed they were safe (label 0.0)
//   * `sos_fired`   — SOS was dispatched and NOT cancelled (label 1.0)
//   * `shake_sos`   — shake-to-SOS was triggered (label 1.0)
//   * `audio_alarm` — keyword hit escalated (label 0.7)
//
// Examples are kept for 30 days, then pruned. Capped at 5000 entries
// to keep the Hive box small.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'risk_training_example.dart';

class TrainingDataStore {
  static const String _boxName = 'risk_training_v1';

  /// Maximum number of examples to keep. Older examples are pruned
  /// when this is exceeded.
  static const int _maxExamples = 5000;

  /// Examples older than this are pruned on [prune].
  static const Duration _maxAge = Duration(days: 30);

  Box<RiskTrainingExample>? _box;

  /// Open the box. Safe to call multiple times.
  Future<void> open() async {
    if (_box != null) return;
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(RiskTrainingExampleAdapter());
    }
    _box = await Hive.openBox<RiskTrainingExample>(_boxName);
  }

  /// Close the box. Safe to call multiple times.
  Future<void> close() async {
    await _box?.close();
    _box = null;
  }

  /// Add an example. If the box is full, the oldest example is
  /// removed to make room.
  Future<void> add(RiskTrainingExample example) async {
    final box = _box;
    if (box == null) return;
    if (box.length >= _maxExamples) {
      final keys = box.keys.toList();
      await box.delete(keys[0]);
    }
    await box.add(example);
  }

  /// Return all stored examples.
  List<RiskTrainingExample> all() {
    final box = _box;
    if (box == null) return const [];
    return box.values.toList(growable: false);
  }

  /// How many examples are stored.
  int get count => _box?.length ?? 0;

  /// Statistics about the stored examples.
  TrainingDataStats stats() {
    final box = _box;
    if (box == null) {
      return const TrainingDataStats(
        total: 0,
        positiveCount: 0,
        negativeCount: 0,
        bySource: {},
      );
    }
    int pos = 0;
    int neg = 0;
    final bySource = <String, int>{};
    for (final e in box.values) {
      if (e.label >= 0.5) {
        pos++;
      } else {
        neg++;
      }
      bySource[e.source] = (bySource[e.source] ?? 0) + 1;
    }
    return TrainingDataStats(
      total: box.length,
      positiveCount: pos,
      negativeCount: neg,
      bySource: bySource,
    );
  }

  /// Delete examples older than [_maxAge].
  Future<int> prune() async {
    final box = _box;
    if (box == null) return 0;
    final cutoff = DateTime.now().subtract(_maxAge);
    final toDelete = <dynamic>[];
    for (final key in box.keys) {
      final e = box.get(key);
      if (e != null && e.capturedAt.isBefore(cutoff)) {
        toDelete.add(key);
      }
    }
    if (toDelete.isNotEmpty) {
      await box.deleteAll(toDelete);
    }
    return toDelete.length;
  }

  /// Clear all stored examples. Used by tests and "forget my data".
  Future<void> clear() async {
    await _box?.clear();
  }
}

@immutable
class TrainingDataStats {
  final int total;
  final int positiveCount;
  final int negativeCount;
  final Map<String, int> bySource;

  const TrainingDataStats({
    required this.total,
    required this.positiveCount,
    required this.negativeCount,
    required this.bySource,
  });

  /// True when we have at least 50 positive and 50 negative examples —
  /// the minimum for a meaningful retraining round.
  bool get isReadyForRetraining => positiveCount >= 50 && negativeCount >= 50;
}
