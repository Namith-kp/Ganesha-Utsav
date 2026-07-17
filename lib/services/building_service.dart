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

  // Stream a single building
  Stream<Building> streamBuilding(String buildingId) {
    return _firestore.collection('buildings').doc(buildingId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) {
        throw Exception('Building was deleted');
      }
      return Building.fromMap(doc.data() as Map<String, dynamic>, doc.id);
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
      updatedAt: DateTime.now(),
    );

    final unit = Unit(
      id: unitRef.id,
      buildingId: buildingRef.id,
      unitLabel: 'Main',
      status: 'pending',
      amount: 0.0,
      updatedAt: DateTime.now(),
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
    required List<String> unitLabels,
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
      totalUnits: unitLabels.length,
      collectedCount: 0,
      totalCollected: 0.0,
      createdBy: createdBy,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    batch.set(buildingRef, building.toMap());

    for (int i = 0; i < unitLabels.length; i++) {
      final unitRef = buildingRef.collection('units').doc();
      final unit = Unit(
        id: unitRef.id,
        buildingId: buildingRef.id,
        unitLabel: unitLabels[i],
        status: 'pending',
        amount: 0.0,
        updatedAt: DateTime.now(),
      );
      batch.set(unitRef, unit.toMap());
    }

    await batch.commit();
  }

  // Add a new unit to an existing building
  Future<void> addUnitToBuilding(String buildingId, String unitLabel) async {
    final batch = _firestore.batch();
    
    final buildingRef = _firestore.collection('buildings').doc(buildingId);
    final unitRef = buildingRef.collection('units').doc();
    
    final unit = Unit(
      id: unitRef.id,
      buildingId: buildingId,
      unitLabel: unitLabel,
      status: 'pending',
      amount: 0.0,
      updatedAt: DateTime.now(),
    );
    
    batch.set(unitRef, unit.toMap());
    
    // Increment total units
    batch.update(buildingRef, {
      'totalUnits': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    
    await batch.commit();
  }

  // Delete a building and its units
  Future<void> deleteBuilding(String buildingId) async {
    final batch = _firestore.batch();
    
    // Get all units to delete them
    final unitsSnapshot = await _firestore
        .collection('buildings')
        .doc(buildingId)
        .collection('units')
        .get();
        
    for (var doc in unitsSnapshot.docs) {
      batch.delete(doc.reference);
    }
    
    // Delete the building itself
    batch.delete(_firestore.collection('buildings').doc(buildingId));
    
    await batch.commit();
  }

  // Update building location
  Future<void> updateBuildingLocation(String buildingId, double lat, double lng) async {
    await _firestore.collection('buildings').doc(buildingId).update({
      'lat': lat,
      'lng': lng,
      'updatedAt': FieldValue.serverTimestamp(),
    });
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
      final double oldAmount = (unitData['amount'] as num?)?.toDouble() ?? 0.0;
      final String buildingName = buildingDoc.data()!['name'] ?? 'Unknown';

      if (wasCollected) {
        // It's a correction
        final double amountDiff = amount - oldAmount;
        
        batch.update(buildingRef, {
          'totalCollected': FieldValue.increment(amountDiff),
          'updatedAt': FieldValue.serverTimestamp(),
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
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      batch.update(unitRef, {
        'status': 'collected',
        'amount': amount,
        'collectedBy': collectedBy,
        'collectedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
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
    final buildingsSnapshot = await _firestore.collection('buildings').get();
    
    final unitFutures = buildingsSnapshot.docs.map((buildingDoc) async {
      final buildingName = buildingDoc.data()['name'] ?? 'Unknown Building';
      final unitsSnapshot = await buildingDoc.reference.collection('units').get();
      
      final List<Map<String, dynamic>> buildingData = [];
      for (final unitDoc in unitsSnapshot.docs) {
        final unitData = unitDoc.data();
        buildingData.add({
          'Building Name': buildingName,
          'Unit Name': unitData['unitLabel'] ?? '',
          'Status': unitData['status'] ?? 'pending',
          'Amount Collected': (unitData['amount'] as num?)?.toDouble() ?? 0.0,
          'Collected By': unitData['collectedBy'] ?? '',
          'Collected At': (unitData['collectedAt'] as Timestamp?)?.toDate().toIso8601String() ?? '',
        });
      }
      return buildingData;
    });

    final results = await Future.wait(unitFutures);
    return results.expand((x) => x).toList();
  }

  // Get detailed collections for the reports UI
  Future<List<Map<String, dynamic>>> getDetailedCollections() async {
    // Fetch buildings
    final buildingsSnapshot = await _firestore.collection('buildings').get();
    
    // Fetch units for all buildings in parallel
    final unitFutures = buildingsSnapshot.docs.map((buildingDoc) async {
      final building = Building.fromMap(buildingDoc.data(), buildingDoc.id);
      final unitsSnapshot = await buildingDoc.reference.collection('units').get();
      
      final List<Map<String, dynamic>> buildingCollections = [];
      for (final unitDoc in unitsSnapshot.docs) {
        final unit = Unit.fromMap(unitDoc.data(), unitDoc.id);
        if (unit.status == 'collected') {
          buildingCollections.add({
            'unit': unit,
            'building': building,
          });
        }
      }
      return buildingCollections;
    });

    final results = await Future.wait(unitFutures);
    final collections = results.expand((x) => x).toList();
    
    // Sort descending by date
    collections.sort((a, b) {
      final dateA = (a['unit'] as Unit).collectedAt;
      final dateB = (b['unit'] as Unit).collectedAt;
      if (dateA == null && dateB == null) return 0;
      if (dateA == null) return 1;
      if (dateB == null) return -1;
      return dateB.compareTo(dateA);
    });
    
    return collections;
  }

  // Update building name (admin only, verified at UI level)
  Future<void> updateBuildingName(String buildingId, String newName) async {
    await _firestore.collection('buildings').doc(buildingId).update({
      'name': newName,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
