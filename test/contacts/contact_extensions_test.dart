// test/contacts/contact_extensions_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapguard/core/utils/contact_extensions.dart';
import 'package:tapguard/data/models/contact_model.dart';

ContactModel _c({
  String name = 'Test',
  bool isActive = false,
  DateTime? lastSeen,
  int priority = 0,
  bool isEmergencyContact = false,
}) =>
    ContactModel(
      uid: 'uid_${name.hashCode}',
      name: name,
      email: '$name@example.com',
      phoneNumber: '+1 555 0100',
      isActive: isActive,
      lastSeen: lastSeen,
      priority: priority,
      isEmergencyContact: isEmergencyContact,
      addedAt: DateTime.utc(2026, 1, 1),
      addedByUid: 'me',
    );

void main() {
  group('ContactStatus.statusLabel', () {
    test('null lastSeen returns "Never seen"', () {
      expect(_c().statusLabel, 'Never seen');
    });

    test('active contact returns "Active Now" regardless of lastSeen', () {
      expect(_c(isActive: true).statusLabel, 'Active Now');
    });

    test('<60s ago returns "Just now"', () {
      expect(
        _c(lastSeen: DateTime.now().subtract(const Duration(seconds: 30)))
            .statusLabel,
        'Just now',
      );
    });

    test('<60min ago returns "X min ago"', () {
      expect(
        _c(lastSeen: DateTime.now().subtract(const Duration(minutes: 5)))
            .statusLabel,
        'Last seen: 5 min ago',
      );
    });

    test('<24h ago returns "Xh ago"', () {
      expect(
        _c(lastSeen: DateTime.now().subtract(const Duration(hours: 3)))
            .statusLabel,
        'Last seen: 3h ago',
      );
    });

    test('>=24h ago returns "Xd ago"', () {
      expect(
        _c(lastSeen: DateTime.now().subtract(const Duration(days: 2)))
            .statusLabel,
        'Last seen: 2d ago',
      );
    });
  });

  group('priorityColor', () {
    test('priority 1 returns red', () {
      expect(priorityColor(1).toARGB32(), const Color(0xFFFF3B30).toARGB32());
    });

    test('priority 2 returns orange', () {
      expect(priorityColor(2).toARGB32(), const Color(0xFFFF9500).toARGB32());
    });

    test('priority 3+ returns grey', () {
      expect(priorityColor(3).toARGB32(), const Color(0xFF9E9E9E).toARGB32());
      expect(priorityColor(0).toARGB32(), const Color(0xFF9E9E9E).toARGB32());
      expect(priorityColor(99).toARGB32(), const Color(0xFF9E9E9E).toARGB32());
    });
  });
}