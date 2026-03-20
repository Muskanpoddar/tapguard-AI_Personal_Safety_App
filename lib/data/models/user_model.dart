
class UserModel {
  final String uid;
  final String phoneNumber;
  final String name;
  final String? profileImageUrl;
  final String? emergencyContactUid;
  final List<String> trustedContactUids;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool nfcEnabled;
  final String? nfcTagId;

  UserModel({
    required this.uid,
    required this.phoneNumber,
    required this.name,
    this.profileImageUrl,
    this.emergencyContactUid,
    this.trustedContactUids = const [],
    required this.createdAt,
    this.updatedAt,
    this.nfcEnabled = true,
    this.nfcTagId,
  });

  // Convert to Firestore JSON
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'phoneNumber': phoneNumber,
      'name': name,
      'profileImageUrl': profileImageUrl,
      'emergencyContactUid': emergencyContactUid,
      'trustedContactUids': trustedContactUids,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'nfcEnabled': nfcEnabled,
      'nfcTagId': nfcTagId,
    };
  }

  // Create from Firestore JSON
  factory UserModel.fromMap(Map<String, dynamic> map, String docId) {
    return UserModel(
      uid: docId,
      phoneNumber: map['phoneNumber'] ?? '',
      name: map['name'] ?? '',
      profileImageUrl: map['profileImageUrl'],
      emergencyContactUid: map['emergencyContactUid'],
      trustedContactUids: List<String>.from(map['trustedContactUids'] ?? []),
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'])
          : null,
      nfcEnabled: map['nfcEnabled'] ?? true,
      nfcTagId: map['nfcTagId'],
    );
  }

  // Copy with modifications
  UserModel copyWith({
    String? uid,
    String? phoneNumber,
    String? name,
    String? profileImageUrl,
    String? emergencyContactUid,
    List<String>? trustedContactUids,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? nfcEnabled,
    String? nfcTagId,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      name: name ?? this.name,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      emergencyContactUid: emergencyContactUid ?? this.emergencyContactUid,
      trustedContactUids: trustedContactUids ?? this.trustedContactUids,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      nfcEnabled: nfcEnabled ?? this.nfcEnabled,
      nfcTagId: nfcTagId ?? this.nfcTagId,
    );
  }
}
