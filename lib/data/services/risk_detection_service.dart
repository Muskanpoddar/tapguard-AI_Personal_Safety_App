// lib/data/services/risk_detection_service.dart
//
// Phase 1 rewrite — same public API as before (RiskLevel, RiskResult,
// riskStream, recordInteraction, cancelSos, sendSafetyConfirmation),
// but the internals now use the AI risk engine:
//   motion_collector + audio_collector + location_collector +
//   context_collector → feature_extractor → risk_model + user_baseline
//   → decision_engine → RiskResult.
//
// The rest of the app (Safety Status screen, SOS auto-trigger,
// home tile) doesn't change because the API is identical.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shake/shake.dart';

import 'risk/audio_collector.dart';
import 'risk/baseline_store.dart';
import 'risk/battery_profiler.dart';
import 'risk/context_collector.dart';
import 'risk/decision_engine.dart';
import 'risk/feature_extractor.dart';
import 'risk/location_collector.dart';
import 'risk/model_health_monitor.dart';
import 'risk/motion_collector.dart';
import 'risk/risk_model.dart';
import 'risk/risk_training_example.dart';
import 'risk/training_data_store.dart';
import 'risk/user_baseline.dart';

export 'risk/decision_engine.dart' show RiskLevel, RiskResult;

class RiskDetectionService {
  static final RiskDetectionService _i = RiskDetectionService._().._init();
  factory RiskDetectionService() => _i;
  RiskDetectionService._();

  bool _initialized = false;

  // ── Collectors ─────────────────────────────────────────────────────────
  final MotionCollector _motion = MotionCollector();
  final AudioCollector _audio = AudioCollector();
  final LocationCollector _location = LocationCollector();
  final ContextCollector _context = ContextCollector();

  // ── Engine pieces ──────────────────────────────────────────────────────
  final FeatureExtractor _features = FeatureExtractor();
  final RiskModel _model = RiskModel();
  final BaselineStore _baselineStore = HiveBaselineStore();
  late final UserBaseline _baseline = UserBaseline(store: _baselineStore);
  late final DecisionEngine _engine = DecisionEngine(
    model: _model,
    baseline: _baseline,
    healthMonitor: _healthMonitor,
  );

  // Phase 4 — collects user-feedback examples for retraining
  final TrainingDataStore _trainingStore = TrainingDataStore();

  // Phase 6 — battery profiling + model health monitoring
  final BatteryProfiler _batteryProfiler = BatteryProfiler();
  final ModelHealthMonitor _healthMonitor = ModelHealthMonitor();
  ModelHealth get modelHealth => _healthMonitor.current;

  // ── Shake (kept for parity with the previous engine) ──────────────────
  late final ShakeDetector _shakeDetector;

  // ── State ──────────────────────────────────────────────────────────────
  final _resultCtrl = StreamController<RiskResult>.broadcast();
  Stream<RiskResult> get riskStream => _resultCtrl.stream;
  RiskResult? get lastResult => _lastResult;
  bool get isMonitoring => _isMonitoring;
  bool get sosTriggered => _sosTriggered;

  bool _isMonitoring = false;
  bool _sosTriggered = false;
  Timer? _evalTimer;
  RiskResult? _lastResult;
  // Re-entrancy guard for _evaluate. The 1-Hz timer used to fire
  // while a previous tick was still draining (e.g. a slow Hive
  // save or a stalled TFLite inference), causing the platform
  // method-channel queue to back up until OneSignal's 6 s ANR
  // watchdog killed the app. Skip instead of piling up.
  bool _evaluating = false;

  // Latest samples from each collector (refreshed every 1 s)
  MotionWindow? _latestMotion;
  LocationSample? _latestLocation;
  DateTime? _lastKeywordAt;
  double _lastKeywordConfidence = 0.0;

  // Phase 4 — feature vector from the last evaluation, used for
  // capturing training examples when the user provides feedback.
  RiskFeatures? _latestFeatures;

