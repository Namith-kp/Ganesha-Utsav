import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../services/building_service.dart';
import '../models/building.dart';

final buildingServiceProvider = Provider<BuildingService>((ref) {
  return BuildingService();
});

final buildingsProvider = StreamProvider<List<Building>>((ref) {
  final buildingService = ref.watch(buildingServiceProvider);
  return buildingService.streamBuildings();
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

  // Yield current position first for quick UI load
  yield await Geolocator.getCurrentPosition(
    desiredAccuracy: LocationAccuracy.bestForNavigation,
  );

  // Then yield continuous stream
  yield* Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0, // Updates on every possible accuracy improvement
    ),
  );
});

// Backward compatibility or for a one-off fetch
final currentLocationProvider = FutureProvider<Position?>((ref) async {
  final hasPermission = await ref.watch(locationPermissionProvider.future);
  if (!hasPermission) return null;

  return await Geolocator.getCurrentPosition(
    desiredAccuracy: LocationAccuracy.bestForNavigation,
  );
});
