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
    required String paymentMethod,
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
        'paymentMethod': paymentMethod,
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
  Future<List<Map<String, dynamic>>> getFlattenedCollectionData({String? filterCollectorId}) async {
    final buildingsSnapshot = await _firestore.collection('buildings').get();
    
    // Fetch team funds
    final collectorsSnapshot = await _firestore.collection('collectors').get();
    final teamFundsData = <Map<String, dynamic>>[];
    for (var doc in collectorsSnapshot.docs) {
      final data = doc.data();
      final role = data['role'] ?? 'viewer';
      final isCore = data['isCoreTeamMember'] ?? false;
      if (role == 'team_member' || isCore) {
        if (data['fundStatus'] == 'paid') {
          if (filterCollectorId != null && data['fundCollectedBy'] != filterCollectorId) continue;
          teamFundsData.add({
            'Building Name': 'Team Funds',
            'Unit Name': data['name'] ?? 'Team Member',
            'Status': 'collected',
            'Amount Collected': (data['fundAmount'] as num?)?.toDouble() ?? 0.0,
            'Payment Method': data['fundPaymentMethod'] ?? 'Cash',
            'Collected By': data['fundCollectedBy'] ?? '',
            'Collected At': (data['fundCollectedAt'] as Timestamp?)?.toDate().toIso8601String() ?? '',
          });
        }
      }
    }
    
    final unitFutures = buildingsSnapshot.docs.map((buildingDoc) async {
      final buildingName = buildingDoc.data()['name'] ?? 'Unknown Building';
      final unitsSnapshot = await buildingDoc.reference.collection('units').get();
      
      final List<Map<String, dynamic>> buildingData = [];
      for (final unitDoc in unitsSnapshot.docs) {
        final unitData = unitDoc.data();
        if (filterCollectorId != null && unitData['collectedBy'] != filterCollectorId) continue;
        
        buildingData.add({
          'Building Name': buildingName,
          'Unit Name': unitData['unitLabel'] ?? '',
          'Status': unitData['status'] ?? 'pending',
          'Amount Collected': (unitData['amount'] as num?)?.toDouble() ?? 0.0,
          'Payment Method': unitData['paymentMethod'] ?? 'Cash',
          'Collected By': unitData['collectedBy'] ?? '',
          'Collected At': (unitData['collectedAt'] as Timestamp?)?.toDate().toIso8601String() ?? '',
        });
      }
      return buildingData;
    });

    final results = await Future.wait(unitFutures);
    final flattened = results.expand((x) => x).toList();
    flattened.addAll(teamFundsData);
    return flattened;
  }

  // Get detailed collections for the reports UI
  Future<List<Map<String, dynamic>>> getDetailedCollections({String? filterCollectorId}) async {
    // Fetch buildings
    final buildingsSnapshot = await _firestore.collection('buildings').get();
    
    // Fetch team funds
    final collectorsSnapshot = await _firestore.collection('collectors').get();
    final teamFundsData = <Map<String, dynamic>>[];
    for (var doc in collectorsSnapshot.docs) {
      final data = doc.data();
      final role = data['role'] ?? 'viewer';
      final isCore = data['isCoreTeamMember'] ?? false;
      if (role == 'team_member' || isCore) {
        if (data['fundStatus'] == 'paid') {
          if (filterCollectorId != null && data['fundCollectedBy'] != filterCollectorId) continue;
          
          final dummyBuilding = Building(
            id: 'team_funds',
            name: 'Team Funds',
            lat: 0,
            lng: 0,
            type: 'team_funds',
            totalUnits: 1,
            collectedCount: 1,
            totalCollected: (data['fundAmount'] as num?)?.toDouble() ?? 0.0,
            createdBy: 'system',
            createdAt: DateTime.now(),
          );
          
          final dummyUnit = Unit(
            id: doc.id,
            buildingId: 'team_funds',
            unitLabel: data['name'] ?? 'Team Member',
            status: 'collected',
            amount: (data['fundAmount'] as num?)?.toDouble() ?? 0.0,
            paymentMethod: data['fundPaymentMethod'] ?? 'Cash',
            collectedBy: data['fundCollectedBy'],
            collectedAt: (data['fundCollectedAt'] as Timestamp?)?.toDate(),
          );
          
          teamFundsData.add({
            'unit': dummyUnit,
            'building': dummyBuilding,
          });
        }
      }
    }
    
    // Fetch units for all buildings in parallel
    final unitFutures = buildingsSnapshot.docs.map((buildingDoc) async {
      final building = Building.fromMap(buildingDoc.data(), buildingDoc.id);
      final unitsSnapshot = await buildingDoc.reference.collection('units').get();
      
      final List<Map<String, dynamic>> buildingCollections = [];
      for (final unitDoc in unitsSnapshot.docs) {
        final unit = Unit.fromMap(unitDoc.data(), unitDoc.id);
        if (unit.status == 'collected') {
          if (filterCollectorId != null && unit.collectedBy != filterCollectorId) continue;
          
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
    collections.addAll(teamFundsData);
    
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

  // Get pending/uncollected units
  Future<List<Map<String, dynamic>>> getPendingCollections() async {
    final buildingsSnapshot = await _firestore.collection('buildings').get();
    
    final unitFutures = buildingsSnapshot.docs.map((buildingDoc) async {
      final building = Building.fromMap(buildingDoc.data(), buildingDoc.id);
      final unitsSnapshot = await buildingDoc.reference.collection('units').get();
      
      final List<Map<String, dynamic>> buildingCollections = [];
      for (final unitDoc in unitsSnapshot.docs) {
        final unit = Unit.fromMap(unitDoc.data(), unitDoc.id);
        if (unit.status != 'collected') {
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
    
    // Sort by building name, then unit label
    collections.sort((a, b) {
      final bA = a['building'] as Building;
      final bB = b['building'] as Building;
      int comp = bA.name.compareTo(bB.name);
      if (comp == 0) {
        final uA = a['unit'] as Unit;
        final uB = b['unit'] as Unit;
        return uA.unitLabel.compareTo(uB.unitLabel);
      }
      return comp;
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

  // Rename a unit
  Future<void> renameUnit({
    required String buildingId,
    required String unitId,
    required String newName,
  }) async {
    await _firestore
        .collection('buildings')
        .doc(buildingId)
        .collection('units')
        .doc(unitId)
        .update({
      'unitLabel': newName,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Reset a unit collection
  Future<void> resetUnitCollection({
    required String buildingId,
    required String unitId,
    required double previousAmount,
  }) async {
    final batch = _firestore.batch();
    final buildingRef = _firestore.collection('buildings').doc(buildingId);
    final unitRef = buildingRef.collection('units').doc(unitId);

    batch.update(buildingRef, {
      'collectedCount': FieldValue.increment(-1),
      'totalCollected': FieldValue.increment(-previousAmount),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    batch.update(unitRef, {
      'status': 'pending',
      'amount': 0.0,
      'collectedBy': null,
      'paymentMethod': null,
      'collectedAt': null,
      'photoBase64': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }
}
