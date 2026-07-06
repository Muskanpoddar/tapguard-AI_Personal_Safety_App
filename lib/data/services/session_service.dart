// lib/data/services/session_service.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/contact_model.dart';
import '../models/session_model.dart';

class SessionService {
  static final SessionService _i = SessionService._();
  factory SessionService() => _i;
  SessionService._();

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  SessionModel? _active;
  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<Position>? _receiverGpsSub;
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
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Not signed in. Please reopen the app.');
    }
    final uid = user.uid;
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
  // Firestore update is fire-and-forget so a chatty GPS stream can never
  // pile up awaits on the UI isolate and trip the 6 s ANR watchdog.
  void _startOwnerStream(String sessionId) {
    _gpsSub?.cancel();
    _gpsSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).listen((pos) {
      if (_active == null) return;
      // In-memory first — UI updates immediately, no network wait.
      _active = _active!.copyWith(
        ownerLat: pos.latitude,
        ownerLng: pos.longitude,
        ownerAccuracy: pos.accuracy,
        updatedAt: DateTime.now(),
      );
      _ctrl.add(_active);
      // Network write in background.
      unawaited(
        _db.collection('sessions').doc(sessionId).update({
          'ownerLat': pos.latitude,
          'ownerLng': pos.longitude,
          'ownerAccuracy': pos.accuracy,
          'updatedAt': FieldValue.serverTimestamp(),
        }).catchError((Object e) {
          debugPrint('Owner GPS write failed (non-blocking): $e');
        }),
      );
    });
  }

  // ── Stream Phone B GPS → receiverLat/receiverLng in Firestore ──────────
  void startReceiverStream(String sessionId) {
    _receiverGpsSub?.cancel();
    _receiverGpsSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).listen((pos) {
      unawaited(
        _db.collection('sessions').doc(sessionId).update({
          'receiverLat': pos.latitude,
          'receiverLng': pos.longitude,
          'receiverAccuracy': pos.accuracy,
          'updatedAt': FieldValue.serverTimestamp(),
        }).catchError((Object e) {
          debugPrint('Receiver GPS write failed (non-blocking): $e');
        }),
      );
    });
  }

  void stopReceiverStream() {
    _receiverGpsSub?.cancel();
    _receiverGpsSub = null;
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
    _receiverGpsSub?.cancel();
    _timeout?.cancel();
    await _db.collection('sessions').doc(_active!.sessionId).update({
      'isActive': false,
    });
    _active = null;
    _ctrl.add(null);
  }

  // ── Create session for an existing paired contact (no QR/NFC re-pair) ─────
  /// Opens a fresh session directly with [contact] — no QR/NFC handshake
  /// required. Pre-fills the receiver fields on the session doc, marks
  /// the contact `isActive`, and returns the active session model.
  /// The contact receives a push with the shareUrl deep-link so they
  /// can join from the notification.
  ///
  /// IMPORTANT: this is invoked on the Flutter UI isolate from
  /// `ContactDetailScreen._startSession`. Every `await` here adds
  /// directly to ANR risk (the OneSignal ANR watchdog fires at 5 s).
  /// Keep the awaits to: GPS + session create. The auth-identity write,
  /// owner-name fetch, and contact merge-set are all fire-and-forget.
  Future<SessionModel> createSessionForContact({
    required ContactModel contact,
    Duration timeout = const Duration(hours: 2),
  }) async {
    final pos = await _getLocation();
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Not signed in. Please reopen the app.');
    }
    final uid = user.uid;
    final ownerName  = user.displayName ?? 'You';
    final ownerPhone = user.phoneNumber ?? '';

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
      'receiverUid': contact.uid,
      'receiverName': contact.name,
      'receiverPhone': contact.phoneNumber,
      // Receiver isn't on the live socket yet — they need to tap the
      // push notification and open the shareUrl to actually stream
      // GPS. We mark joined: false so the UI doesn't render them as
      // connected until they tap in.
      'receiverJoined': false,
      'receiverJoinedAt': null,
      'isActive': true,
      'shareUrl': url,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'invitedFromContact': true,
    });

    _active = SessionModel(
      sessionId: id,
      ownerUid: uid,
      ownerPhone: ownerPhone,
      ownerName: ownerName,
      ownerLat: pos.latitude,
      ownerLng: pos.longitude,
      ownerAccuracy: pos.accuracy,
      receiverUid: contact.uid,
      receiverName: contact.name,
      receiverJoined: false,
      createdAt: now,
      updatedAt: now,
      isActive: true,
      shareUrl: url,
    );
    _ctrl.add(_active);

    _startOwnerStream(id);
    _timeout?.cancel();
    _timeout = Timer(timeout, endSession);

    // Mirror the session reference into the receiver's `sharedSessions`
    // subcollection so the OTHER phone can find this session in Firestore
    // (their in-memory `_active` is empty — only the owner has it). This
    // is what makes bi-directional work: the receiver's live_session
    // screen queries `sharedSessions`, picks up this sessionId, and
    // auto-starts their own GPS stream via `startReceiverStream`.
    //
    // Cross-user write: requires `ownerUid == request.auth.uid` in the
    // payload (see firestore.rules). ownerUid is included on BOTH writes
    // so the same rule covers them — owner's self-write goes through the
    // parent rule, receiver write goes through the subcollection rule.
    unawaited(
      _db
          .collection('users')
          .doc(contact.uid)
          .collection('sharedSessions')
          .doc(id)
          .set({
        'sessionId': id,
        'ownerUid': uid,
        'ownerName': ownerName,
        'shareUrl': url,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
      }).catchError((Object e) {
        debugPrint('Shared-session write failed (non-blocking): $e');
      }),
    );

    // And the reverse on the owner's side — record which contacts have
    // been invited to which session so the owner can later see a list
    // of "sessions I've shared". ownerUid included so this also passes
    // the subcollection rule if the parent rule ever needs to be relaxed.
    unawaited(
      _db
          .collection('users')
          .doc(uid)
          .collection('sharedSessions')
          .doc(id)
          .set({
        'sessionId': id,
        'ownerUid': uid,
        'receiverUid': contact.uid,
        'receiverName': contact.name,
        'shareUrl': url,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
      }).catchError((Object e) {
        debugPrint('Owner shared-session write failed (non-blocking): $e');
      }),
    );

    // Flip the contact's isActive flag so the home tile shows "Active Now".
    // Fire-and-forget — this is cosmetic and shouldn't block navigation.
    unawaited(
      _db
          .collection('users')
          .doc(uid)
          .collection('contacts')
          .doc(contact.uid)
          .set({
        'isActive': true,
        'lastSeen': FieldValue.serverTimestamp(),
        'sessionId': id,
      }, SetOptions(merge: true))
          .catchError((Object e) {
        debugPrint('Contact merge failed (non-blocking): $e');
      }),
    );

    return _active!;
  }

  // ── Permission + location ─────────────────────────────────────────────────
  // Hard-capped at ~3 s: `getCurrentPosition()` can hang 5-10 s on a cold
  // GPS lock (indoors, just-unlocked device), and this whole helper runs
  // on the UI thread from ContactDetailScreen._startSession. Hitting 6 s
  // trips OneSignal's ANR watchdog and the OS kills the app. Fall back
  // to last-known / defaults so navigation can proceed; the GPS stream
  // started by _startOwnerStream will overwrite the values within seconds.
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

    // 1. Try last-known position (essentially instant, may be stale).
    try {
      final last = await Geolocator.getLastKnownPosition().timeout(
        const Duration(milliseconds: 500),
        onTimeout: () => throw TimeoutException('last-known timeout'),
      );
      if (last != null &&
          (last.latitude != 0.0 || last.longitude != 0.0)) {
        return last;
      }
    } catch (_) {}

    // 2. Fresh fix with strict 3 s timeout.
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw TimeoutException('GPS fix timeout'),
      );
    } on TimeoutException {
      // 3. Final fallback: 0,0 placeholder. Stream will overwrite ASAP.
      debugPrint('GPS fix timed out — using placeholder; stream will correct it.');
      return Position(
        latitude: 0.0,
        longitude: 0.0,
        timestamp: DateTime.now(),
        accuracy: 0.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      );
    }
  }

  void dispose() {
    _gpsSub?.cancel();
    _receiverGpsSub?.cancel();
    _timeout?.cancel();
    _ctrl.close();
  }
}
