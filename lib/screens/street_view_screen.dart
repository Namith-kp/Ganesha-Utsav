import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:panorama_viewer/panorama_viewer.dart';
import '../providers/street_view_provider.dart';
import '../providers/map_provider.dart';
import '../models/building.dart';
import '../services/street_view_service.dart';

class StreetViewScreen extends ConsumerStatefulWidget {
  final double lat;
  final double lon;

  const StreetViewScreen({
    super.key,
    required this.lat,
    required this.lon,
  });

  @override
  ConsumerState<StreetViewScreen> createState() => _StreetViewScreenState();
}

class _StreetViewScreenState extends ConsumerState<StreetViewScreen> {
  StreetViewPanorama? _panoramaInfo;
  Uint8List? _panoramaImage;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStreetView();
  }

  Future<void> _loadStreetView() async {
    try {
      final service = ref.read(streetViewServiceProvider);
      // Fetch panorama metadata for the location
      final panoInfo = await service.findPanorama(widget.lat, widget.lon);
      
      if (panoInfo == null) {
        if (mounted) {
          setState(() {
            _error = "No Street View coverage found for this location.";
            _isLoading = false;
          });
        }
        return;
      }

      // Download the tiles and stitch them
      final imageBytes = await service.downloadPanoramaImage(panoInfo.id, zoom: 2);
      
      if (imageBytes == null) {
        if (mounted) {
          setState(() {
            _error = "Failed to download Street View image.";
            _isLoading = false;
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _panoramaInfo = panoInfo;
          _panoramaImage = imageBytes;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  double _calculateBearing(double startLat, double startLng, double destLat, double destLng) {
    final dLon = (destLng - startLng) * pi / 180;
    startLat = startLat * pi / 180;
    destLat = destLat * pi / 180;

    final y = sin(dLon) * cos(destLat);
    final x = cos(startLat) * sin(destLat) - sin(startLat) * cos(destLat) * cos(dLon);
    final brng = atan2(y, x);

    return (brng * 180 / pi + 360) % 360;
  }

  double _normalizeAngle(double angle) {
    while (angle <= -180) angle += 360;
    while (angle > 180) angle -= 360;
    return angle;
  }

  List<Hotspot> _buildHotspots(List<Building> buildings) {
    if (_panoramaInfo == null) return [];
    
    final hotspots = <Hotspot>[];
    
    for (final building in buildings) {
      final isCollected = building.collectedCount >= building.totalUnits;
      
      // Calculate bearing from the street view camera to the building
      final bearing = _calculateBearing(
        _panoramaInfo!.lat, _panoramaInfo!.lon,
        building.lat, building.lng,
      );
      
      // Panorama's center is at _panoramaInfo!.heading
      // So the relative longitude in the viewer is (bearing - heading)
      final relativeYaw = _normalizeAngle(bearing - _panoramaInfo!.heading);

      hotspots.add(
        Hotspot(
          latitude: 0.0, // Horizon
          longitude: relativeYaw,
          width: 120,
          height: 60,
          widget: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isCollected ? Colors.green.withOpacity(0.8) : Colors.orange.withOpacity(0.8),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  building.name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  isCollected ? 'Collected' : 'Pending',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ],
            ),
          ),
        )
      );
    }
    
    return hotspots;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text("Street View"), backgroundColor: Colors.transparent, elevation: 0),
        extendBodyBehindAppBar: true,
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text("Loading 360° Panorama..."),
            ],
          ),
        ),
      );
    }

    if (_error != null || _panoramaImage == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Street View")),
        body: Center(child: Text(_error ?? "Unknown error")),
      );
    }

    // Watch buildings to draw tags
    final buildingsAsync = ref.watch(buildingsProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Street View"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 20),
      ),
      body: buildingsAsync.when(
        data: (buildings) {
          final hotspots = _buildHotspots(buildings);
          
          return PanoramaViewer(
            sensorControl: SensorControl.orientation, // Allows gyro if available
            hotspots: hotspots,
            child: Image.memory(_panoramaImage!),
          );
        },
        loading: () => PanoramaViewer(
          child: Image.memory(_panoramaImage!),
        ),
        error: (err, stack) => PanoramaViewer(
          child: Image.memory(_panoramaImage!),
        ),
      ),
    );
  }
}
