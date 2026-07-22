import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/spending.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final spendingServiceProvider = Provider((ref) => SpendingService());

class SpendingService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<List<Spending>> getSpendings() async {
    try {
      final snapshot = await _db
          .collection('spendings')
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs.map((doc) => Spending.fromFirestore(doc)).toList();
    } catch (e) {
      print('Error fetching spendings: $e');
      return [];
    }
  }

  Future<void> addSpending({
    required double amount,
    required String reason,
    required String createdBy,
    required String createdByName,
    String? photoBase64,
  }) async {
    await _db.collection('spendings').add({
      'amount': amount,
      'reason': reason,
      'photoBase64': photoBase64,
      'createdBy': createdBy,
      'createdByName': createdByName,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'approved',
    });
  }

  Future<void> updateSpending({
    required String spendingId,
    required double amount,
    required String reason,
    String? photoBase64,
  }) async {
    final Map<String, dynamic> updates = {'amount': amount, 'reason': reason};
    if (photoBase64 != null) {
      updates['photoBase64'] = photoBase64;
    }

    await _db.collection('spendings').doc(spendingId).update(updates);
  }

  Future<void> deleteSpending(String spendingId) async {
    await _db.collection('spendings').doc(spendingId).delete();
  }
}
