// lib/data/services/risk/feature_extractor.dart
//
// Phase 1 — Aggregates the latest 1-Hz outputs from each collector
// into a single `RiskFeatures` vector that the risk model consumes.
//
// In Phase 2 this vector will be fed to a TFLite model. In Phase 1
// the decision engine uses the same fields directly.

import 'dart:math' as math;

import 'context_collector.dart';
import 'location_collector.dart';
import 'motion_collector.dart';
import 'yamnet_bridge.dart';

class RiskFeatures {
  // Motion (12)
  final double accelMagMean;
  final double accelMagStd;
  final double accelMagMax;
  final double accelJerk;
  final double accelEnergy;
  final double gyroMagMean;
  final double gyroMagMax;
  final double gyroEnergy;
  // 4 derived booleans (0/1)
  final double isStationary;
  final double isViolent;
  final double isFast;
  final double isJittery;

  // Location (7)
  final double speed;
  final double accuracy;
  final double distanceFromHome; // m
  final double distanceFromNearestFrequent; // m
  final double entropy;
  final double logDistanceFromHome;
  final double isAtHome;

  // Context (10)
  final double hourSin;
  final double hourCos;
  final double dowSin;
  final double dowCos;
  final double batteryLevel;
  final double isCharging;
  final double isOnline;
  final double isOnWifi;
  final double isOnCellular;
  final double lateNight; // 22:00–05:00

  // Audio (1) — keyword hit in the last 10s?
  final double keywordHit;

  // Audio events (5) — YAMNet-derived safety concerns, decay over 10s
  final double audioVerbalAggression;
  final double audioGlassBreaking;
  final double audioVehicleImpact;
  final double audioExplosion;
  final double audioAlarm;

  const RiskFeatures({
    required this.accelMagMean,
    required this.accelMagStd,
    required this.accelMagMax,
    required this.accelJerk,
    required this.accelEnergy,
    required this.gyroMagMean,
    required this.gyroMagMax,
    required this.gyroEnergy,
    required this.isStationary,
    required this.isViolent,
    required this.isFast,
    required this.isJittery,
    required this.speed,
    required this.accuracy,
    required this.distanceFromHome,
    required this.distanceFromNearestFrequent,
    required this.entropy,
    required this.logDistanceFromHome,
    required this.isAtHome,
    required this.hourSin,
    required this.hourCos,
    required this.dowSin,
    required this.dowCos,
    required this.batteryLevel,
    required this.isCharging,
    required this.isOnline,
    required this.isOnWifi,
    required this.isOnCellular,
    required this.lateNight,
    required this.keywordHit,
    required this.audioVerbalAggression,
    required this.audioGlassBreaking,
    required this.audioVehicleImpact,
    required this.audioExplosion,
    required this.audioAlarm,
  });

  /// Total feature count (sanity check against the model's input size).
  static const int expectedCount = 35;

  /// Flat float vector — order must match the model's input tensor.
  List<double> toList() => [
        accelMagMean,
        accelMagStd,
        accelMagMax,
        accelJerk,
        accelEnergy,
        gyroMagMean,
        gyroMagMax,
        gyroEnergy,
        isStationary,
        isViolent,
        isFast,
        isJittery,
        speed,
        accuracy,
        distanceFromHome,
        distanceFromNearestFrequent,
        entropy,
        logDistanceFromHome,
        isAtHome,
        hourSin,
        hourCos,
        dowSin,
        dowCos,
        batteryLevel,
        isCharging,
        isOnline,
        isOnWifi,
        isOnCellular,
        lateNight,
        keywordHit,
        audioVerbalAggression,
        audioGlassBreaking,
        audioVehicleImpact,
        audioExplosion,
        audioAlarm,
      ];

