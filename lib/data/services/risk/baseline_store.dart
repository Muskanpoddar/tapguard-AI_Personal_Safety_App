// lib/data/services/risk/baseline_store.dart
//
// Phase 3 — Storage abstraction for the user's personalization baseline.
// The production implementation persists to Hive; tests use an
// in-memory implementation that doesn't require path_provider.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'user_baseline.dart';

/// Persists a single [UserBaseline] across app restarts.
abstract class BaselineStore {
  /// Open / initialize the store. Must be called before [load]/[save].
  Future<void> open();

  /// Close the store. Safe to call multiple times.
  Future<void> close();

  /// Returns the stored baseline, or a fresh one if nothing saved.
  Future<UserBaselineData> load();

  /// Persist the given baseline.
  Future<void> save(UserBaselineData data);

  /// True if the store has any saved data.
  Future<bool> hasData();
}

/// Plain-old data class for persistence. Keeps Hive-free so tests
/// don't need to register adapters for the live class.
@immutable
class UserBaselineData {
  final List<FrequentPlace> frequentPlaces;
  final List<HourlyMotionProfile> hourlyProfiles;
  final int totalSamples;
  final DateTime updatedAt;

  const UserBaselineData({
    required this.frequentPlaces,
    required this.hourlyProfiles,
    required this.totalSamples,
    required this.updatedAt,
  });

  factory UserBaselineData.fresh() {
    final now = DateTime.now();
    return UserBaselineData(
      frequentPlaces: <FrequentPlace>[],
      hourlyProfiles: List.generate(
        24,
        (h) => HourlyMotionProfile(hour: h),
      ),
      totalSamples: 0,
      updatedAt: now,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// In-memory implementation — used in tests
// ─────────────────────────────────────────────────────────────────────

class MemoryBaselineStore implements BaselineStore {
  UserBaselineData _data = UserBaselineData.fresh();

  @override
  Future<void> open() async {}

  @override
  Future<void> close() async {}

  @override
  Future<UserBaselineData> load() async => _data;

  @override
  Future<void> save(UserBaselineData data) async {
    _data = data;
  }

  @override
  Future<bool> hasData() async => _data.totalSamples > 0;
}

// ─────────────────────────────────────────────────────────────────────
// Hive implementation — used in production
// ─────────────────────────────────────────────────────────────────────

class HiveBaselineStore implements BaselineStore {
  static const String _boxName = 'user_baseline_v1';
  static const String _key = 'baseline';

  /// Set this to `true` once `Hive.initFlutter()` has been called
  /// somewhere in the app (e.g. main.dart).
  static bool _hiveInitialized = false;

  Box<dynamic>? _box;

  /// Must be called once at app startup, BEFORE constructing a
  /// `HiveBaselineStore`.
  static Future<void> ensureInitialized({String? subDir}) async {
    if (_hiveInitialized) return;
    if (subDir != null) {
      await Hive.initFlutter(subDir);
    } else {
      await Hive.initFlutter();
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(FrequentPlaceAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(HourlyMotionProfileAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(UserBaselineDataAdapter());
    }
    _hiveInitialized = true;
  }

  @override
  Future<void> open() async {
    _box = await Hive.openBox<dynamic>(_boxName);
  }

  @override
  Future<void> close() async {
    await _box?.close();
    _box = null;
  }

  @override
  Future<UserBaselineData> load() async {
    final box = _box;
    if (box == null) return UserBaselineData.fresh();
    final raw = box.get(_key);
    if (raw is UserBaselineData) return raw;
    return UserBaselineData.fresh();
  }

  @override
  Future<void> save(UserBaselineData data) async {
    final box = _box;
    if (box == null) return;
    await box.put(_key, data);
  }

  @override
  Future<bool> hasData() async {
    final box = _box;
    if (box == null) return false;
    return box.containsKey(_key);
  }
}

// ─────────────────────────────────────────────────────────────────────
// Hive type adapters
// ─────────────────────────────────────────────────────────────────────

class FrequentPlaceAdapter extends TypeAdapter<FrequentPlace> {
  @override
  final int typeId = 1;

  @override
  FrequentPlace read(BinaryReader reader) {
    final n = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < n; i++) reader.readByte(): reader.read(),
    };
    return FrequentPlace(
      id: fields[0] as String,
      label: fields[1] as String,
      lat: fields[2] as double,
      lng: fields[3] as double,
      radiusMeters: fields[4] as double,
      visitCount: fields[5] as int,
      firstSeen: fields[6] as DateTime,
      lastSeen: fields[7] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, FrequentPlace obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.label)
      ..writeByte(2)
      ..write(obj.lat)
      ..writeByte(3)
      ..write(obj.lng)
      ..writeByte(4)
      ..write(obj.radiusMeters)
      ..writeByte(5)
      ..write(obj.visitCount)
      ..writeByte(6)
      ..write(obj.firstSeen)
      ..writeByte(7)
      ..write(obj.lastSeen);
  }
}

class HourlyMotionProfileAdapter extends TypeAdapter<HourlyMotionProfile> {
  @override
  final int typeId = 2;

  @override
  HourlyMotionProfile read(BinaryReader reader) {
    final n = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < n; i++) reader.readByte(): reader.read(),
    };
    return HourlyMotionProfile(
      hour: fields[0] as int,
      typicalSpeed: fields[1] as double,
      typicalEntropy: fields[2] as double,
      sampleCount: fields[3] as int,
    );
  }

  @override
  void write(BinaryWriter writer, HourlyMotionProfile obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.hour)
      ..writeByte(1)
      ..write(obj.typicalSpeed)
      ..writeByte(2)
      ..write(obj.typicalEntropy)
      ..writeByte(3)
      ..write(obj.sampleCount);
  }
}

class UserBaselineDataAdapter extends TypeAdapter<UserBaselineData> {
  @override
  final int typeId = 3;

  @override
  UserBaselineData read(BinaryReader reader) {
    final n = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < n; i++) reader.readByte(): reader.read(),
    };
    return UserBaselineData(
      frequentPlaces: (fields[0] as List).cast<FrequentPlace>(),
      hourlyProfiles: (fields[1] as List).cast<HourlyMotionProfile>(),
      totalSamples: fields[2] as int,
      updatedAt: fields[3] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, UserBaselineData obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.frequentPlaces)
      ..writeByte(1)
      ..write(obj.hourlyProfiles)
      ..writeByte(2)
      ..write(obj.totalSamples)
      ..writeByte(3)
      ..write(obj.updatedAt);
  }
}
