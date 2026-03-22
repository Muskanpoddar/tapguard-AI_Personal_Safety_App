// lib/data/services/notification_service.dart
//
// Uses OneSignal for push notifications (completely free, no billing needed)
// OneSignal App ID: f6df91d0-1058-4e27-9884-31cc4a53e480
//
// FLOW:
//  1. On login → save OneSignal player ID to Firestore
//  2. Timer ends on Phone A → get contact's player ID from Firestore
//  3. Call OneSignal REST API → Phone B gets push notification + vibration

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:vibration/vibration.dart';

class NotificationService {
  static final NotificationService _i = NotificationService._();
  factory NotificationService() => _i;
  NotificationService._();

  static const String _appId = 'f6df91d0-1058-4e27-9884-31cc4a53e480';

  // OneSignal REST API key — get from OneSignal Dashboard
  // Settings → Keys & IDs → REST API Key
  static const String _restApiKey =
      'Yos_v2_app_63pzduaqlbhcpgeeghgeuu7eqca74yy6i6mu73ed36vjyy6jejpepf2gup6fpbwrmbtn7h5yv4iddmznycbsx5bdapiriqbaylouoyi';

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ── Initialize — call once in main.dart ──────────────────────────────────
  Future<void> initialize() async {
    // 1. Initialize OneSignal
    OneSignal.initialize(_appId);

    // 2. Request notification permission
    await OneSignal.Notifications.requestPermission(true);

    // 3. Save player ID to Firestore when available
    OneSignal.User.pushSubscription.addObserver((state) {
      final playerId = state.current.id;
      if (playerId != null) {
        _savePlayerId(playerId);
      }
    });

    // 4. Handle foreground notifications
    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      // Show notification even when app is open
      event.notification.display();

      // Vibrate based on notification type
      final type = event.notification.additionalData?['type'] ?? '';
      _vibrateForType(type);
    });

    // 5. Handle notification taps
    OneSignal.Notifications.addClickListener((event) {
      debugPrint('Notification tapped: ${event.notification.additionalData}');
    });

    // 6. Try to get and save player ID immediately
    await _saveCurrentPlayerId();
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

  Future<void> _savePlayerId(String playerId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).set({
        'oneSignalPlayerId': playerId,
        'playerIdUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('OneSignal player ID saved: $playerId');
    } catch (e) {
      debugPrint('Error saving player ID: $e');
    }
  }

  // ── Send notification to a specific user ─────────────────────────────────
  // Called directly from Flutter app — no backend needed!
  Future<bool> sendNotificationToUser({
    required String targetUid,
    required String title,
    required String body,
    required String type,
    Map<String, String>? extraData,
  }) async {
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
  Future<void> alertContactsTimerEnded({
    required String ownerUid,
    required String ownerName,
    required String sessionId,
  }) async {
    try {
      // Get all active contacts
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

      // Send to each contact
      for (final doc in contactsSnap.docs) {
        final contactUid = doc.id;
        await sendNotificationToUser(
          targetUid: contactUid,
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
