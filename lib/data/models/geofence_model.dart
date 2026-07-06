// lib/data/models/geofence_model.dart
//
// A user-defined "safe zone" — a circular area on the map.
// When the user enters or exits, the GeofenceService (Phase 5+) can
// notify their trusted contacts.

import 'package:cloud_firestore/cloud_firestore.dart';

class GeofenceModel {
  final String id;
  final String ownerUid;
  final String name;

  // Center point
  final double centerLat;
  final double centerLng;

  // Radius in meters
  final double radiusMeters;

  // Notification preferences
  final bool notifyOnEnter;
  final bool notifyOnExit;

  // Whether the geofence is currently active
  final bool isActive;

  final DateTime createdAt;
  final DateTime? updatedAt;

  const GeofenceModel({
    required this.id,
    required this.ownerUid,
    required this.name,
    required this.centerLat,
    required this.centerLng,
    required this.radiusMeters,
    this.notifyOnEnter = true,
    this.notifyOnExit = false,
    this.isActive = true,
    required this.createdAt,
    this.updatedAt,
  });

  /// Firestore JSON
  Map<String, dynamic> toMap() => {
        'id': id,
        'ownerUid': ownerUid,
        'name': name,
        'centerLat': centerLat,
        'centerLng': centerLng,
        'radiusMeters': radiusMeters,
        'notifyOnEnter': notifyOnEnter,
        'notifyOnExit': notifyOnExit,
        'isActive': isActive,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt':
            updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      };

  factory GeofenceModel.fromMap(Map<String, dynamic> map, String docId) {
    return GeofenceModel(
      id: docId,
      ownerUid: (map['ownerUid'] as String?) ?? '',
      name: (map['name'] as String?) ?? 'Safe Zone',
      centerLat: (map['centerLat'] as num?)?.toDouble() ?? 0.0,
      centerLng: (map['centerLng'] as num?)?.toDouble() ?? 0.0,
      radiusMeters: (map['radiusMeters'] as num?)?.toDouble() ?? 100.0,
      notifyOnEnter: (map['notifyOnEnter'] as bool?) ?? true,
      notifyOnExit: (map['notifyOnExit'] as bool?) ?? false,
      isActive: (map['isActive'] as bool?) ?? true,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  GeofenceModel copyWith({
    String? name,
    double? centerLat,
    double? centerLng,
    double? radiusMeters,
    bool? notifyOnEnter,
    bool? notifyOnExit,
    bool? isActive,
    DateTime? updatedAt,
  }) {
    return GeofenceModel(
      id: id,
      ownerUid: ownerUid,
      name: name ?? this.name,
      centerLat: centerLat ?? this.centerLat,
      centerLng: centerLng ?? this.centerLng,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      notifyOnEnter: notifyOnEnter ?? this.notifyOnEnter,
      notifyOnExit: notifyOnExit ?? this.notifyOnExit,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}
