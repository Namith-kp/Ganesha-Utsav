import '../utils/platform_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:panorama_viewer/panorama_viewer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/street_view_provider.dart';
import '../providers/panorama_download_provider.dart';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import '../models/street_view_node.dart';
import 'package:latlong2/latlong.dart' as latlong;

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
  final FocusNode _focusNode = FocusNode();
  double _panSpeed = 0.0;
  double _zoomLevel = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _cameraLongitude.dispose();
    _focusNode.dispose();
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

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        _handleKeyEvent(event);
        return KeyEventResult.handled;
      },
      autofocus: true,
      child: Scaffold(
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
              onViewChanged: (longitude, latitude, tilt) {
                // Update camera longitude for the navigation dial
                _cameraLongitude.value = longitude;
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
                                  child: Transform.rotate(
                                    angle: -angleRad, // Counter-rotate so it always points 'into' the screen
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
              bottom: 20,
              left: 20,
              right: 160,
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
            
          // Minimap
          if (currentNode != null)
            Positioned(
              bottom: 20,
              right: 20,
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).pop();
                },
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 4)),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: IgnorePointer(
                      child: FlutterMap(
                        key: ValueKey('minimap_${currentNode.id}'),
                        options: MapOptions(
                          initialCenter: latlong.LatLng(currentNode.lat, currentNode.lon),
                          initialZoom: 18.0,
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.none,
                          ),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}',
                            userAgentPackageName: 'com.Dcross.ganeshtracker',
                          ),
                          MarkerLayer(
                            markers: buildings.map((building) {
                              Color pinColor;
                              if (building.collectedCount == 0) {
                                pinColor = Colors.red;
                              } else if (building.collectedCount >= building.totalUnits) {
                                pinColor = Colors.green;
                              } else {
                                pinColor = Colors.orange;
                              }
                              return Marker(
                                point: latlong.LatLng(building.lat, building.lng),
                                width: 24,
                                height: 24,
                                child: Icon(Icons.location_on, color: pinColor, size: 24),
                              );
                            }).toList(),
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: latlong.LatLng(currentNode.lat, currentNode.lon),
                                width: 60,
                                height: 60,
                                child: ValueListenableBuilder<double>(
                                  valueListenable: _cameraLongitude,
                                  builder: (context, cameraLon, child) {
                                    double headingDegrees = currentNode.heading * (180.0 / math.pi);
                                    double absoluteBearing = headingDegrees + cameraLon;
                                    double angleRad = absoluteBearing * (math.pi / 180.0);
                                    
                                    return Transform.rotate(
                                      angle: angleRad,
                                      child: SizedBox(
                                        width: 60,
                                        height: 60,
                                        child: Stack(
                                          alignment: Alignment.center,
                                          clipBehavior: Clip.none,
                                          children: [
                                            // Field of view indicator (blue cone)
                                            CustomPaint(
                                              size: const Size(60, 60),
                                              painter: FieldOfViewPainter(),
                                            ),
                                            // Center dot
                                            Container(
                                              width: 14,
                                              height: 14,
                                              decoration: BoxDecoration(
                                                color: Colors.blue,
                                                shape: BoxShape.circle,
                                                border: Border.all(color: Colors.white, width: 2),
                                                boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black45)],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ));
  }
}
