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
      .collection('trustedContacts')
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
        .collection('trustedContacts')
        .doc(contactUid)
        .get();

    if (doc.exists) {
      return ContactModel.fromMap(doc.data()!, doc.id);
    }
    return null;
  } catch (e) {
    print('Error fetching contact: $e');
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

  // Add a trusted contact
  Future<bool> addTrustedContact({
    required String contactUid,
    required String contactName,
    required String contactPhone,
    required bool isEmergency,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      final contact = ContactModel(
        uid: contactUid,
        phoneNumber: contactPhone,
        name: contactName,
        isEmergencyContact: isEmergency,
        addedAt: DateTime.now(),
        addedByUid: currentUser.uid,
      );

      await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('trustedContacts')
          .doc(contactUid)
          .set(contact.toMap());

      // Update trusted contacts list in user document
      await _firestore.collection('users').doc(currentUser.uid).update({
        'trustedContactUids': FieldValue.arrayUnion([contactUid]),
      });

      return true;
    } catch (e) {
      print('Error adding contact: $e');
      return false;
    }
  }

  // Remove a trusted contact
  Future<bool> removeTrustedContact(String contactUid) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('trustedContacts')
          .doc(contactUid)
          .delete();

      // Update trusted contacts list in user document
      await _firestore.collection('users').doc(currentUser.uid).update({
        'trustedContactUids': FieldValue.arrayRemove([contactUid]),
      });

      return true;
    } catch (e) {
      print('Error removing contact: $e');
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
          .collection('trustedContacts')
          .doc(contactUid)
          .update({'priority': newPriority});

      return true;
    } catch (e) {
      print('Error updating priority: $e');
      return false;
    }
  }

  // Set emergency contact
  Future<bool> setEmergencyContact(String contactUid, bool isEmergency) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('trustedContacts')
          .doc(contactUid)
          .update({'isEmergencyContact': isEmergency});

      if (isEmergency) {
        await _firestore.collection('users').doc(currentUser.uid).update({
          'emergencyContactUid': contactUid,
        });
      }

      return true;
    } catch (e) {
      print('Error setting emergency contact: $e');
      return false;
    }
  }

  // Update user profile
  Future<bool> updateUserProfile({
    required String name,
    String? profileImageUrl,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      await _firestore.collection('users').doc(currentUser.uid).update({
        'name': name,
        'profileImageUrl': profileImageUrl,
        'updatedAt': DateTime.now().toIso8601String(),
      });

      return true;
    } catch (e) {
      print('Error updating profile: $e');
      return false;
    }
  }
}
