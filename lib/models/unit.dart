import 'package:cloud_firestore/cloud_firestore.dart';

class Unit {
  final String id;
  final String buildingId;
  final String unitLabel;
  final String status; // "pending" or "collected"
  final double amount;
  final String? collectedBy;
  final DateTime? collectedAt;
  final String? photoBase64;

  Unit({
    required this.id,
    required this.buildingId,
    required this.unitLabel,
    required this.status,
    required this.amount,
    this.collectedBy,
    this.collectedAt,
    this.photoBase64,
  });

  factory Unit.fromMap(Map<String, dynamic> map, String id) {
    return Unit(
      id: id,
      buildingId: map['buildingId'] as String? ?? '',
      unitLabel: map['unitLabel'] as String? ?? '',
      status: map['status'] as String? ?? 'pending',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      collectedBy: map['collectedBy'] as String?,
      collectedAt: (map['collectedAt'] as Timestamp?)?.toDate(),
      photoBase64: map['photoBase64'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'buildingId': buildingId,
      'unitLabel': unitLabel,
      'status': status,
      'amount': amount,
      if (collectedBy != null) 'collectedBy': collectedBy,
      if (collectedAt != null) 'collectedAt': Timestamp.fromDate(collectedAt!),
      if (photoBase64 != null) 'photoBase64': photoBase64,
    };
  }
}