  /// Neutral (no signal) features — used as a safe default.
  static const RiskFeatures neutral = RiskFeatures(
    accelMagMean: 9.8,
    accelMagStd: 0,
    accelMagMax: 9.8,
    accelJerk: 0,
    accelEnergy: 96,
    gyroMagMean: 0,
    gyroMagMax: 0,
    gyroEnergy: 0,
    isStationary: 1,
    isViolent: 0,
    isFast: 0,
    isJittery: 0,
    speed: 0,
    accuracy: 0,
    distanceFromHome: 0,
    distanceFromNearestFrequent: 0,
    entropy: 0,
    logDistanceFromHome: 0,
    isAtHome: 1,
    hourSin: 0,
    hourCos: 1,
    dowSin: 0,
    dowCos: 1,
    batteryLevel: 1,
    isCharging: 0,
    isOnline: 1,
    isOnWifi: 0,
    isOnCellular: 1,
    lateNight: 0,
    keywordHit: 0,
    audioVerbalAggression: 0,
    audioGlassBreaking: 0,
    audioVehicleImpact: 0,
    audioExplosion: 0,
    audioAlarm: 0,
  );

  /// Returns a new [RiskFeatures] with the given fields overridden.
  /// Useful in tests and when the engine needs to tweak one signal
  /// without rebuilding the whole vector.
  RiskFeatures copyWith({
    double? accelMagMean,
    double? accelMagStd,
    double? accelMagMax,
    double? accelJerk,
    double? accelEnergy,
    double? gyroMagMean,
    double? gyroMagMax,
    double? gyroEnergy,
    double? isStationary,
    double? isViolent,
    double? isFast,
    double? isJittery,
    double? speed,
    double? accuracy,
    double? distanceFromHome,
    double? distanceFromNearestFrequent,
    double? entropy,
    double? logDistanceFromHome,
    double? isAtHome,
    double? hourSin,
    double? hourCos,
    double? dowSin,
    double? dowCos,
    double? batteryLevel,
    double? isCharging,
    double? isOnline,
    double? isOnWifi,
    double? isOnCellular,
    double? lateNight,
    double? keywordHit,
    double? audioVerbalAggression,
    double? audioGlassBreaking,
    double? audioVehicleImpact,
    double? audioExplosion,
    double? audioAlarm,
  }) {
    return RiskFeatures(
      accelMagMean: accelMagMean ?? this.accelMagMean,
      accelMagStd: accelMagStd ?? this.accelMagStd,
      accelMagMax: accelMagMax ?? this.accelMagMax,
      accelJerk: accelJerk ?? this.accelJerk,
      accelEnergy: accelEnergy ?? this.accelEnergy,
      gyroMagMean: gyroMagMean ?? this.gyroMagMean,
      gyroMagMax: gyroMagMax ?? this.gyroMagMax,
      gyroEnergy: gyroEnergy ?? this.gyroEnergy,
      isStationary: isStationary ?? this.isStationary,
      isViolent: isViolent ?? this.isViolent,
      isFast: isFast ?? this.isFast,
      isJittery: isJittery ?? this.isJittery,
      speed: speed ?? this.speed,
      accuracy: accuracy ?? this.accuracy,
      distanceFromHome: distanceFromHome ?? this.distanceFromHome,
      distanceFromNearestFrequent:
          distanceFromNearestFrequent ?? this.distanceFromNearestFrequent,
      entropy: entropy ?? this.entropy,
      logDistanceFromHome: logDistanceFromHome ?? this.logDistanceFromHome,
      isAtHome: isAtHome ?? this.isAtHome,
      hourSin: hourSin ?? this.hourSin,
      hourCos: hourCos ?? this.hourCos,
      dowSin: dowSin ?? this.dowSin,
      dowCos: dowCos ?? this.dowCos,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      isCharging: isCharging ?? this.isCharging,
      isOnline: isOnline ?? this.isOnline,
      isOnWifi: isOnWifi ?? this.isOnWifi,
      isOnCellular: isOnCellular ?? this.isOnCellular,
      lateNight: lateNight ?? this.lateNight,
      keywordHit: keywordHit ?? this.keywordHit,
      audioVerbalAggression:
          audioVerbalAggression ?? this.audioVerbalAggression,
      audioGlassBreaking: audioGlassBreaking ?? this.audioGlassBreaking,
      audioVehicleImpact: audioVehicleImpact ?? this.audioVehicleImpact,
      audioExplosion: audioExplosion ?? this.audioExplosion,
      audioAlarm: audioAlarm ?? this.audioAlarm,
    );
  }
}

