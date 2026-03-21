// lib/data/services/notification_service.dart
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';

// Background message handler — must be top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Background message: ${message.notification?.title}');
}

class NotificationService {
  static final NotificationService _i = NotificationService._();
  factory NotificationService() => _i;
  NotificationService._();

  final _fcm = FirebaseMessaging.instance;
  final _localNotif = FlutterLocalNotificationsPlugin();
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ── Initialize — call once in main.dart ──────────────────────────────────
  Future<void> initialize() async {
    // 1. Request permission
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: true,
    );

    // 2. Setup local notifications
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initSettings = InitializationSettings(android: androidSettings);

    await _localNotif.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // 3. Create notification channel for Android
    final channel = AndroidNotificationChannel(
      'tapguard_alerts',
      'TapGuard Safety Alerts',
      description: 'Safety alerts from TapGuard',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList(const [0, 500, 200, 500]),
    );

    await _localNotif
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    // 4. Handle background messages
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 5. Handle foreground messages
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // 6. Save FCM token to Firestore
    await saveFcmToken();

    // 7. Refresh token when it changes
    _fcm.onTokenRefresh.listen((token) async {
      await _saveToken(token);
    });
  }

  // ── Save FCM token to Firestore ───────────────────────────────────────────
  Future<void> saveFcmToken() async {
    try {
      final token = await _fcm.getToken();
      if (token != null) await _saveToken(token);
    } catch (e) {
      debugPrint('FCM token error: $e');
    }
  }

  Future<void> _saveToken(String token) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).set({
        'fcmToken': token,
        'tokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('FCM token saved: ${token.substring(0, 20)}...');
    } catch (e) {
      debugPrint('Error saving token: $e');
    }
  }

  // ── Handle foreground notification ────────────────────────────────────────
  void _onForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    final type = message.data['type'] ?? '';

    // Vibrate based on type
    _vibrateForType(type);

    // Show local notification
    _localNotif.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'tapguard_alerts',
          'TapGuard Safety Alerts',
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          vibrationPattern: type == 'timer_ended'
              ? Int64List.fromList([0, 500, 200, 500, 200, 500])
              : Int64List.fromList([0, 300, 100, 300]),
          icon: '@mipmap/ic_launcher',
          color: type == 'timer_ended'
              ? const Color(0xFFFF3B30)
              : const Color(0xFF7C4DFF),
          fullScreenIntent: type == 'timer_ended',
        ),
      ),
      payload: type,
    );
  }

  // ── Vibrate patterns ──────────────────────────────────────────────────────
  Future<void> _vibrateForType(String type) async {
    if (!await Vibration.hasVibrator()) return;

    switch (type) {
      case 'timer_ended':
        // Urgent — long vibration pattern
        Vibration.vibrate(
          pattern: [0, 800, 200, 800, 200, 800],
          intensities: [0, 255, 0, 255, 0, 255],
        );
        break;
      case 'user_safe':
        // Gentle — short single vibration
        Vibration.vibrate(duration: 300);
        break;
      case 'session_ended':
        // Medium — two short vibrations
        Vibration.vibrate(pattern: [0, 300, 150, 300]);
        break;
      default:
        Vibration.vibrate(duration: 200);
    }
  }

  // ── Vibrate on timer end (called locally from active session screen) ──────
  Future<void> vibrateTimerEnd() async {
    if (!await Vibration.hasVibrator()) return;
    Vibration.vibrate(
      pattern: [0, 1000, 300, 1000, 300, 1000],
      intensities: [0, 255, 0, 255, 0, 255],
    );
  }

  // ── Stop vibration ────────────────────────────────────────────────────────
  Future<void> stopVibration() async {
    if (await Vibration.hasVibrator()) {
      Vibration.cancel();
    }
  }

  // ── Show local alert notification ─────────────────────────────────────────
  Future<void> showLocalAlert({
    required String title,
    required String body,
    bool isUrgent = false,
  }) async {
    await _localNotif.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'tapguard_alerts',
          'TapGuard Safety Alerts',
          importance: isUrgent ? Importance.max : Importance.high,
          priority: isUrgent ? Priority.max : Priority.high,
          playSound: true,
          enableVibration: true,
          fullScreenIntent: isUrgent,
          color: isUrgent ? const Color(0xFFFF3B30) : const Color(0xFF7C4DFF),
        ),
      ),
    );
  }

  void _onNotificationTap(NotificationResponse response) {
    debugPrint('Notification tapped: ${response.payload}');
    // TODO: Navigate based on payload type
  }
}
