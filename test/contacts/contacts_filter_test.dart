// test/contacts/contacts_filter_test.dart
//
// Pure-logic tests for the top-level filterContacts() function used
// by ContactsScreen.

import 'package:flutter_test/flutter_test.dart';
import 'package:tapguard/data/models/contact_model.dart';
import 'package:tapguard/presentation/contacts/contacts_screen.dart';

ContactModel _c({
  required String uid,
  required String name,
  String email = '',
  String phone = '',
  int priority = 0,
  bool isEmergencyContact = false,
}) =>
    ContactModel(
      uid: uid,
      name: name,
      email: email,
      phoneNumber: phone,
      priority: priority,
      isEmergencyContact: isEmergencyContact,
      addedAt: DateTime.utc(2026, 1, 1),
      addedByUid: 'me',
    );

void main() {
  final sample = [
    _c(uid: 'a', name: 'Alice',   email: 'alice@x.com',   phone: '+1 555 0001', priority: 1),
    _c(uid: 'b', name: 'Bob',     email: 'bob@x.com',     phone: '+1 555 0002', priority: 2),
    _c(uid: 'c', name: 'Charlie', email: 'charlie@x.com', phone: '+1 555 0003', priority: 3, isEmergencyContact: true),
    _c(uid: 'd', name: 'Mom',     email: 'mom@x.com',     phone: '+1 555 9999', priority: 1, isEmergencyContact: true),
  ];

  group('filterContacts', () {
    test('no filters returns all contacts', () {
      expect(filterContacts(sample).length, 4);
    });

    test('empty string query returns all', () {
      expect(filterContacts(sample, query: '').length, 4);
    });

    test('whitespace-only query returns all', () {
      expect(filterContacts(sample, query: '   ').length, 4);
    });

    test('search by name (case-insensitive)', () {
      expect(filterContacts(sample, query: 'ali').map((c) => c.uid), ['a']);
      expect(filterContacts(sample, query: 'MOM').map((c) => c.uid), ['d']);
    });

    test('search by email', () {
      expect(filterContacts(sample, query: 'bob@x').map((c) => c.uid), ['b']);
    });

    test('search by phone', () {
      expect(
        filterContacts(sample, query: '9999').map((c) => c.uid),
        ['d'],
      );
    });

    test('priority filter P1', () {
      expect(
        filterContacts(sample, priority: 1).map((c) => c.uid).toList()..sort(),
        ['a', 'd'],
      );
    });

    test('priority filter P2', () {
      expect(filterContacts(sample, priority: 2).map((c) => c.uid), ['b']);
    });

    test('priority filter P3', () {
      expect(filterContacts(sample, priority: 3).map((c) => c.uid), ['c']);
    });

    test('emergency-only filter shows only emergency contacts', () {
      expect(
        filterContacts(sample, emergencyOnly: true).map((c) => c.uid).toList()
          ..sort(),
        ['c', 'd'],
      );
    });

    test('combined search + priority filter', () {
      // No contact with priority 1 named "Bob".
      expect(filterContacts(sample, query: 'bob', priority: 1), isEmpty);
      // Mom has priority 1.
      expect(
        filterContacts(sample, query: 'mom', priority: 1).map((c) => c.uid),
        ['d'],
      );
    });

    test('combined search + emergency filter', () {
      expect(
        filterContacts(sample, query: 'alice', emergencyOnly: true),
        isEmpty,
      );
      expect(
        filterContacts(sample, query: 'mom', emergencyOnly: true).map((c) => c.uid),
        ['d'],
      );
    });

    test('non-matching query returns empty list', () {
      expect(filterContacts(sample, query: 'zzz_no_match_zzz'), isEmpty);
    });

    test('empty contact list returns empty result for any filter', () {
      expect(filterContacts(const [], query: 'anything'), isEmpty);
      expect(filterContacts(const [], priority: 1), isEmpty);
      expect(filterContacts(const [], emergencyOnly: true), isEmpty);
    });
  });
}