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
  final String? paymentMethod;
  final DateTime? updatedAt;
  final double? originalAmount; // set on first admin edit, never changed again
  final String? donationItem; // for non-monetary donations like Rice, Sarees
  final String? phoneNumber;
  final String? phoneNumberNormalized;

  Unit({
    required this.id,
    required this.buildingId,
    required this.unitLabel,
    required this.status,
    required this.amount,
    this.collectedBy,
    this.collectedAt,
    this.photoBase64,
    this.paymentMethod,
    this.updatedAt,
    this.originalAmount,
    this.donationItem,
    this.phoneNumber,
    this.phoneNumberNormalized,
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
      paymentMethod: map['paymentMethod'] as String?,
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
      originalAmount: (map['originalAmount'] as num?)?.toDouble(),
      donationItem: map['donationItem'] as String?,
      phoneNumber: map['phoneNumber'] as String?,
      phoneNumberNormalized: map['phoneNumberNormalized'] as String?,
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
      if (paymentMethod != null) 'paymentMethod': paymentMethod,
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
      if (originalAmount != null) 'originalAmount': originalAmount,
      if (donationItem != null && donationItem!.isNotEmpty)
        'donationItem': donationItem,
      if (phoneNumber != null && phoneNumber!.isNotEmpty)
        'phoneNumber': phoneNumber,
      if (phoneNumberNormalized != null && phoneNumberNormalized!.isNotEmpty)
        'phoneNumberNormalized': phoneNumberNormalized,
    };
  }
}
