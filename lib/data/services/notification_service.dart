// lib/data/services/notification_service.dart
//
// Uses OneSignal for push notifications (completely free, no billing needed)
// OneSignal App ID: f6df91d0-1058-4e27-9884-31cc4a53e480
//
// FLOW:
//  1. On login → save OneSignal player ID to Firestore
//  2. Timer ends on Phone A → get contact's player ID from Firestore
//  3. Call OneSignal REST API → Phone B gets push notification + vibration
//
// SECURITY NOTE: the REST API key below ships inside the APK. Anyone
// who unpacks the APK can use it to send push notifications to your
// users (impersonating your app). They cannot read user data. The
// only fully secure alternative is a server-side proxy, which would
// require Firebase billing (Blaze plan) — not viable for this free
// app. Keep this in mind if user base grows.

import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:vibration/vibration.dart';

import '../../core/routes/app_routes.dart';
import '../../main.dart' show rootNavigatorKey;

class NotificationService {
  static final NotificationService _i = NotificationService._();
  factory NotificationService() => _i;
  NotificationService._();

  // ─── OneSignal keys loaded from .env at runtime ───────────────────────────
  // Throws clearly if missing instead of silently using a stale value.
  static String get _appId =>
      dotenv.maybeGet('ONESIGNAL_APP_ID') ?? _missing('ONESIGNAL_APP_ID');

  // SECURITY NOTE: the REST API key still ships inside the APK.
  // Anyone who unpacks the APK can use it to send push notifications
  // to your users (impersonating your app). They cannot read user
  // data. The only fully secure alternative is a server-side proxy,
  // which would require Firebase billing (Blaze plan) — not viable
  // for this free app. Keep this in mind if user base grows.
  static String get _restApiKey =>
      dotenv.maybeGet('ONESIGNAL_REST_API_KEY') ??
      _missing('ONESIGNAL_REST_API_KEY');

