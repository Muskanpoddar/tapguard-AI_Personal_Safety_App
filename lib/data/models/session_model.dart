// lib/data/models/session_model.dart
// Firestore document structure for a TapGuard NFC session

class SessionModel {
  final String sessionId;       // unique ID — also used in the share URL
  final String ownerUid;        // Firebase Auth UID of person who started session
  final String ownerPhone;      // display phone number
  final String ownerName;       // display name
  final double latitude;        // latest lat
  final double longitude;       // latest lng
  final double accuracy;        // GPS accuracy in metres
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;          // false when session ended
  final String shareUrl;        // https://tapguard.page.link/s/[sessionId]

  const SessionModel({
    required this.sessionId,
    required this.ownerUid,
    required this.ownerPhone,
    required this.ownerName,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.createdAt,
    required this.updatedAt,
    required this.isActive,
    required this.shareUrl,
  });

  // ── Firestore → model ─────────────────────────────────────────────────────
  factory SessionModel.fromMap(Map<String, dynamic> map, String docId) {
    return SessionModel(
      sessionId:  docId,
      ownerUid:   map['ownerUid']   ?? '',
      ownerPhone: map['ownerPhone'] ?? '',
      ownerName:  map['ownerName']  ?? '',
      latitude:   (map['latitude']  ?? 0.0).toDouble(),
      longitude:  (map['longitude'] ?? 0.0).toDouble(),
      accuracy:   (map['accuracy']  ?? 0.0).toDouble(),
      createdAt:  (map['createdAt'] as dynamic)?.toDate() ?? DateTime.now(),
      updatedAt:  (map['updatedAt'] as dynamic)?.toDate() ?? DateTime.now(),
      isActive:   map['isActive']   ?? false,
      shareUrl:   map['shareUrl']   ?? '',
    );
  }

  // ── Model → Firestore ─────────────────────────────────────────────────────
  Map<String, dynamic> toMap() {
    return {
      'ownerUid':   ownerUid,
      'ownerPhone': ownerPhone,
      'ownerName':  ownerName,
      'latitude':   latitude,
      'longitude':  longitude,
      'accuracy':   accuracy,
      'createdAt':  createdAt,
      'updatedAt':  updatedAt,
      'isActive':   isActive,
      'shareUrl':   shareUrl,
    };
  }

  SessionModel copyWith({
    double? latitude,
    double? longitude,
    double? accuracy,
    DateTime? updatedAt,
    bool? isActive,
  }) {
    return SessionModel(
      sessionId:  sessionId,
      ownerUid:   ownerUid,
      ownerPhone: ownerPhone,
      ownerName:  ownerName,
      latitude:   latitude  ?? this.latitude,
      longitude:  longitude ?? this.longitude,
      accuracy:   accuracy  ?? this.accuracy,
      createdAt:  createdAt,
      updatedAt:  updatedAt ?? this.updatedAt,
      isActive:   isActive  ?? this.isActive,
      shareUrl:   shareUrl,
    );
  }
}                                   