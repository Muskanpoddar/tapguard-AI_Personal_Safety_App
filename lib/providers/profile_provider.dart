import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:tapguard/data/models/user_model.dart';
import 'package:tapguard/data/models/contact_model.dart';

final firestore = FirebaseFirestore.instance;
final auth = FirebaseAuth.instance;

// Current user profile
final currentUserProvider = StreamProvider<UserModel?>((ref) {
  final user = auth.currentUser;
  if (user == null) return Stream.value(null);

  return firestore.collection('users').doc(user.uid).snapshots().map((doc) {
    if (doc.exists) {
      return UserModel.fromMap(doc.data()!, doc.id);
    }
    return null;
  });
});

// User's trusted contacts
final userContactsProvider = StreamProvider.family<List<ContactModel>, String>((
  ref,
  userId,
) {
  return firestore
      .collection('users')
      .doc(userId)
      .collection('contacts')
      .orderBy('priority', descending: true)
      .orderBy('addedAt', descending: true)
      .snapshots()
      .map((snapshot) {
        return snapshot.docs
            .map((doc) => ContactModel.fromMap(doc.data(), doc.id))
            .toList();
      });
});

// Get specific contact details
final contactDetailsProvider = FutureProvider.family<ContactModel?, String>((
  ref,
  contactUid,
) async {
  try {
    final currentUser = auth.currentUser;
    if (currentUser == null) return null;

    final doc = await firestore
        .collection('users')
        .doc(currentUser.uid)
        .collection('contacts')
        .doc(contactUid)
        .get();

    if (doc.exists) {
      return ContactModel.fromMap(doc.data()!, doc.id);
    }
    return null;
  } catch (e) {
    debugPrint('Error fetching contact: $e');
    return null;
  }
});

// Profile service for mutations
final profileServiceProvider = Provider((ref) {
  return ProfileService();
});

class ProfileService {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // Create the user document on first login (post-OTP, pre-home).
  Future<bool> createUserProfile({
    required String name,
    required String email,
    String phoneNumber = '',
    int avatarColor = 0,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      final now = DateTime.now();
      final user = UserModel(
        uid: currentUser.uid,
        email: email.trim().toLowerCase(),
        phoneNumber: phoneNumber.trim(),
        name: name.trim(),
        avatarColor: avatarColor,
        createdAt: now,
        updatedAt: now,
      );

      await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .set(user.toMap(), SetOptions(merge: false));

      return true;
    } catch (e) {
      debugPrint('Error creating profile: $e');
      return false;
    }
  }

  // Add a trusted contact
  Future<bool> addTrustedContact({
    required String contactUid,
    required String contactName,
    required String contactEmail,
    required String contactPhone,
    required bool isEmergency,
    int priority = 3,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      final contact = ContactModel(
        uid: contactUid,
        email: contactEmail.trim().toLowerCase(),
        phoneNumber: contactPhone.trim(),
        name: contactName.trim(),
        isEmergencyContact: isEmergency,
        priority: priority,
        addedAt: DateTime.now(),
        addedByUid: currentUser.uid,
      );

      await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('contacts')
          .doc(contactUid)
          .set(contact.toMap());

      // Update trusted contacts list in user document
      await _firestore.collection('users').doc(currentUser.uid).update({
        'trustedContactUids': FieldValue.arrayUnion([contactUid]),
        'updatedAt': DateTime.now().toIso8601String(),
      });

      return true;
    } catch (e) {
      debugPrint('Error adding contact: $e');
      return false;
    }
  }

  // Remove a trusted contact
  Future<bool> removeTrustedContact(String contactUid) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      // Clear emergencyContactUid if this was the primary
      final userDoc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();
      if (userDoc.exists &&
          userDoc.data()?['emergencyContactUid'] == contactUid) {
        await _firestore
            .collection('users')
            .doc(currentUser.uid)
            .update({'emergencyContactUid': null});
      }

      await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('contacts')
          .doc(contactUid)
          .delete();

      // Update trusted contacts list in user document
      await _firestore.collection('users').doc(currentUser.uid).update({
        'trustedContactUids': FieldValue.arrayRemove([contactUid]),
        'updatedAt': DateTime.now().toIso8601String(),
      });

      return true;
    } catch (e) {
      debugPrint('Error removing contact: $e');
      return false;
    }
  }

  // Update contact priority
  Future<bool> updateContactPriority(String contactUid, int newPriority) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('contacts')
          .doc(contactUid)
          .update({'priority': newPriority});

      return true;
    } catch (e) {
      debugPrint('Error updating priority: $e');
      return false;
    }
  }

  // Rename a contact (display name only — does not change auth name).
  Future<bool> updateContactName(String contactUid, String newName) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      final trimmed = newName.trim();
      if (trimmed.isEmpty) return false;

      await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('contacts')
          .doc(contactUid)
          .update({'name': trimmed});

      return true;
    } catch (e) {
      debugPrint('Error renaming contact: $e');
      return false;
    }
  }

  // Set / unset emergency contact
  Future<bool> setEmergencyContact(String contactUid, bool isEmergency) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      // If we're setting a new emergency contact, clear isEmergencyContact
      // on every other contact first so only one is "primary".
      if (isEmergency) {
        final allContacts = await _firestore
            .collection('users')
            .doc(currentUser.uid)
            .collection('contacts')
            .get();
        for (final doc in allContacts.docs) {
          if (doc.id != contactUid && (doc.data()['isEmergencyContact'] == true)) {
            await doc.reference.update({'isEmergencyContact': false});
          }
        }
      }

      await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('contacts')
          .doc(contactUid)
          .update({'isEmergencyContact': isEmergency});

      await _firestore.collection('users').doc(currentUser.uid).update({
        'emergencyContactUid': isEmergency ? contactUid : null,
        'updatedAt': DateTime.now().toIso8601String(),
      });

      return true;
    } catch (e) {
      debugPrint('Error setting emergency contact: $e');
      return false;
    }
  }

  // Update editable profile fields (name, email, phone, avatar color).
  Future<bool> updateUserProfile({
    String? name,
    String? email,
    String? phoneNumber,
    int? avatarColor,
    String? profileImageUrl,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      final updates = <String, dynamic>{
        'updatedAt': DateTime.now().toIso8601String(),
      };
      if (name != null) updates['name'] = name.trim();
      if (email != null) updates['email'] = email.trim().toLowerCase();
      if (phoneNumber != null) updates['phoneNumber'] = phoneNumber.trim();
      if (avatarColor != null) updates['avatarColor'] = avatarColor;
      if (profileImageUrl != null) updates['profileImageUrl'] = profileImageUrl;

      await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .update(updates);

      return true;
    } catch (e) {
      debugPrint('Error updating profile: $e');
      return false;
    }
  }
}
