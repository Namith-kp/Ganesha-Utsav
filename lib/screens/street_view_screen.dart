import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:panorama_viewer/panorama_viewer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/street_view_provider.dart';
import 'dart:math' as math;
import '../models/street_view_node.dart';
import 'package:latlong2/latlong.dart' as latlong;
import '../providers/map_provider.dart';
import '../models/building.dart';
import '../providers/auth_provider.dart';
import '../services/building_service.dart';

double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  const R = 6371e3; // metres
  final phi1 = lat1 * math.pi / 180;
  final phi2 = lat2 * math.pi / 180;
  final deltaPhi = (lat2 - lat1) * math.pi / 180;
  final deltaLambda = (lon2 - lon1) * math.pi / 180;

  final a = math.sin(deltaPhi / 2) * math.sin(deltaPhi / 2) +
      math.cos(phi1) * math.cos(phi2) *
      math.sin(deltaLambda / 2) * math.sin(deltaLambda / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

  return R * c;
}

class StreetViewScreen extends ConsumerStatefulWidget {
  final double lat;
  final double lon;

  const StreetViewScreen({Key? key, required this.lat, required this.lon}) : super(key: key);

  @override
  _StreetViewScreenState createState() => _StreetViewScreenState();
}

class _StreetViewScreenState extends ConsumerState<StreetViewScreen> {
  String? _foregroundId;
  String? _backgroundId;
  bool _isTransitioning = false;
  final ValueNotifier<double> _cameraLongitude = ValueNotifier<double>(0.0);
  double _initialLongitude = 0.0;

  @override
  void initState() {
    super.initState();
    // Foreground ID will be resolved in build() based on lat/lon
  }

  @override
  void dispose() {
    _cameraLongitude.dispose();
    super.dispose();
  }

