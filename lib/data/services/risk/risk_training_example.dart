// lib/data/services/risk/risk_training_example.dart
//
// One user-feedback example: the feature vector at the moment of
// feedback + a label (0.0 = definitely safe, 1.0 = definitely risk)
// + the source (where the feedback came from) + a timestamp.

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Source of the feedback that produced this example.
class TrainingSource {
  static const String iAmSafe = 'i_am_safe';
  static const String sosFired = 'sos_fired';
  static const String shakeSos = 'shake_sos';
  static const String audioAlarm = 'audio_alarm';
  static const String manualTest = 'manual_test';

  static const Set<String> all = {
    iAmSafe,
    sosFired,
    shakeSos,
    audioAlarm,
    manualTest,
  };
}

@immutable
class RiskTrainingExample {
  /// Feature vector (must match `RiskFeatures.toList()` order).
  final List<double> features;

  /// 0.0 = safe, 1.0 = risk. Intermediate values allowed.
  final double label;

  /// Where the feedback came from.
  final String source;

  /// When the example was captured.
  final DateTime capturedAt;

  const RiskTrainingExample({
    required this.features,
    required this.label,
    required this.source,
    required this.capturedAt,
  });
}

class RiskTrainingExampleAdapter extends TypeAdapter<RiskTrainingExample> {
  @override
  final int typeId = 10;

  @override
  RiskTrainingExample read(BinaryReader reader) {
    final n = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < n; i++) reader.readByte(): reader.read(),
    };
    return RiskTrainingExample(
      features: (fields[0] as List).cast<double>(),
      label: fields[1] as double,
      source: fields[2] as String,
      capturedAt: fields[3] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, RiskTrainingExample obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.features)
      ..writeByte(1)
      ..write(obj.label)
      ..writeByte(2)
      ..write(obj.source)
      ..writeByte(3)
      ..write(obj.capturedAt);
  }
}