class FeatureExtractor {
  FeatureExtractor();

  /// Build a `RiskFeatures` vector from the latest samples.
  RiskFeatures build({
    required MotionWindow? motion,
    required LocationSample? location,
    required ContextSnapshot context,
    required double keywordHit,
    AudioEventScore audio = AudioEventScore.neutral,
  }) {
    // Motion
    final accMean = motion?.accelMagMean ?? 9.8;
    final accMax = motion?.accelMagMax ?? 9.8;
    final accJerk = motion?.accelJerk ?? 0.0;
    final accEnergy = motion?.accelEnergy ?? 96.0;
    final gyroMax = motion?.gyroMagMax ?? 0.0;

    final isStationary = (accMean < 0.5 && accEnergy < 1.0) ? 1.0 : 0.0;
    final isViolent = (accMax > 25.0 && accJerk > 3.0 && gyroMax > 8.0) ? 1.0 : 0.0;
    final isFast = (location != null && location.speed > 6.0) ? 1.0 : 0.0;
    final isJittery = (accJerk > 1.5 && !isViolent.isNaN && isViolent == 0.0) ? 1.0 : 0.0;

    // Location
    final fromHome = location?.distanceFromHome ?? 0.0;
    final fromNearest = location?.distanceFromNearestFrequent ?? 0.0;
    final isAtHome = (fromHome.isNaN || fromHome < 100) ? 1.0 : 0.0;
    final logDist = (fromHome.isNaN || fromHome <= 0) ? 0.0 : _log1p(fromHome / 1000.0);

    // Context
    final lateNight = _isLateNight(context.at);

    return RiskFeatures(
      accelMagMean: accMean,
      accelMagStd: motion?.accelMagStd ?? 0.0,
      accelMagMax: accMax,
      accelJerk: accJerk,
      accelEnergy: accEnergy,
      gyroMagMean: motion?.gyroMagMean ?? 0.0,
      gyroMagMax: gyroMax,
      gyroEnergy: motion?.gyroEnergy ?? 0.0,
      isStationary: isStationary,
      isViolent: isViolent,
      isFast: isFast,
      isJittery: isJittery,
      speed: location?.speed ?? 0.0,
      accuracy: location?.accuracy ?? 0.0,
      distanceFromHome: fromHome.isNaN ? 0.0 : fromHome,
      distanceFromNearestFrequent: fromNearest.isNaN ? 0.0 : fromNearest,
      entropy: location?.entropy ?? 0.0,
      logDistanceFromHome: logDist,
      isAtHome: isAtHome,
      hourSin: context.hourSin,
      hourCos: context.hourCos,
      dowSin: context.dowSin,
      dowCos: context.dowCos,
      batteryLevel: context.batteryLevel,
      isCharging: context.isCharging ? 1.0 : 0.0,
      isOnline: context.isOnline ? 1.0 : 0.0,
      isOnWifi: context.isOnWifi ? 1.0 : 0.0,
      isOnCellular: context.isOnCellular ? 1.0 : 0.0,
      lateNight: lateNight,
      keywordHit: keywordHit,
      audioVerbalAggression: audio.verbalAggression,
      audioGlassBreaking: audio.glassBreaking,
      audioVehicleImpact: audio.vehicleImpact,
      audioExplosion: audio.explosion,
      audioAlarm: audio.alarm,
    );
  }

  // 22:00 – 05:00
  static double _isLateNight(DateTime t) {
    final h = t.hour;
    return (h >= 22 || h < 5) ? 1.0 : 0.0;
  }

  static double _log1p(double x) {
    if (x <= 0) return 0.0;
    return math.log(x + 1);
  }
}
