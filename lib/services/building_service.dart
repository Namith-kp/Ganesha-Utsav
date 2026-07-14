import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/building.dart';
import '../models/unit.dart';

class BuildingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Stream all buildings for the map
  Stream<List<Building>> streamBuildings() {
    return _firestore.collection('buildings').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => Building.fromMap(doc.data(), doc.id)).toList();
    });
  }

  // Create a single-unit building (house/shop)
  Future<void> createSingleUnitBuilding({
    required double lat,
    required double lng,
    required String name,
    required String type, // "house" or "shop"
    required String createdBy,
  }) async {
    final batch = _firestore.batch();
    
    final buildingRef = _firestore.collection('buildings').doc();
    final unitRef = buildingRef.collection('units').doc();

    final building = Building(
      id: buildingRef.id,
      lat: lat,
      lng: lng,
      name: name,
      type: type,
      totalUnits: 1,
      collectedCount: 0,
      totalCollected: 0.0,
      createdBy: createdBy,
      createdAt: DateTime.now(),
    );

    final unit = Unit(
      id: unitRef.id,
      buildingId: buildingRef.id,
      unitLabel: 'Main',
      status: 'pending',
      amount: 0.0,
    );

    batch.set(buildingRef, building.toMap());
    batch.set(unitRef, unit.toMap());

    await batch.commit();
  }

  // Create a multi-unit building (apartment)
  Future<void> createMultiUnitBuilding({
    required double lat,
    required double lng,
    required String name,
    required int totalUnits,
    required String createdBy,
  }) async {
    final batch = _firestore.batch();
    
    final buildingRef = _firestore.collection('buildings').doc();

    final building = Building(
      id: buildingRef.id,
      lat: lat,
      lng: lng,
      name: name,
      type: 'apartment',
      totalUnits: totalUnits,
      collectedCount: 0,
      totalCollected: 0.0,
      createdBy: createdBy,
      createdAt: DateTime.now(),
    );

    batch.set(buildingRef, building.toMap());

    for (int i = 1; i <= totalUnits; i++) {
      final unitRef = buildingRef.collection('units').doc();
      final unit = Unit(
        id: unitRef.id,
        buildingId: buildingRef.id,
        unitLabel: 'Unit $i',
        status: 'pending',
        amount: 0.0,
      );
      batch.set(unitRef, unit.toMap());
    }

    await batch.commit();
  }

  // Get units for a specific building
  Stream<List<Unit>> streamUnits(String buildingId) {
    return _firestore
        .collection('buildings')
        .doc(buildingId)
        .collection('units')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => Unit.fromMap(doc.data(), doc.id)).toList();
    });
  }

  // Mark a unit as collected (or correct an already collected unit)
  Future<void> markUnitCollected({
    required String buildingId,
    required String unitId,
    required double amount,
    required String collectedBy,
    String? photoBase64,
  }) async {
    final batch = _firestore.batch();
    final buildingRef = _firestore.collection('buildings').doc(buildingId);
    final unitRef = buildingRef.collection('units').doc(unitId);

    // Get current unit and building to see if it's an edit
    final unitDoc = await unitRef.get();
    final buildingDoc = await buildingRef.get();
    
    if (unitDoc.exists && buildingDoc.exists) {
      final unitData = unitDoc.data()!;
      final bool wasCollected = unitData['status'] == 'collected';
      final double oldAmount = unitData['amount'] ?? 0.0;
      final String buildingName = buildingDoc.data()!['name'] ?? 'Unknown';

      if (wasCollected) {
        // It's a correction
        final double amountDiff = amount - oldAmount;
        
        batch.update(buildingRef, {
          'totalCollected': FieldValue.increment(amountDiff),
        });

        // Write correction log
        final correctionRef = _firestore.collection('corrections').doc();
        batch.set(correctionRef, {
          'unitId': unitId,
          'buildingName': buildingName,
          'unitLabel': unitData['unitLabel'],
          'oldAmount': oldAmount,
          'newAmount': amount,
          'correctedBy': collectedBy,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } else {
        // First time collection
        batch.update(buildingRef, {
          'collectedCount': FieldValue.increment(1),
          'totalCollected': FieldValue.increment(amount),
        });
      }

      batch.update(unitRef, {
        'status': 'collected',
        'amount': amount,
        'collectedBy': collectedBy,
        'collectedAt': FieldValue.serverTimestamp(),
        if (photoBase64 != null) 'photoBase64': photoBase64,
      });

      await batch.commit();
    }
  }

  // Stream corrections log
  Stream<List<Map<String, dynamic>>> streamCorrectionsLog() {
    return _firestore
        .collection('corrections')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => doc.data()).toList();
    });
  }

  // Get all flattened collection data for CSV export
  Future<List<Map<String, dynamic>>> getFlattenedCollectionData() async {
    final List<Map<String, dynamic>> flatData = [];
    
    final buildingsSnapshot = await _firestore.collection('buildings').get();
    
    for (final buildingDoc in buildingsSnapshot.docs) {
      final buildingName = buildingDoc.data()['name'] ?? 'Unknown Building';
      
      final unitsSnapshot = await buildingDoc.reference.collection('units').get();
      
      for (final unitDoc in unitsSnapshot.docs) {
        final unitData = unitDoc.data();
        
        flatData.add({
          'Building Name': buildingName,
          'Unit Name': unitData['unitLabel'] ?? '',
          'Status': unitData['status'] ?? 'pending',
          'Amount Collected': unitData['amount'] ?? 0.0,
          'Collected By': unitData['collectedBy'] ?? '',
          'Collected At': (unitData['collectedAt'] as Timestamp?)?.toDate().toIso8601String() ?? '',
        });
      }
    }
    
    return flatData;
  }
}
