// lib/data/services/sos_service.dart
//
// All SOS business logic, extracted from the original inline implementation
// in `presentation/sos/sos_screen.dart`. Keeps the screen a thin UI layer
// that just watches `sosStateProvider` and renders the result.
//
// Responsibilities:
//   * Update the SOS flag on the user's Firestore document
//   * Look up the user's name + current GPS
//   * Build a Google Maps link
//   * Send SMS directly to each trusted contact via the `telephony` package
//     (priority-sorted, real-time dispatch events emitted on a broadcast
//     stream so the UI can render a live log)
//   * Write a notification doc to each contact's subcollection
//   * Cancel the SOS and clear the flag
//
// Backwards compatible: `triggerSos` / `cancelSos` signatures unchanged, so
// the existing call sites in `live_session_screen.dart` still compile.

import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:telephony/telephony.dart';

import 'session_service.dart';

/// Status of a single contact's SOS dispatch, emitted on the broadcast
/// stream as each contact is processed.
enum DispatchStatus { sending, sent, failed, skipped }

/// One event per contact per attempt. Emitted in real time from
/// [SosService.dispatchStream] so the UI can render a live log.
class DispatchEvent {
  const DispatchEvent({
    required this.contactUid,
    required this.contactName,
    required this.phone,
    required this.status,
    this.error,
  });

  final String contactUid;
  final String contactName;
  final String phone;
  final DispatchStatus status;
  final String? error;

  @override
  String toString() =>
      'DispatchEvent($contactName, $phone, $status${error != null ? ', err=$error' : ''})';
}

class SosService {
  SosService({
    FirebaseFirestore? db,
    FirebaseAuth? auth,
    Telephony? telephony,
    SessionService? sessions,
    Battery? battery,
  })  : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _telephony = telephony ?? Telephony.instance,
        _sessions = sessions ?? SessionService(),
        _battery = battery ?? Battery();

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final Telephony _telephony;
  final SessionService _sessions;
  final Battery _battery;

  /// Session id created for the current SOS, if any. Carried so
  /// `cancelSos` can end the live-stream too.
  String? _activeSosSessionId;

  // ── Dispatch stream (live per-contact progress for the UI) ────────────────
  final _dispatchCtrl = StreamController<DispatchEvent>.broadcast();
  Stream<DispatchEvent> get dispatchStream => _dispatchCtrl.stream;

  void _emit(DispatchEvent e) {
    if (_dispatchCtrl.isClosed) return;
    _dispatchCtrl.add(e);
  }

  // ── Permission gate (call once before first SOS) ──────────────────────────
  /// Returns true if the user grants SEND_SMS permission. Falls back to
  /// false on Android < 4.4 or any error — caller should still proceed
  /// with Firestore-only dispatch in that case.
  Future<bool> requestSmsPermission() async {
    try {
      final granted = await _telephony.requestSmsPermissions ?? false;
      debugPrint('[SosService] SMS permission granted=$granted');
      return granted;
    } catch (e) {
      debugPrint('[SosService] requestSmsPermission error: $e');
      return false;
    }
  }

  // ── Trigger SOS ────────────────────────────────────────────────────────────
  /// 1. Set `sosActive: true` on the user doc.
  /// 2. Read user name + current GPS.
  /// 3. SMS each trusted contact (priority-sorted) via direct telephony.
  /// 4. Write a notification doc to each contact.
  /// Returns the number of contacts that were notified.
  Future<int> triggerSos({bool fromRisk = false}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return 0;

    await _updateFirestore(uid, active: true);

    return _dispatchToContacts(uid);
  }

