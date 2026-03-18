// lib/data/models/session_model.dart
class SessionModel {
  final String sessionId;

  // Sender (Phone A - has app)
  final String ownerUid;
  final String ownerPhone;
  final String ownerName;
  final double ownerLat;
  final double ownerLng;
  final double ownerAccuracy;

  // Receiver (Phone B - browser only)
  final String?   receiverName;
  final double?   receiverLat;
  final double?   receiverLng;
  final double?   receiverAccuracy;
  final bool      receiverJoined;
  final DateTime? receiverJoinedAt;

  // Metadata
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool     isActive;
  final String   shareUrl;

  const SessionModel({
    required this.sessionId,
    required this.ownerUid,
    required this.ownerPhone,
    required this.ownerName,
    required this.ownerLat,
    required this.ownerLng,
    required this.ownerAccuracy,
    this.receiverName,
    this.receiverLat,
    this.receiverLng,
    this.receiverAccuracy,
    this.receiverJoined    = false,
    this.receiverJoinedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.isActive,
    required this.shareUrl,
  });

  bool get hasBothLocations =>
      receiverLat != null && receiverLng != null;

  factory SessionModel.fromMap(Map<String, dynamic> d, String id) {
    return SessionModel(
      sessionId:        id,
      ownerUid:         d['ownerUid']      ?? '',
      ownerPhone:       d['ownerPhone']     ?? '',
      ownerName:        d['ownerName']      ?? '',
      ownerLat:         (d['ownerLat']      ?? 0.0).toDouble(),
      ownerLng:         (d['ownerLng']      ?? 0.0).toDouble(),
      ownerAccuracy:    (d['ownerAccuracy'] ?? 0.0).toDouble(),
      receiverName:     d['receiverName'],
      receiverLat:      d['receiverLat']      != null
          ? (d['receiverLat']      as num).toDouble() : null,
      receiverLng:      d['receiverLng']      != null
          ? (d['receiverLng']      as num).toDouble() : null,
      receiverAccuracy: d['receiverAccuracy'] != null
          ? (d['receiverAccuracy'] as num).toDouble() : null,
      receiverJoined:   d['receiverJoined']   ?? false,
      receiverJoinedAt: (d['receiverJoinedAt'] as dynamic)?.toDate(),
      createdAt:        (d['createdAt'] as dynamic)?.toDate() ?? DateTime.now(),
      updatedAt:        (d['updatedAt'] as dynamic)?.toDate() ?? DateTime.now(),
      isActive:         d['isActive'] ?? false,
      shareUrl:         d['shareUrl'] ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'ownerUid':       ownerUid,
    'ownerPhone':     ownerPhone,
    'ownerName':      ownerName,
    'ownerLat':       ownerLat,
    'ownerLng':       ownerLng,
    'ownerAccuracy':  ownerAccuracy,
    'receiverJoined': receiverJoined,
    'isActive':       isActive,
    'shareUrl':       shareUrl,
  };

  SessionModel copyWith({
    double?   ownerLat,      double?   ownerLng,   double?   ownerAccuracy,
    String?   receiverName,
    double?   receiverLat,   double?   receiverLng, double?  receiverAccuracy,
    bool?     receiverJoined, DateTime? receiverJoinedAt,
    DateTime? updatedAt,     bool?     isActive,
  }) => SessionModel(
    sessionId:        sessionId,
    ownerUid:         ownerUid,
    ownerPhone:       ownerPhone,
    ownerName:        ownerName,
    ownerLat:         ownerLat         ?? this.ownerLat,
    ownerLng:         ownerLng         ?? this.ownerLng,
    ownerAccuracy:    ownerAccuracy    ?? this.ownerAccuracy,
    receiverName:     receiverName     ?? this.receiverName,
    receiverLat:      receiverLat      ?? this.receiverLat,
    receiverLng:      receiverLng      ?? this.receiverLng,
    receiverAccuracy: receiverAccuracy ?? this.receiverAccuracy,
    receiverJoined:   receiverJoined   ?? this.receiverJoined,
    receiverJoinedAt: receiverJoinedAt ?? this.receiverJoinedAt,
    createdAt:        createdAt,
    updatedAt:        updatedAt        ?? this.updatedAt,
    isActive:         isActive         ?? this.isActive,
    shareUrl:         shareUrl,
  );
}