  RiskDetectionService _init() {
    if (_initialized) return this;
    _initialized = true;
    _shakeDetector = ShakeDetector.autoStart(
      onPhoneShake: _onShakeDetected,
    );
    _motion.windowStream.listen((w) => _latestMotion = w);
    _location.sampleStream.listen((s) {
      _latestLocation = s;
      // Fire-and-forget: the baseline updates its persistent store
      // every 50 samples.
      unawaited(_baseline.observe(s));
      // Once the baseline is loaded, push its frequent places
      // back into the location collector for distance computation.
      if (_baseline.frequentPlaces.isNotEmpty) {
        _location.frequentPlaces = _baseline.frequentPlaces;
      }
    });
    _audio.keywordStream.listen((hit) {
      _lastKeywordAt = hit.at;
      _lastKeywordConfidence = hit.confidence;
    });
    return this;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> startMonitoring() async {
    if (_isMonitoring) return;
    _isMonitoring = true;
    _sosTriggered = false;
    _engine.startSession();
    _engine.recordInteraction();

    // Load the user baseline (Hive). If Hive isn't initialised yet
    // (rare — main.dart does it), fall back to an in-memory store.
    try {
      await HiveBaselineStore.ensureInitialized();
      await _baselineStore.open();
      await _baseline.load();
      // Phase 4 — open the training-example store
      await _trainingStore.open();
    } catch (e) {
      debugPrint('[RiskDetectionService] baseline load failed: $e');
    }

    // Try to load the (Phase-2) model. Phase 1 falls through to the
    // heuristic inside RiskModel.
    await _model.load();
    await _audio.loadKeywordModel();
    // Phase 4 — YAMNet audio event classifier. Optional: if missing,
    // the audio score stays at 0 and the rest of the engine works.
    await _audio.yamnet.load();
    _shakeDetector.startListening();

    // Phase 6 — start battery profiling.
    _batteryProfiler.start();
    _batteryProfiler.markSensorStarted('motion');
    _batteryProfiler.markSensorStarted('location');
    _batteryProfiler.markSensorStarted('audio');
    _batteryProfiler.markSensorStarted('context');

    // Start collectors. Some may fail (e.g. mic permission denied);
    // the engine gracefully handles missing signals.
    await Future.wait([
      _context.start(),
      _location.start(),
      _audio.start(),
    ]);
    _motion.start();

    // Cadence: 2 s. A risk engine doesn't need 1-Hz — at 2 s we still
    // catch violent motion within two seconds, but the platform
    // thread has half as many timer callbacks to service. Combined
    // with the re-entrancy guard in _evaluate, this keeps us well
    // under the 5 s ANR limit even on slow devices.
    _evalTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _evaluate(),
    );
  }

  Future<void> stopMonitoring() async {
    if (!_isMonitoring) return;
    _isMonitoring = false;
    _evalTimer?.cancel();
    _evalTimer = null;
    _shakeDetector.stopListening();
    await Future.wait([
      _motion.stop(),
      _audio.stop(),
      _location.stop(),
      _context.stop(),
    ]);
  }

  void recordInteraction() {
    _engine.recordInteraction();
  }

  Future<void> triggerSosManually() async {
    if (_sosTriggered) return;
    _sosTriggered = true;
    final result = RiskResult(
      level: RiskLevel.high,
      score: 1.0,
      factors: {'trigger': 'manual'},
      evaluatedAt: DateTime.now(),
      modelScore: 1.0,
      anomalyScore: 0,
      keywordScore: 0,
      rulesScore: 1.0,
    );
    _lastResult = result;
    _resultCtrl.add(result);
    unawaited(_captureTrainingExample(
      label: 1.0,
      source: TrainingSource.sosFired,
    ));
    await _dispatchSos(result);
  }