  // ── Cancel SOS ────────────────────────────────────────────────────────────
  Future<void> cancelSos() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _updateFirestore(uid, active: false);
    // Tear down the live session we opened for the SOS broadcast so the
    // shareUrl stops serving live GPS.
    if (_activeSosSessionId != null) {
      try {
        await _sessions.endSession();
      } catch (e) {
        debugPrint('[SosService] Failed to end SOS session: $e');
      }
      _activeSosSessionId = null;
    }
  }

  // ── Internal helpers ───────────────────────────────────────────────────────
  Future<void> _updateFirestore(String uid, {required bool active}) async {
    try {
      await _db.collection('users').doc(uid).set({
        'sosActive': active,
        'sosTriggeredAt':
            active ? FieldValue.serverTimestamp() : null,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[SosService] Failed to update SOS flag: $e');
    }
  }

  Future<int> _dispatchToContacts(String uid) async {
    int notified = 0;
    try {
      // 1. Read user name
      String name = 'User';
      String ownerPhone = '';
      final userSnap = await _db.collection('users').doc(uid).get();
      if (userSnap.exists) {
        name = (userSnap.data()?['name'] as String?) ?? name;
        ownerPhone = (userSnap.data()?['phoneNumber'] as String?) ?? '';
      }

      // 2. GPS — try last-known first (instant, may be stale but better
      // than no pin), fall back to fresh fix with hard timeout.
      double? lat;
      double? lng;
      try {
        final last = await Geolocator.getLastKnownPosition().timeout(
          const Duration(milliseconds: 500),
          onTimeout: () => throw TimeoutException('last-known timeout'),
        );
        if (last != null &&
            (last.latitude != 0.0 || last.longitude != 0.0)) {
          lat = last.latitude;
          lng = last.longitude;
        }
      } catch (_) {}
      if (lat == null || lng == null) {
        try {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
            ),
          ).timeout(
            const Duration(seconds: 3),
            onTimeout: () => throw TimeoutException('GPS fix timeout'),
          );
          lat = pos.latitude;
          lng = pos.longitude;
        } catch (e) {
          debugPrint('[SosService] GPS unavailable: $e');
        }
      }

      // 3. Open a live session so the shareUrl can be included in the
      // SMS — recipient can tap to watch your location in real time.
      String shareUrl = '';
      try {
        final session = await _sessions.createSession(
          ownerName: name,
          ownerPhone: ownerPhone,
        );
        shareUrl = session.shareUrl;
        _activeSosSessionId = session.sessionId;
        debugPrint('[SosService] SOS session created: ${session.sessionId}');
      } catch (e) {
        debugPrint('[SosService] Session create failed, sending without link: $e');
      }

      // 4. Battery level (best-effort, omit if unavailable)
      int? batteryPct;
      try {
        batteryPct = await _battery.batteryLevel;
      } catch (_) {}

      // 5. Build the multi-part SMS body.
      final mapsLine = (lat != null && lng != null)
          ? 'Maps: https://maps.google.com/?q=$lat,$lng'
          : null;
      final coordsLine = (lat != null && lng != null) ? '$lat,$lng' : null;
      final liveLine =
          shareUrl.isNotEmpty ? 'Live: $shareUrl' : null;
      final batteryLine = batteryPct != null ? 'Battery: $batteryPct%' : null;
      final lines = <String>[
        'SOS! $name needs help.',
        ?liveLine,
        ?mapsLine,
        if (coordsLine != null) 'Coords: $coordsLine',
        ?batteryLine,
      ];
      final message = lines.join('\n');

      // 6. Direct SMS + notification per contact, lowest priority first
      final contactsSnap = await _db
          .collection('users')
          .doc(uid)
          .collection('contacts')
          .orderBy('priority', descending: false)
          .get();

      // Parallel dispatch — each contact's SMS + notification write runs
      // in its own unawaited future. Total wall-clock time becomes the
      // max of the individual SMS latencies (~1-2 s each) instead of
      // the sum. This is critical because the SOS trigger() is invoked
      // from the UI isolate; sequential awaits here piled up to 6+ s
      // across multiple contacts and tripped the OneSignal ANR
      // watchdog.
      for (final doc in contactsSnap.docs) {
        final phone = (doc.data()['phoneNumber'] as String?) ?? '';
        final contactName = (doc.data()['name'] as String?) ?? 'Contact';
        final priority = (doc.data()['priority'] as num?)?.toInt() ?? 99;
        final contactUid = doc.id;

        if (phone.isEmpty) {
          _emit(DispatchEvent(
            contactUid: contactUid,
            contactName: contactName,
            phone: '',
            status: DispatchStatus.skipped,
            error: 'no phone number',
          ));
          // Still write a Firestore notification if the contact is a
          // real account (skip for placeholder UIDs).
          if (!_isPlaceholderUid(contactUid)) {
            unawaited(_writeNotification(contactUid, uid, name, shareUrl));
          }
        } else {
          _emit(DispatchEvent(
            contactUid: contactUid,
            contactName: contactName,
            phone: phone,
            status: DispatchStatus.sending,
          ));
          notified++;
          // Fire-and-forget: the statusListener inside _sendSms fires
          // the terminal DispatchEvent (sent/failed) when the OS reports
          // back. We don't await it from the trigger() path, so the
          // UI thread is freed immediately.
          unawaited(_sendSmsAsync(contactUid, contactName, phone, message));
          if (!_isPlaceholderUid(contactUid)) {
            unawaited(_writeNotification(contactUid, uid, name, shareUrl));
          }
        }
        debugPrint(
          '[SosService] Dispatched to $contactName (priority $priority)',
        );
      }
    } catch (e) {
      debugPrint('[SosService] Dispatch failed: $e');
    }
    return notified;
  }

  Future<bool> _sendSms(String phone, String message) async {
    try {
      // Direct send — no SMS composer is opened. telephony 0.2.0 reports
      // back via the per-call `statusListener` once the OS has handed
      // the message to the carrier. We treat the call itself as success
      // unless the platform itself throws.
      await _telephony.sendSms(
        to: phone,
        message: message,
        statusListener: (SendStatus status) {
          if (status == SendStatus.SENT) {
            debugPrint('[SosService] SMS sent → $phone');
          } else if (status == SendStatus.DELIVERED) {
            debugPrint('[SosService] SMS delivered → $phone');
          } else {
            debugPrint(
              '[SosService] SMS status for $phone: ${status.name}',
            );
          }
        },
      );
      return true;
    } catch (e) {
      debugPrint('[SosService] SMS send error: $e');
      return false;
    }
  }

  /// Fire-and-forget wrapper used by the parallel dispatch loop.
  /// Emits the terminal DispatchEvent (sent/failed) when the OS
  /// reports back so the UI's live log row gets the final status.
  Future<void> _sendSmsAsync(
    String contactUid,
    String contactName,
    String phone,
    String message,
  ) async {
    final ok = await _sendSms(phone, message);
    _emit(DispatchEvent(
      contactUid: contactUid,
      contactName: contactName,
      phone: phone,
      status: ok ? DispatchStatus.sent : DispatchStatus.failed,
      error: ok ? null : 'SMS dispatch failed',
    ));
  }

  /// True for placeholder contact UIDs that came from QR/NFC pairings
  /// — no real Firebase account exists for them. Cross-user Firestore
  /// writes into their /notifications or /sharedSessions are blocked
  /// by the rules, and there's no account to receive push anyway.
  bool _isPlaceholderUid(String uid) {
    return uid.startsWith('qr_contact_') ||
        uid.startsWith('nfc_') ||
        uid.contains('/') ||
        uid.isEmpty;
  }

  Future<void> _writeNotification(
    String contactUid,
    String fromUid,
    String fromName,
    String shareUrl,
  ) async {
    try {
      await _db
          .collection('users')
          .doc(contactUid)
          .collection('notifications')
          .add({
        'type': 'sos_alert',
        'fromUid': fromUid,
        'fromName': fromName,
        'message': 'SOS ALERT! $fromName needs help immediately.',
        'shareUrl': shareUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'read': false,
      });
    } catch (e) {
      debugPrint('[SosService] Notification write failed: $e');
    }
  }

  void dispose() {
    _dispatchCtrl.close();
  }
}