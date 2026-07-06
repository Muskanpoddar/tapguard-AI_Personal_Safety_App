
class UserModel {
  final String uid;
  final String email;
  final String phoneNumber;
  final String name;
  final int avatarColor;
  final String? profileImageUrl;
  final String? emergencyContactUid;
  final List<String> trustedContactUids;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool nfcEnabled;
  final String? nfcTagId;

  UserModel({
    required this.uid,
    required this.email,
    required this.phoneNumber,
    required this.name,
    this.avatarColor = 0,
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
      'email': email,
      'phoneNumber': phoneNumber,
      'name': name,
      'avatarColor': avatarColor,
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
      email: (map['email'] as String?) ?? '',
      phoneNumber: (map['phoneNumber'] as String?) ?? '',
      name: (map['name'] as String?) ?? '',
      avatarColor: (map['avatarColor'] as num?)?.toInt() ?? 0,
      profileImageUrl: map['profileImageUrl'] as String?,
      emergencyContactUid: map['emergencyContactUid'] as String?,
      trustedContactUids:
          List<String>.from(map['trustedContactUids'] ?? const []),
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'] as String)
          : null,
      nfcEnabled: (map['nfcEnabled'] as bool?) ?? true,
      nfcTagId: map['nfcTagId'] as String?,
    );
  }

  // Copy with modifications
  UserModel copyWith({
    String? uid,
    String? email,
    String? phoneNumber,
    String? name,
    int? avatarColor,
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
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      name: name ?? this.name,
      avatarColor: avatarColor ?? this.avatarColor,
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
