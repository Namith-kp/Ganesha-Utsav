import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' as math;
import 'package:google_fonts/google_fonts.dart';
import '../providers/map_provider.dart';
import '../main.dart';
import '../utils/building_dialogs.dart';

class ARViewScreen extends ConsumerStatefulWidget {
  const ARViewScreen({super.key});

  @override
  ConsumerState<ARViewScreen> createState() => _ARViewScreenState();
}

class _ARViewScreenState extends ConsumerState<ARViewScreen> with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  
  // Filtered values for UI rendering
  double _heading = 0.0;
  double _pitch = 0.0;
  
  // Latest raw values from sensors
  double _latestHeading = 0.0;
  double _latestPitch = 0.0;
  
  StreamSubscription<CompassEvent>? _compassSubscription;
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  Ticker? _ticker;

  @override
  void initState() {
    super.initState();
    _initCamera();
    
    _compassSubscription = FlutterCompass.events?.listen((event) {
      if (event.heading != null) {
        double h = event.heading!;
        if (h < 0) h += 360;
        _latestHeading = h;
      }
    });
    
    _accelSubscription = accelerometerEventStream().listen((AccelerometerEvent event) {
      // Pitch: positive when tilting phone up, negative when pointing down.
      _latestPitch = math.atan2(event.z, event.y) * (180 / math.pi);
    });
    
    _ticker = createTicker((_) {
      if (!mounted) return;
      
      bool needsUpdate = false;
      
      // Smooth pitch (Low-pass filter with alpha 0.15 for balance of smooth vs responsive)
      double newPitch = _pitch + (_latestPitch - _pitch) * 0.15;
      if ((newPitch - _pitch).abs() > 0.05) {
        _pitch = newPitch;
        needsUpdate = true;
      }
      
      // Smooth heading (accounting for wrap-around at 360)
      double diff = _latestHeading - _heading;
      while (diff < -180) diff += 360;
      while (diff > 180) diff -= 360;
      
      double newHeading = _heading + (diff * 0.15);
      while (newHeading < 0) newHeading += 360;
      while (newHeading >= 360) newHeading -= 360;
      
      if ((newHeading - _heading).abs() > 0.05) {
        _heading = newHeading;
        needsUpdate = true;
      }
      
      if (needsUpdate) {
        setState(() {});
      }
    });
    
    _ticker?.start();
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
    _ticker?.dispose();
    _compassSubscription?.cancel();
    _accelSubscription?.cancel();
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
    if (kIsWeb) {
      return Scaffold(
        backgroundColor: AppColors.bgBase,
        appBar: AppBar(
          title: Text('AR Street View', style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
          backgroundColor: AppColors.bgCard,
          iconTheme: const IconThemeData(color: AppColors.textPrimary),
        ),
        body: Center(
          child: Text('AR Street View is available only in the mobile app.', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary)),
        ),
      );
    }

    final locationAsync = ref.watch(liveLocationProvider);
    final buildingsAsync = ref.watch(buildingsProvider);

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('AR Street View', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black45,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          // Camera Background
          if (_isCameraInitialized && _cameraController != null)
            SizedBox.expand(
              child: CameraPreview(_cameraController!),
            )
          else
            const Center(child: CircularProgressIndicator(color: AppColors.accent)),

          // Compass Heading overlay for debugging/context
          Positioned(
            top: 100,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                'Heading: ${_heading.toStringAsFixed(1)}°',
                style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ),

          // Building AR Overlays
          locationAsync.when(
            data: (location) {
              return buildingsAsync.when(
                data: (buildings) {
                  if (location == null) return const SizedBox.shrink();

                  // 1. Calculate bearing and distance for all buildings, and filter out distant ones
                  List<Map<String, dynamic>> visibleData = [];
                  for (var building in buildings) {
                      double distance = Geolocator.distanceBetween(
                        location.latitude,
                        location.longitude,
                        building.lat,
                        building.lng,
                      );

                      // Only show buildings within 1km
                      if (distance > 1000) continue;

                      double bearing = Geolocator.bearingBetween(
                        location.latitude,
                        location.longitude,
                        building.lat,
                        building.lng,
                      );
                      
                      if (bearing < 0) bearing += 360;

                      visibleData.add({
                          'building': building,
                          'distance': distance,
                          'bearing': bearing,
                      });
                  }

                  // 2. Sort by distance so closer buildings are processed first
                  visibleData.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));

                  // 3. Occlusion filtering
                  List<Map<String, dynamic>> unoccludedData = [];
                  for (var data in visibleData) {
                      double bearing = data['bearing'];
                      double distance = data['distance'];
                      bool occluded = false;

                      for (var closer in unoccludedData) {
                          double closerBearing = closer['bearing'];
                          double closerDistance = closer['distance'];

                          // Dynamic angular width based on distance (assume 8m wide building)
                          double angularWidth = (math.atan2(8.0 / 2, closerDistance == 0 ? 0.1 : closerDistance) * (180.0 / math.pi));
                          double dynamicThreshold = (angularWidth * 1.5).clamp(15.0, 90.0);

                          double diff = _angleDifference(bearing, closerBearing).abs();

                          if (diff < dynamicThreshold) {
                              occluded = true;
                              break;
                          }
                      }

                      if (!occluded) {
                          unoccludedData.add(data);
                      }
                  }

                  // 4. Render unoccluded buildings
                  return SizedBox.expand(
                    child: Stack(
                      children: unoccludedData.map((data) {
                      final building = data['building'];
                      final distance = data['distance'];
                      final bearing = data['bearing'];

                      // Calculate the difference between phone heading and building bearing
                      double diff = _angleDifference(_heading, bearing);

                      // Field of View (FOV) roughly 60 degrees (-30 to +30)
                      const double fov = 60.0;
                      
                      if (diff.abs() > fov / 2) {
                        return const SizedBox.shrink();
                      }

                      // Screen mapping
                      final screenWidth = MediaQuery.of(context).size.width;
                      final screenHeight = MediaQuery.of(context).size.height;

                      // Normalised X position (-1.0 to 1.0)
                      final normalizedX = diff / (fov / 2);
                      
                      // Convert to absolute pixel position
                      final dx = (screenWidth / 2) + (normalizedX * (screenWidth / 2));
                      
                      // Calculate 3D Pitch (Vertical Angle) of the building based on distance
                      // Assuming the tag is rendered 3 meters above the camera level
                      double heightAboveCamera = 3.0; 
                      double buildingPitchDeg = math.atan2(heightAboveCamera, distance == 0 ? 0.1 : distance) * (180.0 / math.pi);
                      
                      // Calculate difference between building pitch and device pitch
                      double pitchDiff = buildingPitchDeg - _pitch;
                      
                      // Map pitch to Y position on screen.
                      // Vertical FOV is roughly 45 degrees (-22.5 to 22.5). Center of screen is 0 pitch.
                      const double vFov = 45.0;
                      
                      // The higher the pitchDiff, the higher on the screen (lower Y value)
                      final normalizedY = pitchDiff / (vFov / 2);
                      final dy = (screenHeight / 2) - (normalizedY * (screenHeight / 2));
                      
                      bool isFullyCollected = building.collectedCount >= building.totalUnits;
                      bool hasCollections = building.collectedCount > 0;

                      return Positioned(
                        left: dx - 125, // Center the 250px width widget
                        top: dy - 75, // Center the 150px height widget
                        child: SizedBox(
                          width: 250,
                          height: 150,
                          child: Center(
                            child: GestureDetector(
                              onTap: () => showCollectionBottomSheet(context, ref, building),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: isFullyCollected ? AppColors.green.withValues(alpha: 0.9) : (hasCollections ? AppColors.amber.withValues(alpha: 0.9) : AppColors.crimson.withValues(alpha: 0.9)),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.white, width: 2),
                                      boxShadow: const [
                                        BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 2))
                                      ]
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          building.name,
                                          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (hasCollections && building.totalCollected > 0)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 2),
                                            child: Text(
                                              '₹${building.totalCollected.toStringAsFixed(0)}',
                                              style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        Text(
                                          '${distance.toInt()}m',
                                          style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_drop_down,
                                    color: isFullyCollected ? AppColors.green : (hasCollections ? AppColors.amber : AppColors.crimson),
                                    size: 30,
                                    shadows: const [
                                      Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 2))
                                    ],
                                  ),
                                ],
                              ),
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
