// lib/providers/session_provider.dart
//
// Riverpod wrapper around SessionService. Exposes the live
// `SessionModel?` stream and provides imperative actions
// (create / end) that any widget can trigger.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tapguard/data/models/contact_model.dart';
import 'package:tapguard/data/models/session_model.dart';
import 'package:tapguard/data/services/session_service.dart';

/// The currently-active session (null when no session is active).
final activeSessionProvider = StreamProvider<SessionModel?>((ref) {
  final service = SessionService();
  return service.sessionStream;
});

/// Synchronous read of the active session.
final currentSessionProvider = Provider<SessionModel?>((ref) {
  final async = ref.watch(activeSessionProvider);
  return async.maybeWhen(data: (s) => s, orElse: () => null);
});

/// True when a session is currently active on this device.
final hasActiveSessionProvider = Provider<bool>((ref) {
  return ref.watch(currentSessionProvider)?.isActive == true;
});

/// Action provider — wraps SessionService so widgets can call these
/// without depending on the service directly.
final sessionActionsProvider = Provider<SessionActions>((ref) {
  return SessionActions(SessionService());
});

class SessionActions {
  SessionActions(this._service);
  final SessionService _service;

  /// Create a new session (Phone A / "owner").
  Future<SessionModel> create({
    required String ownerName,
    required String ownerPhone,
    Duration timeout = const Duration(hours: 2),
  }) {
    return _service.createSession(
      ownerName: ownerName,
      ownerPhone: ownerPhone,
      timeout: timeout,
    );
  }

  /// Open a fresh session with an already-paired [contact] — no
  /// QR/NFC re-pair required. Pre-fills the session with the
  /// contact's UID/name/phone and pushes them an invite.
  Future<SessionModel> startForContact(
    ContactModel contact, {
    Duration timeout = const Duration(hours: 2),
  }) {
    return _service.createSessionForContact(
      contact: contact,
      timeout: timeout,
    );
  }

  /// Watch an existing session by id (Phone B / "receiver" use case).
  Stream<SessionModel?> watch(String sessionId) {
    return _service.watchSession(sessionId);
  }

  /// Start streaming the receiver's GPS to an existing session.
  void startReceiverStream(String sessionId) {
    _service.startReceiverStream(sessionId);
  }

  /// Stop the receiver GPS stream.
  void stopReceiverStream() {
    _service.stopReceiverStream();
  }

  /// End the current session.
  Future<void> end() => _service.endSession();
}

/// Sessions that have been shared with the current user (as receiver).
/// Source: `users/{myUid}/sharedSessions` (written by the owner phone
/// when they tap "Share Live Location"). Used by the home screen to
/// surface a banner so the receiver knows there's a session waiting.
class SharedSession {
  const SharedSession({
    required this.sessionId,
    required this.ownerUid,
    required this.ownerName,
    required this.shareUrl,
    required this.isActive,
  });

  final String sessionId;
  final String ownerUid;
  final String ownerName;
  final String shareUrl;
  final bool isActive;
}

final sharedSessionsProvider = StreamProvider<List<SharedSession>>((ref) {
  final auth = FirebaseAuth.instance;
  return auth.authStateChanges().asyncExpand((user) {
    if (user == null) return Stream.value(<SharedSession>[]);
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('sharedSessions')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => SharedSession(
                  sessionId: d.id,
                  ownerUid: d.data()['ownerUid'] as String? ?? '',
                  ownerName: d.data()['ownerName'] as String? ?? 'Contact',
                  shareUrl: d.data()['shareUrl'] as String? ?? '',
                  isActive: d.data()['isActive'] as bool? ?? false,
                ))
            .toList());
  });
});
