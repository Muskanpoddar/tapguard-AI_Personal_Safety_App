import 'package:cloud_firestore/cloud_firestore.dart';

class ContactModel {
  final String uid;
  final String phoneNumber;
  final String name;
  final String? profileImageUrl;
  final bool isEmergencyContact;
  final int priority;
  final DateTime addedAt;
  final String addedByUid;
  final bool isVerified;
  final bool allowsLocationSharing;

  ContactModel({
    required this.uid,
    required this.phoneNumber,
    required this.name,
    this.profileImageUrl,
    this.isEmergencyContact = false,
    this.priority = 0,
    required this.addedAt,
    required this.addedByUid,
    this.isVerified = false,
    this.allowsLocationSharing = true,
  });

  // Convert to Firestore JSON
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'phoneNumber': phoneNumber,
      'name': name,
      'profileImageUrl': profileImageUrl,
      'isEmergencyContact': isEmergencyContact,
      'priority': priority,
      'addedAt': Timestamp.fromDate(addedAt),
      'addedByUid': addedByUid,
      'isVerified': isVerified,
      'allowsLocationSharing': allowsLocationSharing,
    };
  }

  // Create from Firestore JSON
  factory ContactModel.fromMap(Map<String, dynamic> map, String docId) {
    return ContactModel(
      uid: docId,
      phoneNumber: map['phoneNumber'] ?? '',
      name: map['name'] ?? '',
      profileImageUrl: map['profileImageUrl'],
      isEmergencyContact: map['isEmergencyContact'] ?? false,
      priority: map['priority'] ?? 0,
      addedAt: (map['addedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      addedByUid: map['addedByUid'] ?? '',
      isVerified: map['isVerified'] ?? false,
      allowsLocationSharing: map['allowsLocationSharing'] ?? true,
    );
  }

  // Copy with modifications
  ContactModel copyWith({
    String? uid,
    String? phoneNumber,
    String? name,
    String? profileImageUrl,
    bool? isEmergencyContact,
    int? priority,
    DateTime? addedAt,
    String? addedByUid,
    bool? isVerified,
    bool? allowsLocationSharing,
  }) {
    return ContactModel(
      uid: uid ?? this.uid,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      name: name ?? this.name,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      isEmergencyContact: isEmergencyContact ?? this.isEmergencyContact,
      priority: priority ?? this.priority,
      addedAt: addedAt ?? this.addedAt,
      addedByUid: addedByUid ?? this.addedByUid,
      isVerified: isVerified ?? this.isVerified,
      allowsLocationSharing:
          allowsLocationSharing ?? this.allowsLocationSharing,
    );
  }
}
