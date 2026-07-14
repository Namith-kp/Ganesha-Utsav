import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../providers/map_provider.dart';

class ARViewScreen extends ConsumerStatefulWidget {
  const ARViewScreen({super.key});

  @override
  ConsumerState<ARViewScreen> createState() => _ARViewScreenState();
}

class _ARViewScreenState extends ConsumerState<ARViewScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  double _heading = 0.0;
  bool _isCameraInitialized = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
    FlutterCompass.events?.listen((event) {
      if (mounted && event.heading != null) {
        setState(() {
          _heading = event.heading!;
          // Normalise to 0-360
          if (_heading < 0) _heading += 360;
        });
      }
    });
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        _cameraController = CameraController(
          _cameras![0], // Back camera usually
          ResolutionPreset.high,
          enableAudio: false,
        );
        await _cameraController!.initialize();
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  // Calculate shortest difference between two angles (returns -180 to 180)
  double _angleDifference(double a1, double a2) {
    double diff = a2 - a1;
    while (diff < -180) { diff += 360; }
    while (diff > 180) { diff -= 360; }
    return diff;
  }

  @override
  Widget build(BuildContext context) {
    final locationAsync = ref.watch(liveLocationProvider);
    final buildingsAsync = ref.watch(buildingsProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('AR Street View'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 20),
      ),
      body: Stack(
        children: [
          // Camera Background
          if (_isCameraInitialized && _cameraController != null)
            SizedBox.expand(
              child: CameraPreview(_cameraController!),
            )
          else
            const Center(child: CircularProgressIndicator()),

          // Compass Heading overlay for debugging/context
          Positioned(
            top: 100,
            left: 16,
            child: Container(
              padding: const EdgeInsets.all(8),
              color: Colors.black54,
              child: Text(
                'Heading: ${_heading.toStringAsFixed(1)}°',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),

          // Building AR Overlays
          locationAsync.when(
            data: (location) {
              return buildingsAsync.when(
                data: (buildings) {
                  return SizedBox.expand(
                    child: Stack(
                      children: buildings.map((building) {
                        if (location == null) return const SizedBox.shrink();
                      // 1. Calculate bearing and distance from current location to building
                      double distance = Geolocator.distanceBetween(
                        location.latitude,
                        location.longitude,
                        building.lat,
                        building.lng,
                      );

                      // Only show buildings within 1km
                      if (distance > 1000) return const SizedBox.shrink();

                      double bearing = Geolocator.bearingBetween(
                        location.latitude,
                        location.longitude,
                        building.lat,
                        building.lng,
                      );
                      
                      if (bearing < 0) bearing += 360;

                      // 2. Calculate the difference between phone heading and building bearing
                      double diff = _angleDifference(_heading, bearing);

                      // Field of View (FOV) roughly 60 degrees (-30 to +30)
                      const double fov = 60.0;
                      
                      // 3. Map the difference to screen coordinates
                      // If diff is 0, it's center screen.
                      // If diff is -30, it's far left. If +30, far right.
                      if (diff.abs() > fov / 2) {
                        // Outside of view
                        return const SizedBox.shrink();
                      }

                      // Screen mapping
                      final screenWidth = MediaQuery.of(context).size.width;
                      final screenHeight = MediaQuery.of(context).size.height;

                      // Normalised X position (-1.0 to 1.0)
                      final normalizedX = diff / (fov / 2);
                      
                      // Convert to absolute pixel position
                      final dx = (screenWidth / 2) + (normalizedX * (screenWidth / 2));
                      
                      // Y position based on distance (closer = lower on screen)
                      // Scale distance from 0 to 500m to height ranges
                      double dy = screenHeight / 2; // Center horizontally
                      
                      // Scale factor for badge based on distance
                      double scale = 1.0 - (distance / 1000).clamp(0.0, 0.8);

                      return Positioned(
                        left: dx - 75, // Adjust for badge width roughly
                        top: dy,
                        child: Transform.scale(
                          scale: scale,
                          child: Container(
                            width: 150,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: building.collectedCount == building.totalUnits 
                                  ? Colors.green.withValues(alpha: 0.9)
                                  : Colors.blue.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black45,
                                  blurRadius: 10,
                                  offset: Offset(0, 5),
                                )
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  building.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${distance.toInt()}m',
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ));
                },
                loading: () => const SizedBox.shrink(),
                error: (err, stack) => const SizedBox.shrink(),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (err, stack) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
