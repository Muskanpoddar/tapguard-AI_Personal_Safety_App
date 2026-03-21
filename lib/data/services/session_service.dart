// lib/data/services/session_service.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import '../models/session_model.dart';

class SessionService {
  static final SessionService _i = SessionService._();
  factory SessionService() => _i;
  SessionService._();

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  SessionModel? _active;
  StreamSubscription<Position>? _gpsSub;
  Timer? _timeout;

  final _ctrl = StreamController<SessionModel?>.broadcast();
  Stream<SessionModel?> get sessionStream => _ctrl.stream;
  SessionModel? get activeSession => _active;
  bool get hasActiveSession => _active?.isActive == true;

  // ── Create session (Phone A) ──────────────────────────────────────────────
  Future<SessionModel> createSession({
    required String ownerName,
    required String ownerPhone,
    Duration timeout = const Duration(hours: 2),
  }) async {
    final pos = await _getLocation();
    final user = _auth.currentUser ?? (await _auth.signInAnonymously()).user;
    final uid = user?.uid ?? 'anon';
    final ref = _db.collection('sessions').doc();
    final id = ref.id;
    final url = 'https://tapguard-0.web.app/s/$id';
    final now = DateTime.now();

    await ref.set({
      'ownerUid': uid,
      'ownerPhone': ownerPhone,
      'ownerName': ownerName,
      'ownerLat': pos.latitude,
      'ownerLng': pos.longitude,
      'ownerAccuracy': pos.accuracy,
      'receiverJoined': false,
      'isActive': true,
      'shareUrl': url,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    _active = SessionModel(
      sessionId: id,
      ownerUid: uid,
      ownerPhone: ownerPhone,
      ownerName: ownerName,
      ownerLat: pos.latitude,
      ownerLng: pos.longitude,
      ownerAccuracy: pos.accuracy,
      createdAt: now,
      updatedAt: now,
      isActive: true,
      shareUrl: url,
    );
    _ctrl.add(_active);

    _startOwnerStream(id);
    _timeout?.cancel();
    _timeout = Timer(timeout, endSession);
    return _active!;
  }

  // ── Stream Phone A GPS → ownerLat/ownerLng in Firestore ──────────────────
  void _startOwnerStream(String sessionId) {
    _gpsSub?.cancel();
    _gpsSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).listen((pos) async {
          if (_active == null) return;
          await _db.collection('sessions').doc(sessionId).update({
            'ownerLat': pos.latitude,
            'ownerLng': pos.longitude,
            'ownerAccuracy': pos.accuracy,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          _active = _active!.copyWith(
            ownerLat: pos.latitude,
            ownerLng: pos.longitude,
            ownerAccuracy: pos.accuracy,
            updatedAt: DateTime.now(),
          );
          _ctrl.add(_active);
        });
  }

  // ── Watch full session (both locations) — used by map/session screens ─────
  Stream<SessionModel?> watchSession(String sessionId) {
    return _db
        .collection('sessions')
        .doc(sessionId)
        .snapshots()
        .map((s) => s.exists ? SessionModel.fromMap(s.data()!, s.id) : null);
  }

  // ── End session ───────────────────────────────────────────────────────────
  Future<void> endSession() async {
    if (_active == null) return;
    _gpsSub?.cancel();
    _timeout?.cancel();
    await _db.collection('sessions').doc(_active!.sessionId).update({
      'isActive': false,
    });
    _active = null;
    _ctrl.add(null);
  }

  // ── Permission + location ─────────────────────────────────────────────────
  Future<Position> _getLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('GPS is off. Enable Location Services.');
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied) {
        throw Exception('Location permission denied.');
      }
    }
    if (p == LocationPermission.deniedForever) {
      throw Exception('Location permanently denied. Enable in Settings.');
    }
    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  void dispose() {
    _gpsSub?.cancel();
    _timeout?.cancel();
    _ctrl.close();
  }
}
