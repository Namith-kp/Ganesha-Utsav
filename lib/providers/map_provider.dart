import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../services/building_service.dart';
import '../models/building.dart';
import '../models/unit.dart';

enum FilterStatus { all, pending, partial, completed }

class FilterStatusNotifier extends Notifier<FilterStatus> {
  @override
  FilterStatus build() => FilterStatus.all;

  void setStatus(FilterStatus status) {
    state = status;
  }
}

final filterStatusProvider =
    NotifierProvider<FilterStatusNotifier, FilterStatus>(() {
      return FilterStatusNotifier();
    });

final buildingServiceProvider = Provider<BuildingService>((ref) {
  return BuildingService();
});

final buildingsProvider = StreamProvider<List<Building>>((ref) {
  final buildingService = ref.watch(buildingServiceProvider);
  return buildingService.streamBuildings();
});

final buildingUnitsProvider = StreamProvider.family<List<Unit>, String>((
  ref,
  buildingId,
) {
  final buildingService = ref.watch(buildingServiceProvider);
  return buildingService.streamUnits(buildingId);
});

final locationPermissionProvider = FutureProvider<bool>((ref) async {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) return false;

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) return false;
  }

  if (permission == LocationPermission.deniedForever) return false;

  return true;
});

// A stream provider for live location tracking
final liveLocationProvider = StreamProvider<Position?>((ref) async* {
  final hasPermission = await ref.watch(locationPermissionProvider.future);
  if (!hasPermission) {
    yield null;
    return;
  }

  // Try to yield last known position instantly for a quick map render
  if (!kIsWeb) {
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        yield lastKnown;
      }
    } catch (_) {}
  }

  // Then yield continuous stream which will eventually emit the precise live location

  yield* Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      // Avoid rebuilding the location marker for GPS jitter while the map is
      // being panned or zoomed.
      distanceFilter: 15,
    ),
  );
});

// Backward compatibility or for a one-off fetch
final currentLocationProvider = FutureProvider<Position?>((ref) async {
  final hasPermission = await ref.watch(locationPermissionProvider.future);
  if (!hasPermission) return null;

  Position? lastKnown;
  if (!kIsWeb) {
    lastKnown = await Geolocator.getLastKnownPosition();
  }

  if (lastKnown != null) {
    return lastKnown;
  }

  return await Geolocator.getCurrentPosition(
    desiredAccuracy: LocationAccuracy.bestForNavigation,
  );
});

// Used to track if an admin is moving a building's location
class MoveBuildingNotifier extends Notifier<Building?> {
  @override
  Building? build() => null;

  void setState(Building? building) {
    state = building;
  }
}

final moveBuildingProvider = NotifierProvider<MoveBuildingNotifier, Building?>(
  MoveBuildingNotifier.new,
);
