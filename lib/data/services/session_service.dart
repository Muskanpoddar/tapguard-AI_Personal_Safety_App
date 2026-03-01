// lib/data/services/session_service.dart
// Creates a Firestore session, streams live location updates to it,
// and returns the share URL that gets written to NFC tag.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import '../models/session_model.dart';

class SessionService {
  static final SessionService _instance = SessionService._internal();
  factory SessionService() => _instance;
  SessionService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Current active session
  SessionModel? _activeSession;
  StreamSubscription<Position>? _locationSub;
  Timer? _timeoutTimer;

  SessionModel? get activeSession => _activeSession;
  bool get hasActiveSession => _activeSession != null && (_activeSession?.isActive ?? false);

  // ── Create a new session ──────────────────────────────────────────────────
  // Returns the session (with shareUrl) or throws on error
  Future<SessionModel> createSession({
    required String ownerName,
    required String ownerPhone,
    Duration timeout = const Duration(hours: 2),
  }) async {
    // 1. Get current location
    final position = await _getCurrentLocation();

    // 2. Generate unique session ID
    final docRef = _db.collection('sessions').doc(); // auto-ID
    final sessionId = docRef.id;

    // 3. Build share URL
    // Replace with your real domain or Firebase Dynamic Link
    final shareUrl = 'https://tapguard.page.link/s/$sessionId';

    // 4. Get current user UID (may be null if not yet authenticated)
    final uid = _auth.currentUser?.uid ?? 'anonymous_$sessionId';

    // 5. Build model
    final now = DateTime.now();
    final session = SessionModel(
      sessionId:  sessionId,
      ownerUid:   uid,
      ownerPhone: ownerPhone,
      ownerName:  ownerName,
      latitude:   position.latitude,
      longitude:  position.longitude,
      accuracy:   position.accuracy,
      createdAt:  now,
      updatedAt:  now,
      isActive:   true,
      shareUrl:   shareUrl,
    );

    // 6. Write to Firestore
    await docRef.set(session.toMap());

    _activeSession = session;

    // 7. Start streaming location updates
    _startLocationStream(sessionId);

    // 8. Auto-end session after timeout
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(timeout, () => endSession());

    return session;
  }

  // ── Stream live location to Firestore ────────────────────────────────────
  void _startLocationStream(String sessionId) {
    _locationSub?.cancel();

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // update every 5 metres moved
    );

    _locationSub = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((position) async {
      if (_activeSession == null) return;

      // Update Firestore
      await _db.collection('sessions').doc(sessionId).update({
        'latitude':  position.latitude,
        'longitude': position.longitude,
        'accuracy':  position.accuracy,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update local model
      _activeSession = _activeSession!.copyWith(
        latitude:  position.latitude,
        longitude: position.longitude,
        accuracy:  position.accuracy,
        updatedAt: DateTime.now(),
      );
    });
  }

  // ── End / close session ───────────────────────────────────────────────────
  Future<void> endSession() async {
    if (_activeSession == null) return;

    _locationSub?.cancel();
    _timeoutTimer?.cancel();

    await _db
        .collection('sessions')
        .doc(_activeSession!.sessionId)
        .update({'isActive': false});

    _activeSession = null;
  }

  // ── Watch a session (for receiver / map screen) ───────────────────────────
  Stream<SessionModel?> watchSession(String sessionId) {
    return _db
        .collection('sessions')
        .doc(sessionId)
        .snapshots()
        .map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return SessionModel.fromMap(snap.data()!, snap.id);
    });
  }

  // ── Request location permission + get position ────────────────────────────
  Future<Position> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled. Please enable GPS.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
          'Location permission permanently denied. Please enable in Settings.');
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }
}