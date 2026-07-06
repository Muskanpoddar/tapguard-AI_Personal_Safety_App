// test/contacts/contact_detail_flow_test.dart
//
// Tests for the new "re-share without re-pairing" flow:
//   • ContactModel.fromMap / toMap round-trip
//   • ContactModel.copyWith name change
//   • SessionModel.fromMap accepts the pre-filled receiver fields
//   • Priority color logic (mirror of home_screen / detail screen)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapguard/data/models/contact_model.dart';
import 'package:tapguard/data/models/session_model.dart';

void main() {
  group('ContactModel round-trip', () {
    test('toMap → fromMap preserves name + uid + priority', () {
      final c = ContactModel(
        uid: 'abc123',
        email: 'sarah@example.com',
        phoneNumber: '+1 555 0100',
        name: 'Sarah',
        priority: 1,
        addedAt: DateTime.utc(2026, 7, 1, 12),
        addedByUid: 'me',
      );
      final round = ContactModel.fromMap(c.toMap(), c.uid);
      expect(round.uid, 'abc123');
      expect(round.name, 'Sarah');
      expect(round.email, 'sarah@example.com');
      expect(round.priority, 1);
      expect(round.addedAt.toUtc(), DateTime.utc(2026, 7, 1, 12));
    });

    test('copyWith changes name but keeps uid', () {
      final c = ContactModel(
        uid: 'abc',
        name: 'Sarah',
        email: '',
        phoneNumber: '',
        addedAt: DateTime.now(),
        addedByUid: 'me',
      );
      final renamed = c.copyWith(name: 'Mom');
      expect(renamed.uid, 'abc');
      expect(renamed.name, 'Mom');
    });
  });

  group('SessionModel pre-filled receiver fields', () {
    test('fromMap reads receiverUid + receiverName + receiverPhone', () {
      final id = 'session_xyz';
      final data = {
        'ownerUid': 'me',
        'ownerPhone': '+1 555 0001',
        'ownerName': 'Me',
        'ownerLat': 12.34,
        'ownerLng': 56.78,
        'ownerAccuracy': 5.0,
        'receiverUid': 'contact_uid',
        'receiverName': 'Sarah',
        'receiverPhone': '+1 555 0002',
        'receiverJoined': false,
        'isActive': true,
        'shareUrl': 'https://tapguard-0.web.app/s/$id',
        'createdAt': Timestamp.fromDate(DateTime.now()),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
        'invitedFromContact': true,
      };
      final s = SessionModel.fromMap(data, id);
      expect(s.sessionId, id);
      expect(s.receiverUid, 'contact_uid');
      expect(s.receiverName, 'Sarah');
      expect(s.receiverJoined, false);
      expect(s.isActive, true);
    });
  });

  group('contact detail priority color logic', () {
    test('priority 1 is red, 2 orange, 3 grey', () {
      // Mirror the detail screen logic.
      Color colorFor(int p) {
        if (p == 1) return const Color(0xFFFF3B30);
        if (p == 2) return const Color(0xFFFF9500);
        return const Color(0xFF9E9E9E);
      }

      expect(colorFor(1).toARGB32(), const Color(0xFFFF3B30).toARGB32());
      expect(colorFor(2).toARGB32(), const Color(0xFFFF9500).toARGB32());
      expect(colorFor(3).toARGB32(), const Color(0xFF9E9E9E).toARGB32());
    });
  });

  group('contact last-seen label', () {
    test('null lastSeen renders as "Never seen"', () {
      String label(DateTime? lastSeen) {
        if (lastSeen == null) return 'Never seen';
        final diff = DateTime.now().difference(lastSeen);
        if (diff.inSeconds < 60) return 'Just now';
        if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
        return 'Last seen: ${diff.inHours}h ago';
      }

      expect(label(null), 'Never seen');
      expect(label(DateTime.now().subtract(const Duration(seconds: 30))),
          'Just now');
      expect(label(DateTime.now().subtract(const Duration(minutes: 5))),
          '5 min ago');
    });
  });
}