  static String _missing(String key) {
    throw StateError(
      'NotificationService: missing "$key" in .env — see docs/SECURITY.md',
    );
  }

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ── Initialize — call once in main.dart ──────────────────────────────────
  // Sets up every trigger that should re-save the OneSignal player
  // ID for the current user:
  //   • on app start (cold boot)
  //   • on Firebase Auth state change (login / link / refresh)
  //   • on OneSignal subscription state change (initial / refresh)
  //   • on OneSignal permission change (user grants later)
  //   • on app foreground (subscription may have rotated)
  // Together these guarantee the Firestore `oneSignalPlayerId` field
  // is never stale for an authenticated user.
  Future<void> initialize() async {
    // 1. Initialize OneSignal
    OneSignal.initialize(_appId);

    // 2. Request notification permission
    await OneSignal.Notifications.requestPermission(true);

    // 3. Save player ID whenever the OneSignal subscription changes
    OneSignal.User.pushSubscription.addObserver((state) {
      final playerId = state.current.id;
      if (playerId != null) {
        _savePlayerId(playerId);
      }
    });

    // 3b. Save when the user grants permission later (OneSignal
    //     creates the subscription async in that case).
    OneSignal.Notifications.addPermissionObserver((state) {
      debugPrint('[Notif] OneSignal permission changed → $state');
      unawaited(retrySavePlayerId());
    });

    // 4. Handle foreground notifications
    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      event.notification.display();

      final type = event.notification.additionalData?['type'] ?? '';
      _vibrateForType(type);
    });

    // 5. Handle notification taps — route the user to the right screen
    //    based on the notification `type`.
    //    Supported types (set by the sender in the push payload's
    //    `data` field):
    //      • session_invite → opens LiveSessionScreen so the receiver
    //                         can Accept/Decline the live-location share
    //      • timer_ended    → opens LiveMapScreen so the contact can
    //                         see the owner's last-known location
    //      • user_safe      → opens HomeScreen
    //      • session_ended  → opens HomeScreen
    OneSignal.Notifications.addClickListener((event) {
      final data = event.notification.additionalData ?? <String, dynamic>{};
      final type = data['type'] as String? ?? '';
      final sessionId = data['sessionId'] as String?;

      debugPrint(
        'Notification tapped: type=$type sessionId=$sessionId',
      );

      // Wait until auth + the navigator are ready before pushing.
      // The OneSignal click listener can fire before Flutter's first
      // frame is built (cold start via notification tap), so guard
      // against an unready navigator.
      unawaited(_navigateForNotification(type, sessionId));
    });

    // 6. Re-save on every Firebase Auth state change. Covers:
    //    • anonymous sign-in (main.dart)
    //    • email-link upgrade (OTP screen)
    //    • returning user with cached credentials
    //    • account switch (future)
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) return;
      debugPrint('[Notif] auth changed (${user.uid}) — saving player ID');
      unawaited(retrySavePlayerId());
    });

    // 7. Re-save whenever the app comes to the foreground. The
    //    OneSignal SDK can rotate the player ID, and a fresh login
    //    on a different network may not have triggered the
    //    subscription observer yet.
    WidgetsBinding.instance.addObserver(_AppLifecycleObserver(this));

    // 8. Try to save player ID immediately (no-op if not ready)
    await _saveCurrentPlayerId();
  }

  // ── Navigation helper for notification taps ───────────────────────────────
  // Routes a tapped notification to the appropriate screen. If the
  // user isn't authenticated yet, wait for auth to settle (up to 5 s)
  // and bail out cleanly otherwise — the notification still showed,
  // they just won't be auto-routed to a session they can't view.
  Future<void> _navigateForNotification(
    String type,
    String? sessionId,
  ) async {
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) {
      // Navigator not mounted yet — try again on next frame. This can
      // happen on cold-start from a notification tap.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      return _navigateForNotification(type, sessionId);
    }

    // Wait briefly for auth to settle on cold-start.
    for (var i = 0; i < 20; i++) {
      if (_auth.currentUser != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (_auth.currentUser == null) {
      debugPrint('[Notif] click: no auth user — letting user land on splash');
      return;
    }

    switch (type) {
      case 'session_invite':
        // The LiveSessionScreen auto-discovers the session from the
        // user's `sharedSessions` subcollection, so we don't need to
        // pass the sessionId as an argument.
        navigator.pushNamed(AppRoutes.liveSession);
        break;
      case 'timer_ended':
        navigator.pushNamed(AppRoutes.liveMap);
        break;
      case 'user_safe':
      case 'session_ended':
        navigator.pushNamedAndRemoveUntil(
          AppRoutes.home,
          (route) => route.isFirst,
        );
        break;
      default:
        debugPrint('[Notif] click: unknown type "$type" — no-op');
    }
  }

  // ── Save player ID to Firestore ───────────────────────────────────────────
  Future<void> _saveCurrentPlayerId() async {
    try {
      final playerId = OneSignal.User.pushSubscription.id;
      if (playerId != null && playerId.isNotEmpty) {
        await _savePlayerId(playerId);
      }
    } catch (e) {
      debugPrint('Error getting player ID: $e');
    }
  }

  // ── Public retry — call after login ───────────────────────────────────────
  // OneSignal may not have a player ID immediately after launch
  // (push subscription is created async after permission grant).
  // This polls up to ~30 s and writes to Firestore as soon as the
  // ID becomes available. Safe to call from any post-auth point.
  Future<String?> retrySavePlayerId({
    Duration maxWait = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(maxWait);
    final backoffs = <Duration>[
      const Duration(seconds: 1),
      const Duration(seconds: 2),
      const Duration(seconds: 3),
      const Duration(seconds: 5),
      const Duration(seconds: 8),
      const Duration(seconds: 11),
    ];

    for (final wait in backoffs) {
      try {
        final id = OneSignal.User.pushSubscription.id;
        if (id != null && id.isNotEmpty) {
          await _savePlayerId(id);
          return id;
        }
      } catch (e) {
        debugPrint('retrySavePlayerId poll error: $e');
      }
      if (DateTime.now().add(wait).isAfter(deadline)) break;
      await Future.delayed(wait);
    }

    // One last shot with whatever's there now
    try {
      final id = OneSignal.User.pushSubscription.id;
      if (id != null && id.isNotEmpty) {
        await _savePlayerId(id);
        return id;
      }
    } catch (_) {}
    debugPrint('retrySavePlayerId: no player ID after ${maxWait.inSeconds}s');
    return null;
  }

  Future<void> _savePlayerId(String playerId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      debugPrint('[Notif] _savePlayerId: no auth user yet — skipping');
      return;
    }

    // Retry once after a short delay if Firestore is unreachable
    // (DNS glitch, cold start, etc.). Most calls succeed on the
    // first try; the retry handles the flaky-network case.
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        await _db.collection('users').doc(uid).set({
          'oneSignalPlayerId': playerId,
          // Alias so any caller looking for `fcmToken` finds the
          // push target too. Same string in both fields.
          'fcmToken': playerId,
          'playerIdUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('OneSignal player ID saved: $playerId (uid=$uid)');
        return;
      } catch (e) {
        debugPrint('[Notif] save attempt $attempt failed: $e');
        if (attempt == 2) rethrow;
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  // ── Send notification to a specific user ─────────────────────────────────
  // Direct OneSignal REST API call. Server-side proxy would need
  // Firebase billing, which is not viable for this free app.
  Future<bool> sendNotificationToUser({
    required String targetUid,
    required String title,
    required String body,
    required String type,
    Map<String, String>? extraData,
  }) async {
    // Placeholder UIDs (e.g. 'qr_contact_1783105180829', 'nfc_*') come
    // from pairings where the remote party was never authenticated, so
    // there is no real /users/{uid} doc and the Firestore rule denies
    // cross-user reads anyway. Skip the push instead of waiting for
    // PERMISSION_DENIED.
    if (targetUid.startsWith('qr_contact_') ||
        targetUid.startsWith('nfc_') ||
        targetUid.contains('/') ||
        targetUid.isEmpty) {
      debugPrint('Skipping push for non-account contact uid: $targetUid');
      return false;
    }

    try {
      // 1. Get target user's OneSignal player ID from Firestore
      final userDoc = await _db.collection('users').doc(targetUid).get();
      if (!userDoc.exists) return false;

      final playerId = userDoc.data()?['oneSignalPlayerId'] as String?;
      if (playerId == null || playerId.isEmpty) {
        debugPrint('No player ID for user $targetUid');
        return false;
      }

      // 2. Send via OneSignal REST API
      final data = {'type': type, ...?extraData};

      final response = await http.post(
        Uri.parse('https://onesignal.com/api/v1/notifications'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Basic $_restApiKey',
        },
        body: jsonEncode({
          'app_id': _appId,
          'include_player_ids': [playerId],
          'headings': {'en': title},
          'contents': {'en': body},
          'data': data,
          'android_channel_id': 'tapguard_alerts',
          'priority': type == 'timer_ended' ? 10 : 5,
          'android_accent_color': type == 'timer_ended'
              ? 'FFFF3B30'
              : 'FF7C4DFF',
          'small_icon': 'ic_stat_onesignal_default',
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('Notification sent to $targetUid ✅');
        return true;
      } else {
        debugPrint('Failed: ${response.statusCode} — ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Error sending notification: $e');
      return false;
    }
  }

  // ── Send timer ended alert to ALL active contacts ─────────────────────────
  // Client-side fan-out. The `onTimerEnded` Firestore trigger in
  // functions/index.js also fires on the same session-doc update
  // (it tries to use FCM with these player IDs, which silently fails
  // because OneSignal IDs ≠ FCM tokens). This loop is what actually
  // delivers the alert today.
  Future<void> alertContactsTimerEnded({
    required String ownerUid,
    required String ownerName,
    required String sessionId,
  }) async {
    try {
      final contactsSnap = await _db
          .collection('users')
          .doc(ownerUid)
          .collection('contacts')
          .where('isActive', isEqualTo: true)
          .get();

      if (contactsSnap.docs.isEmpty) {
        debugPrint('No active contacts to alert');
        return;
      }

      for (final doc in contactsSnap.docs) {
        await sendNotificationToUser(
          targetUid: doc.id,
          title: '⚠️ Check on $ownerName',
          body:
              '$ownerName\'s safety timer has ended. Please check if they are safe!',
          type: 'timer_ended',
          extraData: {
            'sessionId': sessionId,
            'ownerUid': ownerUid,
            'ownerName': ownerName,
          },
        );
      }
    } catch (e) {
      debugPrint('Error alerting contacts: $e');
    }
  }

  // ── Send "I am Safe" notification ─────────────────────────────────────────
  Future<void> notifyContactsUserSafe({
    required String ownerUid,
    required String ownerName,
  }) async {
    try {
      final contactsSnap = await _db
          .collection('users')
          .doc(ownerUid)
          .collection('contacts')
          .where('isActive', isEqualTo: true)
          .get();

      for (final doc in contactsSnap.docs) {
        await sendNotificationToUser(
          targetUid: doc.id,
          title: '✅ $ownerName is Safe',
          body: '$ownerName has confirmed they are safe.',
          type: 'user_safe',
          extraData: {'ownerName': ownerName},
        );
      }
    } catch (e) {
      debugPrint('Error sending safe notification: $e');
    }
  }

  // ── Send session ended notification ───────────────────────────────────────
  Future<void> notifySessionEnded({
    required String ownerUid,
    required String ownerName,
  }) async {
    try {
      final contactsSnap = await _db
          .collection('users')
          .doc(ownerUid)
          .collection('contacts')
          .where('isPaired', isEqualTo: true)
          .get();

      for (final doc in contactsSnap.docs) {
        await sendNotificationToUser(
          targetUid: doc.id,
          title: '🔒 Session Ended',
          body: '$ownerName has ended their safety session.',
          type: 'session_ended',
          extraData: {'ownerName': ownerName},
        );
      }
    } catch (e) {
      debugPrint('Error sending session ended notification: $e');
    }
  }

  // ── Vibration patterns ────────────────────────────────────────────────────
  Future<void> _vibrateForType(String type) async {
    if (!await Vibration.hasVibrator()) return;
    switch (type) {
      case 'timer_ended':
        Vibration.vibrate(
          pattern: [0, 800, 200, 800, 200, 800],
          intensities: [0, 255, 0, 255, 0, 255],
        );
        break;
      case 'user_safe':
        Vibration.vibrate(duration: 300);
        break;
      case 'session_ended':
        Vibration.vibrate(pattern: [0, 300, 150, 300]);
        break;
      default:
        Vibration.vibrate(duration: 200);
    }
  }

  // ── Vibrate locally when timer ends ──────────────────────────────────────
  Future<void> vibrateTimerEnd() async {
    if (!await Vibration.hasVibrator()) return;
    Vibration.vibrate(
      pattern: [0, 1000, 300, 1000, 300, 1000],
      intensities: [0, 255, 0, 255, 0, 255],
    );
  }

  Future<void> stopVibration() async {
    if (await Vibration.hasVibrator()) Vibration.cancel();
  }
}

// ── App lifecycle observer ─────────────────────────────────────────────────
// Re-saves the OneSignal player ID whenever the app comes back to
// the foreground. OneSignal can rotate its player ID, and on a
// returning user we may not have caught the rotation while
// backgrounded.
class _AppLifecycleObserver with WidgetsBindingObserver {
  final NotificationService _svc;
  _AppLifecycleObserver(this._svc);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[Notif] app resumed — saving player ID');
      unawaited(_svc.retrySavePlayerId());
    }
  }
}