  void _navigateToNeighbor(String nextId) {
    if (_isTransitioning) return;
    
    // Maintain geographic viewing direction across transitions
    final currentId = ref.read(currentPanoramaIdProvider);
    if (currentId != null) {
      final currentNode = ref.read(nodeByIdProvider(currentId));
      final nextNode = ref.read(nodeByIdProvider(nextId));
      if (currentNode != null && nextNode != null) {
        double currentHeading = currentNode.heading * (180.0 / math.pi);
        double geographicDirection = _cameraLongitude.value + currentHeading;
        
        double nextHeading = nextNode.heading * (180.0 / math.pi);
        _initialLongitude = geographicDirection - nextHeading;
        _initialLongitude = (_initialLongitude + 540) % 360 - 180;
        
        // Update dial instantly so it doesn't snap
        _cameraLongitude.value = _initialLongitude;
      }
    }
    
    // Set background to the new image, trigger state update to start prefetching
    ref.read(currentPanoramaIdProvider.notifier).updateId(nextId);
    
    setState(() {
      _backgroundId = nextId;
      _isTransitioning = true;
    });

    // Wait for a short duration for the fade transition to happen
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() {
          // The background image is now fully visible, make it the foreground
          _foregroundId = nextId;
          _backgroundId = null;
          _isTransitioning = false;
        });
      }
    });
  }

  void _showCreateBuildingDialog(BuildContext context, latlong.LatLng point) {
    final nameController = TextEditingController();
    final unitsController = TextEditingController();
    bool isApartment = false;
    bool isSubmitting = false;
    
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Add Building'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Building Name / Landmark'),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Multi-unit apartment'),
                    value: isApartment,
                    onChanged: (val) {
                      setState(() => isApartment = val);
                    },
                  ),
                  if (isApartment) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: unitsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Number of Units'),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('CANCEL'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting ? null : () async {
                    if (nameController.text.trim().isEmpty) return;

                    final authUser = ref.read(authStateProvider).value;
                    if (authUser == null) {
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Not logged in')));
                      return;
                    }

                    final buildingService = BuildingService();
                    
                    setState(() => isSubmitting = true);
                    
                    try {
                      if (isApartment) {
                        final units = int.tryParse(unitsController.text) ?? 1;
                        await buildingService.createMultiUnitBuilding(
                          lat: point.latitude,
                          lng: point.longitude,
                          name: nameController.text.trim(),
                          totalUnits: units,
                          createdBy: authUser.uid,
                        );
                      } else {
                        await buildingService.createSingleUnitBuilding(
                          lat: point.latitude,
                          lng: point.longitude,
                          name: nameController.text.trim(),
                          type: 'house',
                          createdBy: authUser.uid,
                        );
                      }
                      if (ctx.mounted) {
                        Navigator.of(ctx).pop();
                      }
                    } catch (e) {
                      setState(() => isSubmitting = false);
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('Error adding building: $e')),
                        );
                      }
                    }
                  },
                  child: isSubmitting 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) 
                    : const Text('SAVE'),
                ),
              ],
            );
          }
        );
      }
    );
  }

  List<Hotspot> _buildHotspots(StreetViewNode? currentNode, List<Building> buildings) {
    if (currentNode == null) return [];
    
    List<Hotspot> hotspots = [];
    final distanceCalc = const latlong.Distance();
    
    // First, collect data for all buildings within range
    List<Map<String, dynamic>> visibleData = [];
    
    for (var building in buildings) {
      double dist = distanceCalc(
        latlong.LatLng(currentNode.lat, currentNode.lon),
        latlong.LatLng(building.lat, building.lng),
      );
      
      // Limit range to 16 meters
      if (dist > 16) continue;
      
      double bearing = distanceCalc.bearing(
        latlong.LatLng(currentNode.lat, currentNode.lon),
        latlong.LatLng(building.lat, building.lng),
      );
      
      double headingDegrees = currentNode.heading * (180.0 / math.pi);
      double relativeYaw = bearing - headingDegrees;
      relativeYaw = (relativeYaw + 540) % 360 - 180;
      
      visibleData.add({
        'building': building,
        'dist': dist,
        'yaw': relativeYaw,
      });
    }
    
    // Sort by distance (closest first)
    visibleData.sort((a, b) => (a['dist'] as double).compareTo(b['dist'] as double));
    
    // Filter out occluded buildings and build hotspots
    List<Map<String, dynamic>> unoccludedData = [];
    
    for (var data in visibleData) {
      double yaw = data['yaw'];
      double dist = data['dist'];
      bool occluded = false;
      
      for (var closer in unoccludedData) {
        double closerYaw = closer['yaw'];
        double closerDist = closer['dist'];
        
        // Calculate dynamic angular width based on distance. 
        // Assume an average building is 8 meters wide.
        double angularWidth = (math.atan2(8.0 / 2, closerDist == 0 ? 0.1 : closerDist) * (180.0 / math.pi));
        
        // The closer a building is, the wider the angle it blocks. 
        // We clamp it between 15 and 90 degrees to be safe.
        double dynamicThreshold = (angularWidth * 1.5).clamp(15.0, 90.0);
        
        double diff = (yaw - closerYaw).abs();
        if (diff > 180) diff = 360 - diff;
        
        // If it's behind a closer building and within its angular shadow, hide it!
        if (diff < dynamicThreshold) {
          occluded = true;
          break;
        }
      }
      
      if (!occluded) {
        unoccludedData.add(data);
        
        var building = data['building'];
        double dist = data['dist'];
        
        // Calculate scale based on distance: 
        double scaleFactor = (1.5 - (dist / 16.0) * 0.9).clamp(0.6, 1.5);
        bool isCollected = building.collectedCount > 0;
        
        // Calculate 3D Pitch (Vertical Angle)
        double heightAboveCamera = 3.0; 
        double pitchRad = math.atan2(heightAboveCamera, dist == 0 ? 0.1 : dist);
        double pitchDeg = pitchRad * (180.0 / math.pi);
        
        hotspots.add(
          Hotspot(
            latitude: pitchDeg, // Dynamically set vertical height based on distance!
            longitude: yaw,
            width: 250, // Fixed layout width to prevent overflow
          height: 150, // Fixed layout height to prevent overflow
          widget: Transform.scale(
            scale: scaleFactor,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isCollected ? Colors.green.withOpacity(0.9) : Colors.orange.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 4, offset: const Offset(0, 2))
                    ]
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        building.name,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        textAlign: TextAlign.center,
                        maxLines: 2, // Allow name to wrap
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (isCollected && building.totalCollected > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '₹${building.totalCollected.toStringAsFixed(0)}',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down,
                  color: isCollected ? Colors.green : Colors.orange,
                  size: 30,
                  shadows: [
                    Shadow(color: Colors.black.withOpacity(0.5), blurRadius: 4, offset: const Offset(0, 2))
                  ],
                ),
              ],
            ),
          ),
          ),
        )
      );
      }
    }
    
    return hotspots;
  }

  @override
  Widget build(BuildContext context) {
    // Watch this to trigger the prefetching logic silently
    ref.watch(prefetchControllerProvider);
    
    final currentId = ref.watch(currentPanoramaIdProvider);
    final currentNode = currentId != null ? ref.watch(nodeByIdProvider(currentId)) : null;
    final buildingsAsync = ref.watch(buildingsProvider);
    final buildings = buildingsAsync.value ?? [];

    if (_foregroundId == null) {
      final nodesAsync = ref.watch(streetViewNodesProvider);
      return nodesAsync.when(
        data: (nodes) {
          if (nodes.isEmpty) {
            return const Scaffold(body: Center(child: Text("No panoramas available.")));
          }
          
          StreetViewNode? closestNode;
          double minDistance = double.infinity;
          for (var node in nodes) {
            double dist = _calculateDistance(widget.lat, widget.lon, node.lat, node.lon);
            if (dist < minDistance) {
              minDistance = dist;
              closestNode = node;
            }
          }
          
          if (closestNode != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _foregroundId == null) {
                ref.read(currentPanoramaIdProvider.notifier).updateId(closestNode!.id);
                setState(() {
                  _foregroundId = closestNode!.id;
                });
              }
            });
          }
          
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: CircularProgressIndicator()),
          );
        },
        loading: () => const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator())),
        error: (err, stack) => Scaffold(backgroundColor: Colors.black, body: Center(child: Text('Error loading panoramas: $err', style: const TextStyle(color: Colors.white)))),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          // Background Layer (loads next image during transition)
          if (_backgroundId != null)
            PanoramaViewer(
              key: ValueKey(_backgroundId),
              longitude: _initialLongitude,
              animSpeed: 0.0,
              sensorControl: SensorControl.none,
              sensitivity: 2.5,
              hotspots: _backgroundId != null ? _buildHotspots(ref.read(nodeByIdProvider(_backgroundId!)), buildings) : [],
              child: Image(
                image: CachedNetworkImageProvider('$baseUrl/$_backgroundId.webp'),
              ),
            ),
          
          // Foreground Layer (fades out during transition)
          AnimatedOpacity(
            opacity: _isTransitioning ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 500),
            child: PanoramaViewer(
              key: ValueKey(_foregroundId),
              longitude: _initialLongitude,
              animSpeed: 0.0,
              sensorControl: SensorControl.none,
              sensitivity: 2.5,
              hotspots: _buildHotspots(currentNode, buildings),
              onViewChanged: (longitude, latitude, tilt) {
                // Update camera longitude for the navigation dial
                _cameraLongitude.value = longitude;
              },
              onLongPressStart: (longitude, latitude, tilt) {
                if (currentNode == null) return;
                
                // Convert heading from radians to degrees
                double headingDegrees = currentNode.heading * (180.0 / math.pi);
                
                // Absolute bearing of the tap
                double absoluteBearing = headingDegrees + longitude;
                
                // Estimate distance based on pitch (latitude)
                double distanceInMeters = 6.0; // default for tapping above horizon
                if (latitude < 0) {
                  // User tapped below horizon
                  double pitchRad = latitude.abs() * (math.pi / 180.0);
                  if (pitchRad > 0.05) { // avoid division by near-zero
                    distanceInMeters = 2.5 / math.tan(pitchRad);
                  }
                }
                
                // Clamp distance to reasonable limits
                distanceInMeters = distanceInMeters.clamp(2.0, 16.0);
                
                final distanceCalc = const latlong.Distance();
                final targetLatLng = distanceCalc.offset(
                  latlong.LatLng(currentNode.lat, currentNode.lon),
                  distanceInMeters,
                  absoluteBearing,
                );
                
                _showCreateBuildingDialog(context, targetLatLng);
              },
              child: Image(
                image: CachedNetworkImageProvider('$baseUrl/$_foregroundId.webp'),
              ),
            ),
          ),
          
          // Fixed Bottom Navigation Dial (Google Street View Style)
          if (currentNode != null && !_isTransitioning)
            Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: Center(
                child: ValueListenableBuilder<double>(
                  valueListenable: _cameraLongitude,
                  builder: (context, cameraLon, child) {
                    return Transform(
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.002) // Perspective distortion
                        ..rotateX(1.3), // Tilt back to lay flat on the ground
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: 250,
                        height: 250,
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: currentNode.neighbors.map((neighborId) {
                            final neighborNode = ref.read(nodeByIdProvider(neighborId));
                            if (neighborNode == null) return const SizedBox.shrink();
                            
                            // Calculate geographic bearing
                            final distance = const latlong.Distance();
                            final bearing = distance.bearing(
                              latlong.LatLng(currentNode.lat, currentNode.lon),
                              latlong.LatLng(neighborNode.lat, neighborNode.lon),
                            );
                            
                            // Convert heading from radians to degrees
                            double headingDegrees = currentNode.heading * (180.0 / math.pi);
                            
                            // Calculate base yaw (where the node is when camera looks straight)
                            double baseYaw = bearing - headingDegrees;
                            
                            // Calculate relative angle on the screen
                            double relativeAngle = baseYaw - cameraLon;
                            
                            // Convert to radians for UI rotation
                            double angleRad = relativeAngle * (math.pi / 180.0);
                            
                            return Transform(
                              transform: Matrix4.identity()
                                ..rotateZ(angleRad)
                                ..translate(0.0, -110.0), // Push outwards by radius
                              alignment: Alignment.center,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _navigateToNeighbor(neighborId),
                                child: Container(
                                  // Increase hit area slightly
                                  padding: const EdgeInsets.all(10),
                                  child: const Icon(
                                    Icons.keyboard_arrow_up_rounded,
                                    size: 100,
                                    color: Colors.white,
                                    shadows: [
                                      Shadow(color: Colors.black87, blurRadius: 15, offset: Offset(0, 5))
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          
          // Overlay information
          if (currentNode != null && currentNode.address.isNotEmpty)
            Positioned(
              bottom: 40,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      currentNode.address,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
