import 'package:cloud_firestore/cloud_firestore.dart';

class ContactModel {
  final String uid;
  final String email;
  final String phoneNumber;
  final String name;
  final String? profileImageUrl;
  final bool isEmergencyContact;
  final bool isActive;
  final DateTime? lastSeen;
  final int priority;
  final DateTime addedAt;
  final String addedByUid;
  final bool isVerified;
  final bool allowsLocationSharing;

  ContactModel({
    required this.uid,
    required this.email,
    required this.phoneNumber,
    required this.name,
    this.profileImageUrl,
    this.isEmergencyContact = false,
    this.isActive = false,
    this.lastSeen,
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
      'email': email,
      'phoneNumber': phoneNumber,
      'name': name,
      'profileImageUrl': profileImageUrl,
      'isEmergencyContact': isEmergencyContact,
      'isActive': isActive,
      'lastSeen': lastSeen != null
          ? Timestamp.fromDate(lastSeen!)
          : null,
      'priority': priority,
      'addedAt': Timestamp.fromDate(addedAt),
      'addedByUid': addedByUid,
      'isVerified': isVerified,
      'allowsLocationSharing': allowsLocationSharing,
    };
  }

  // Create from Firestore JSON
  factory ContactModel.fromMap(Map<String, dynamic> map, String docId) {
    final lastSeenTs = map['lastSeen'] as Timestamp?;
    return ContactModel(
      uid: docId,
      email: (map['email'] as String?) ?? '',
      phoneNumber: (map['phoneNumber'] as String?) ?? '',
      name: (map['name'] as String?) ?? '',
      profileImageUrl: map['profileImageUrl'] as String?,
      isEmergencyContact: (map['isEmergencyContact'] as bool?) ?? false,
      isActive: (map['isActive'] as bool?) ?? false,
      lastSeen: lastSeenTs?.toDate(),
      priority: (map['priority'] as num?)?.toInt() ?? 0,
      addedAt: (map['addedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      addedByUid: (map['addedByUid'] as String?) ?? '',
      isVerified: (map['isVerified'] as bool?) ?? false,
      allowsLocationSharing:
          (map['allowsLocationSharing'] as bool?) ?? true,
    );
  }

  // Copy with modifications
  ContactModel copyWith({
    String? uid,
    String? email,
    String? phoneNumber,
    String? name,
    String? profileImageUrl,
    bool? isEmergencyContact,
    bool? isActive,
    DateTime? lastSeen,
    int? priority,
    DateTime? addedAt,
    String? addedByUid,
    bool? isVerified,
    bool? allowsLocationSharing,
  }) {
    return ContactModel(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      name: name ?? this.name,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      isEmergencyContact: isEmergencyContact ?? this.isEmergencyContact,
      isActive: isActive ?? this.isActive,
      lastSeen: lastSeen ?? this.lastSeen,
      priority: priority ?? this.priority,
      addedAt: addedAt ?? this.addedAt,
      addedByUid: addedByUid ?? this.addedByUid,
      isVerified: isVerified ?? this.isVerified,
      allowsLocationSharing:
          allowsLocationSharing ?? this.allowsLocationSharing,
    );
  }
}