  Future<void> cancelSos() async {
    _sosTriggered = false;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'sosActive': false,
        'sosTriggeredAt': null,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> sendSafetyConfirmation() async {
    _engine.recordInteraction();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'lastSafeAt': FieldValue.serverTimestamp(),
        'sosActive': false,
        'sosTriggeredAt': null,
      }, SetOptions(merge: true));
    } catch (_) {}

    // Phase 4 — capture a "definitely safe" example for retraining.
    // Only do this when an SOS was actually in flight (otherwise the
    // user is just opening the screen and the data is noise).
    if (_sosTriggered) {
      unawaited(_captureTrainingExample(
        label: 0.0,
        source: TrainingSource.iAmSafe,
      ));
    }
    _sosTriggered = false;

    final contacts = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('contacts')
        .get();

    for (final doc in contacts.docs) {
      final contactUid = doc.data()['uid'] as String? ?? doc.id;
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(contactUid)
            .collection('notifications')
            .add({
          'type': 'safety_confirmation',
          'fromUid': uid,
          'message':
              '${FirebaseAuth.instance.currentUser?.displayName ?? 'User'} is safe',
          'createdAt': FieldValue.serverTimestamp(),
          'read': false,
        });
      } catch (_) {}
    }
  }

  void dispose() {
    stopMonitoring();
    _motion.dispose();
    _audio.close();
    _location.dispose();
    _context.dispose();
    _model.close();
    unawaited(_baseline.close());
    unawaited(_trainingStore.close());
    _resultCtrl.close();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // INTERNAL
  // ═══════════════════════════════════════════════════════════════════════

  void _onShakeDetected([ShakeEvent? event]) {
    if (_sosTriggered) return;
    _sosTriggered = true;
    final result = RiskResult(
      level: RiskLevel.high,
      score: 1.0,
      factors: {'trigger': 'shake_detected'},
      evaluatedAt: DateTime.now(),
      modelScore: 0,
      anomalyScore: 0,
      keywordScore: 0,
      rulesScore: 1.0,
    );
    _lastResult = result;
    _resultCtrl.add(result);
    unawaited(_captureTrainingExample(
      label: 1.0,
      source: TrainingSource.shakeSos,
    ));
    _dispatchSos(result);
  }

  Future<void> _evaluate() async {
    if (!_isMonitoring || _sosTriggered) return;
    if (_evaluating) {
      // Previous tick still running (e.g. slow Firestore dispatch).
      // Skip this one so we don't stack work onto a stuck main
      // isolate.
      return;
    }
    _evaluating = true;
    try {
      final keywordConf = _keywordConfidence();
      final features = _features.build(
        motion: _latestMotion,
        location: _latestLocation,
        context: _context.last,
        keywordHit: _lastKeywordConfidence,
        audio: _audio.latestAudioScore,
      );
      _latestFeatures = features;
      final result = await _engine.decide(
        features: features,
        motion: _latestMotion,
        keywordConfidence: keywordConf,
        location: _latestLocation,
      );

      _lastResult = result;
      _resultCtrl.add(result);

      if (result.shouldTriggerSos && !_sosTriggered) {
        _sosTriggered = true;
        unawaited(_captureTrainingExample(
          label: 1.0,
          source: TrainingSource.sosFired,
        ));
        // Don't await _dispatchSos here — it's fully fire-and-
        // forget now (fanned out across contacts in parallel) and
        // we don't want any single notification write gating the
        // next 2-second tick.
        unawaited(_dispatchSos(result));
      }
    } finally {
      _evaluating = false;
    }
  }

  double _keywordConfidence() {
    if (_lastKeywordAt == null) return 0.0;
    final since = DateTime.now().difference(_lastKeywordAt!).inSeconds;
    if (since > 10) return 0.0;
    // Decay over 10s
    return _lastKeywordConfidence * (1.0 - since / 10.0);
  }

  Future<void> _dispatchSos(RiskResult result) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // 1. Mark the user as in SOS — fire-and-forget so a slow Firestore
    //    write doesn't gate the whole dispatch.
    unawaited(
      FirebaseFirestore.instance.collection('users').doc(uid).set({
        'sosActive': true,
        'sosTriggeredAt': FieldValue.serverTimestamp(),
        'sosRiskFactors': result.factors,
        'sosModelScore': result.modelScore,
        'sosAnomalyScore': result.anomalyScore,
      }, SetOptions(merge: true)).catchError((Object e) {
        debugPrint('[RiskDetectionService] SOS user-flag write failed: $e');
      }),
    );

    try {
      // 2. Read the trusted-contact list — only blocking call left.
      final contacts = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('contacts')
          .get();

      // 3. Fan out the per-contact notifications in parallel. The
      //    previous implementation awaited each one sequentially,
      //    so 10 contacts × ~600 ms slow round-trip could pile up
      //    past the 5 s ANR watchdog and trigger OneSignal's kill.
      //    Now each add() races independently and we don't block
      //    the UI isolate waiting for any of them.
      final ownerName =
          FirebaseAuth.instance.currentUser?.displayName ?? 'User';
      for (final doc in contacts.docs) {
        FirebaseFirestore.instance
            .collection('users')
            .doc(doc.id)
            .collection('notifications')
            .add({
              'type': 'sos_alert',
              'fromUid': uid,
              'fromName': ownerName,
              'message': 'SOS ALERT! Trusted contact needs help.',
              'createdAt': FieldValue.serverTimestamp(),
              'read': false,
            })
            .then((_) {}, onError: (Object e) {
          debugPrint(
            '[RiskDetectionService] SOS notification to '
            '${doc.id} failed: $e',
          );
        });
      }
    } catch (e) {
      debugPrint('[RiskDetectionService] contact list query failed: $e');
    }
  }
  // ── Phase 4 — training-example capture ───────────────────────────
  /// Persist the latest feature vector with a label and source.
  /// Called from `sendSafetyConfirmation` (label 0.0) and from
  /// `_dispatchSos` (label 1.0, source `sos_fired` / `shake_sos`).
  Future<void> _captureTrainingExample({
    required double label,
    required String source,
  }) async {
    final features = _latestFeatures;
    if (features == null) return;
    try {
      await _trainingStore.add(RiskTrainingExample(
        features: features.toList(),
        label: label,
        source: source,
        capturedAt: DateTime.now(),
      ));
      if (kDebugMode) {
        debugPrint(
          '[RiskDetectionService] captured training example: '
          'label=$label source=$source (total=${_trainingStore.count})',
        );
      }
    } catch (e) {
      debugPrint('[RiskDetectionService] training capture failed: $e');
    }
  }

  /// Public access to the training-data store — used by the
  /// Safety Status screen to show "X examples collected, ready
  /// to retrain".
  TrainingDataStore get trainingDataStore => _trainingStore;

  /// Public handle to the live [UserBaseline] used by the decision
  /// engine. Screens subscribe to its `changes` stream to render
  /// "X / N samples collected" progress, and read
  /// `baseline.totalSamples` / `baseline.isReady` for state.
  UserBaseline get baseline => _baseline;

  // ── Preferences (kept for parity) ─────────────────────────────────────
  Future<void> savePreferences({
    required bool shakeDetectionEnabled,
    required int autoTimeoutMinutes,
    required int locationAccuracyLevel,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('risk.shake_detection', shakeDetectionEnabled);
    await prefs.setInt('risk.auto_timeout', autoTimeoutMinutes);
    await prefs.setInt('risk.location_accuracy', locationAccuracyLevel);
  }

  Future<Map<String, dynamic>> loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'shakeDetection': prefs.getBool('risk.shake_detection') ?? true,
      'autoTimeout': prefs.getInt('risk.auto_timeout') ?? 120,
      'locationAccuracy': prefs.getInt('risk.location_accuracy') ?? 1,
    };
  }
}
