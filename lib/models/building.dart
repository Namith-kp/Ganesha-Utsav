import 'package:cloud_firestore/cloud_firestore.dart';

class Building {
  final String id;
  final double lat;
  final double lng;
  final String name;
  final String type; // "house", "shop", "apartment"
  final int totalUnits;
  final int collectedCount;
  final double totalCollected;
  final String createdBy;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Building({
    required this.id,
    required this.lat,
    required this.lng,
    required this.name,
    required this.type,
    required this.totalUnits,
    required this.collectedCount,
    required this.totalCollected,
    required this.createdBy,
    required this.createdAt,
    this.updatedAt,
  });

  factory Building.fromMap(Map<String, dynamic> map, String id) {
    return Building(
      id: id,
      lat: (map['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (map['lng'] as num?)?.toDouble() ?? 0.0,
      name: map['name'] as String? ?? 'Unknown',
      type: map['type'] as String? ?? 'house',
      totalUnits: map['totalUnits'] as int? ?? 1,
      collectedCount: map['collectedCount'] as int? ?? 0,
      totalCollected: (map['totalCollected'] as num?)?.toDouble() ?? 0.0,
      createdBy: map['createdBy'] as String? ?? '',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'lat': lat,
      'lng': lng,
      'name': name,
      'type': type,
      'totalUnits': totalUnits,
      'collectedCount': collectedCount,
      'totalCollected': totalCollected,
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(createdAt),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }
}
