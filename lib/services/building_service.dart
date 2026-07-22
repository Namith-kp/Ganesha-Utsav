import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/building.dart';
import '../models/unit.dart';

class BuildingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _normalizePhoneNumber(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }

  Future<bool> isPhoneNumberInUse(
    String phoneNumber, {
    String? excludeBuildingId,
    String? excludeUnitId,
  }) async {
    final normalized = _normalizePhoneNumber(phoneNumber.trim());
    if (normalized.isEmpty) return false;

    try {
      final snapshot = await _firestore
          .collectionGroup('units')
          .where('phoneNumberNormalized', isEqualTo: normalized)
          .get();

      for (final doc in snapshot.docs) {
        final parentBuildingId = doc.reference.parent.parent?.id;
        if (parentBuildingId == excludeBuildingId && doc.id == excludeUnitId) {
          continue;
        }
        return true;
      }
    } on FirebaseException catch (e) {
      if (e.code == 'failed-precondition') {
        return false;
      }
      rethrow;
    }

    return false;
  }

  // Stream all buildings for the map
  Stream<List<Building>> streamBuildings() {
    return _firestore.collection('buildings').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => Building.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  // Stream a single building
  Stream<Building> streamBuilding(String buildingId) {
    return _firestore.collection('buildings').doc(buildingId).snapshots().map((
      doc,
    ) {
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
  Future<void> updateBuildingLocation(
    String buildingId,
    double lat,
    double lng,
  ) async {
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
          return snapshot.docs
              .map((doc) => Unit.fromMap(doc.data(), doc.id))
              .toList();
        });
  }

  // Mark a unit as collected (or correct an already collected unit)
  Future<void> markUnitCollected({
    required String buildingId,
    required String unitId,
    required double amount,
    required String collectedBy,
    String?
    collectedByName, // used when editing to record who made the correction
    String? photoBase64,
    required String paymentMethod,
    String? donationItem,
    String? phoneNumber,
  }) async {
    final batch = _firestore.batch();
    final buildingRef = _firestore.collection('buildings').doc(buildingId);
    final unitRef = buildingRef.collection('units').doc(unitId);
    final normalizedPhone = phoneNumber == null
        ? null
        : _normalizePhoneNumber(phoneNumber);

    // Get current unit and building to see if it's an edit
    final unitDoc = await unitRef.get();
    final buildingDoc = await buildingRef.get();

    if (unitDoc.exists && buildingDoc.exists) {
      final unitData = unitDoc.data()!;
      final bool wasCollected = unitData['status'] == 'collected';
      final double oldAmount = (unitData['amount'] as num?)?.toDouble() ?? 0.0;
      final String buildingName = buildingDoc.data()!['name'] ?? 'Unknown';

      if (wasCollected) {
        // It's a correction — adjust running total by the delta only
        final double amountDiff = amount - oldAmount;

        if (amountDiff == 0) {
          // If no amount changed, just update other fields silently without logging a correction
          final Map<String, dynamic> phoneFields = {};
          if (phoneNumber != null) {
            phoneFields['phoneNumber'] = phoneNumber.isNotEmpty
                ? phoneNumber
                : FieldValue.delete();
            phoneFields['phoneNumberNormalized'] = normalizedPhone!.isNotEmpty
                ? normalizedPhone
                : FieldValue.delete();
          }
          final Map<String, dynamic> unitUpdate = {
            'paymentMethod': paymentMethod,
            'updatedAt': FieldValue.serverTimestamp(),
            if (photoBase64 != null) 'photoBase64': photoBase64,
            if (donationItem != null && donationItem.isNotEmpty)
              'donationItem': donationItem,
            ...phoneFields,
          };
          batch.update(unitRef, unitUpdate);
          await batch.commit();
          return;
        }

        batch.update(buildingRef, {
          'totalCollected': FieldValue.increment(amountDiff),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Determine the originalAmount: if this unit was never edited before,
        // the current oldAmount IS the original. Otherwise keep the already-stored value.
        final double? existingOriginal = (unitData['originalAmount'] as num?)
            ?.toDouble();
        final double originalAmount = existingOriginal ?? oldAmount;

        // Write correction log with editor name for the info page
        final correctionRef = _firestore.collection('corrections').doc();
        batch.set(correctionRef, {
          'unitId': unitId,
          'buildingId': buildingId,
          'buildingName': buildingName,
          'unitLabel': unitData['unitLabel'],
          'oldAmount': oldAmount,
          'newAmount': amount,
          'delta': amountDiff,
          'correctedBy': collectedBy,
          'correctedByName': collectedByName ?? 'Admin',
          'timestamp': FieldValue.serverTimestamp(),
        });

        // Update the unit: new amount, originalAmount (once), but DO NOT touch collectedAt
        final Map<String, dynamic> phoneFields = {};
        if (phoneNumber != null) {
          phoneFields['phoneNumber'] = phoneNumber.isNotEmpty
              ? phoneNumber
              : FieldValue.delete();
          phoneFields['phoneNumberNormalized'] = normalizedPhone!.isNotEmpty
              ? normalizedPhone
              : FieldValue.delete();
        }
        final Map<String, dynamic> unitUpdate = {
          'amount': amount,
          'paymentMethod': paymentMethod,
          'updatedAt': FieldValue.serverTimestamp(),
          if (photoBase64 != null) 'photoBase64': photoBase64,
          if (donationItem != null && donationItem.isNotEmpty)
            'donationItem': donationItem,
          ...phoneFields,
        };
        // Only set originalAmount if this is the first edit
        if (existingOriginal == null) {
          unitUpdate['originalAmount'] = originalAmount;
        }
        batch.update(unitRef, unitUpdate);
      } else {
        // First time collection
        batch.update(buildingRef, {
          'collectedCount': FieldValue.increment(1),
          'totalCollected': FieldValue.increment(amount),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        final Map<String, dynamic> phoneFields = {};
        if (phoneNumber != null) {
          phoneFields['phoneNumber'] = phoneNumber.isNotEmpty
              ? phoneNumber
              : FieldValue.delete();
          phoneFields['phoneNumberNormalized'] = normalizedPhone!.isNotEmpty
              ? normalizedPhone
              : FieldValue.delete();
        }
        batch.update(unitRef, {
          'status': 'collected',
          'amount': amount,
          'collectedBy': collectedBy,
          'paymentMethod': paymentMethod,
          'collectedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          if (photoBase64 != null) 'photoBase64': photoBase64,
          if (donationItem != null && donationItem.isNotEmpty)
            'donationItem': donationItem,
          ...phoneFields,
        });
      }

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
  Future<List<Map<String, dynamic>>> getFlattenedCollectionData({
    String? filterCollectorId,
  }) async {
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
          if (filterCollectorId != null &&
              data['fundCollectedBy'] != filterCollectorId)
            continue;
          teamFundsData.add({
            'Building Name': 'Team Funds',
            'Unit Name': data['name'] ?? 'Team Member',
            'Status': 'collected',
            'Amount Collected': (data['fundAmount'] as num?)?.toDouble() ?? 0.0,
            'Payment Method': data['fundPaymentMethod'] ?? 'Cash',
            'Collected By': data['fundCollectedBy'] ?? '',
            'Collected At':
                (data['fundCollectedAt'] as Timestamp?)
                    ?.toDate()
                    .toIso8601String() ??
                '',
          });
        }
      }
    }

    final unitFutures = buildingsSnapshot.docs.map((buildingDoc) async {
      final buildingName = buildingDoc.data()['name'] ?? 'Unknown Building';
      final unitsSnapshot = await buildingDoc.reference
          .collection('units')
          .get();

      final List<Map<String, dynamic>> buildingData = [];
      for (final unitDoc in unitsSnapshot.docs) {
        final unitData = unitDoc.data();
        if (filterCollectorId != null &&
            unitData['collectedBy'] != filterCollectorId)
          continue;

        buildingData.add({
          'Building Name': buildingName,
          'Unit Name': unitData['unitLabel'] ?? '',
          'Status': unitData['status'] ?? 'pending',
          'Amount Collected': (unitData['amount'] as num?)?.toDouble() ?? 0.0,
          'Payment Method': unitData['paymentMethod'] ?? 'Cash',
          'Collected By': unitData['collectedBy'] ?? '',
          'Collected At':
              (unitData['collectedAt'] as Timestamp?)
                  ?.toDate()
                  .toIso8601String() ??
              '',
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
  Future<List<Map<String, dynamic>>> getDetailedCollections({
    String? filterCollectorId,
  }) async {
    // Fetch buildings, corrections, and collectors in parallel
    final results = await Future.wait([
      _firestore.collection('buildings').get(),
      _firestore
          .collection('corrections')
          .orderBy('timestamp', descending: true)
          .get(),
      _firestore.collection('collectors').get(),
    ]);

    final buildingsSnapshot = results[0] as QuerySnapshot;
    final correctionsSnapshot = results[1] as QuerySnapshot;
    final collectorsSnapshot = results[2] as QuerySnapshot;

    // Build a name lookup map for collectors
    final collectorNames = <String, String>{};
    for (var doc in collectorsSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      collectorNames[doc.id] = data['name'] as String? ?? 'Unknown';
    }

    // ── Team funds ──────────────────────────────────────────────────────────
    final teamFundsData = <Map<String, dynamic>>[];
    for (var doc in collectorsSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final role = data['role'] ?? 'viewer';
      final isCore = data['isCoreTeamMember'] ?? false;
      if (role == 'team_member' || isCore) {
        if (data['fundStatus'] == 'paid') {
          if (filterCollectorId != null &&
              data['fundCollectedBy'] != filterCollectorId)
            continue;

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

          teamFundsData.add({'unit': dummyUnit, 'building': dummyBuilding});
        }
      }
    }

    // ── Units ────────────────────────────────────────────────────────────────
    final unitFutures = buildingsSnapshot.docs.map((buildingDoc) async {
      final building = Building.fromMap(
        buildingDoc.data() as Map<String, dynamic>,
        buildingDoc.id,
      );
      final unitsSnapshot = await buildingDoc.reference
          .collection('units')
          .get();

      final List<Map<String, dynamic>> buildingCollections = [];
      for (final unitDoc in unitsSnapshot.docs) {
        final unit = Unit.fromMap(
          unitDoc.data() as Map<String, dynamic>,
          unitDoc.id,
        );
        if (unit.status == 'collected') {
          if (filterCollectorId != null &&
              unit.collectedBy != filterCollectorId)
            continue;

          // If the unit has been edited, show it at its original date with originalAmount
          buildingCollections.add({'unit': unit, 'building': building});
        }
      }
      return buildingCollections;
    });

    final unitResults = await Future.wait(unitFutures);
    final collections = unitResults.expand((x) => x).toList();
    collections.addAll(teamFundsData);

    // ── Correction delta entries ─────────────────────────────────────────────
    // Build lookups: unitId -> building & unit (from already-fetched real units)
    final buildingByUnitId = <String, Building>{};
    final unitById = <String, Unit>{};
    for (var entry in collections) {
      final unit = entry['unit'] as Unit;
      final building = entry['building'] as Building;
      if (building.id != 'team_funds') {
        buildingByUnitId[unit.id] = building;
        unitById[unit.id] = unit;
      }
    }

    for (var corrDoc in correctionsSnapshot.docs) {
      final data = corrDoc.data() as Map<String, dynamic>;
      final String unitId = data['unitId'] as String? ?? '';
      final String buildingId = data['buildingId'] as String? ?? '';
      final double delta = (data['delta'] as num?)?.toDouble() ?? 0.0;
      final double oldAmount = (data['oldAmount'] as num?)?.toDouble() ?? 0.0;
      final double newAmount = (data['newAmount'] as num?)?.toDouble() ?? 0.0;
      final String correctedBy = data['correctedBy'] as String? ?? '';
      final String correctedByName =
          data['correctedByName'] as String? ??
          collectorNames[correctedBy] ??
          'Admin';
      final DateTime? correctionTime = (data['timestamp'] as Timestamp?)
          ?.toDate();
      final String buildingName = data['buildingName'] as String? ?? 'Unknown';
      final String unitLabel = data['unitLabel'] as String? ?? '';

      // Skip if filtering by collector (corrections are admin-only, always shown to admins)
      if (filterCollectorId != null) continue;

      // Look up the original real unit so the card can show its photo and open
      // the correct info dialog on tap.
      final realUnit = unitById[unitId];
      final realBuilding = buildingByUnitId[unitId];

      // Build a placeholder building (fallback when real unit not in scope)
      final correctionBuilding =
          realBuilding ??
          Building(
            id: buildingId,
            name: buildingName,
            lat: 0,
            lng: 0,
            type: 'house',
            totalUnits: 1,
            collectedCount: 1,
            totalCollected: newAmount,
            createdBy: 'system',
            createdAt: DateTime.now(),
          );

      // A virtual Unit that represents the DELTA — carries original photo for thumbnail
      final deltaUnit = Unit(
        id: '${unitId}_correction_${corrDoc.id}',
        buildingId: buildingId,
        unitLabel: unitLabel,
        status: 'collected',
        amount: delta, // positive or negative delta
        collectedAt: correctionTime,
        updatedAt: correctionTime,
        originalAmount: oldAmount,
        photoBase64: realUnit?.photoBase64, // reuse original unit's thumbnail
      );

      collections.add({
        'unit': deltaUnit,
        'building': correctionBuilding,
        'isCorrection': true,
        'realUnit': realUnit, // original unit for tap dialog
        'realBuilding': realBuilding ?? correctionBuilding,
        'correctedByName': correctedByName,
        'oldAmount': oldAmount,
        'newAmount': newAmount,
        'delta': delta,
      });
    }

    // Sort descending by date (collectedAt for normal, correctionTime for deltas)
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
      final unitsSnapshot = await buildingDoc.reference
          .collection('units')
          .get();

      final List<Map<String, dynamic>> buildingCollections = [];
      for (final unitDoc in unitsSnapshot.docs) {
        final unit = Unit.fromMap(unitDoc.data(), unitDoc.id);
        if (unit.status != 'collected') {
          buildingCollections.add({'unit': unit, 'building': building});
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
      'phoneNumber': null,
      'phoneNumberNormalized': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }
}
