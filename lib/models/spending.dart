import 'package:cloud_firestore/cloud_firestore.dart';

class Spending {
  final String id;
  final double amount;
  final String reason;
  final String? photoBase64;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final String status;

  Spending({
    required this.id,
    required this.amount,
    required this.reason,
    this.photoBase64,
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
    this.status = 'approved',
  });

  factory Spending.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Spending(
      id: doc.id,
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      reason: data['reason'] ?? '',
      photoBase64: data['photoBase64'],
      createdBy: data['createdBy'] ?? 'unknown',
      createdByName: data['createdByName'] ?? 'Unknown',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: data['status'] ?? 'approved',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'amount': amount,
      'reason': reason,
      if (photoBase64 != null) 'photoBase64': photoBase64,
      'createdBy': createdBy,
      'createdByName': createdByName,
      'createdAt': Timestamp.fromDate(createdAt),
      'status': status,
    };
  }
}
