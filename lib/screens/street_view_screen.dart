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
import '../providers/map_provider.dart';
import '../utils/building_dialogs.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/gestures.dart';
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

  void _moveInDirection(double targetRelativeAngle) {
    if (_isTransitioning) return;
    
    final currentId = ref.read(currentPanoramaIdProvider);
    if (currentId == null) return;
    
    final currentNode = ref.read(nodeByIdProvider(currentId));
    if (currentNode == null || currentNode.neighbors.isEmpty) return;

    String? bestNeighbor;
    double smallestDiff = double.infinity;

    for (String neighborId in currentNode.neighbors) {
      final neighborNode = ref.read(nodeByIdProvider(neighborId));
      if (neighborNode == null) continue;

      final distance = const latlong.Distance();
      final bearing = distance.bearing(
        latlong.LatLng(currentNode.lat, currentNode.lon),
        latlong.LatLng(neighborNode.lat, neighborNode.lon),
      );
      
      double headingDegrees = currentNode.heading * (180.0 / math.pi);
      double baseYaw = bearing - headingDegrees;
      double relativeAngle = baseYaw - _cameraLongitude.value;
      
      // Normalize to -180 to 180
      relativeAngle = (relativeAngle + 540) % 360 - 180;
      
      // Calculate angular distance to the target angle (0 for forward, 180 for backward)
      double diff = (relativeAngle - targetRelativeAngle).abs();
      diff = diff > 180 ? 360 - diff : diff;

      if (diff < smallestDiff) {
        smallestDiff = diff;
        bestNeighbor = neighborId;
      }
    }

    // Only move if there is a neighbor roughly in that direction (within 60 degrees)
    if (bestNeighbor != null && smallestDiff <= 60) {
      _navigateToNeighbor(bestNeighbor);
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp || event.logicalKey == LogicalKeyboardKey.keyW) {
        _moveInDirection(0); // Forward
      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown || event.logicalKey == LogicalKeyboardKey.keyS) {
        _moveInDirection(180); // Backward
      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _moveInDirection(-90); // Move Left
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _moveInDirection(90); // Move Right
      } else if (event.logicalKey == LogicalKeyboardKey.keyA) {
        if (_panSpeed == 0) {
          setState(() {
            _initialLongitude = _cameraLongitude.value;
            _panSpeed = 1.5;
          });
        }
      } else if (event.logicalKey == LogicalKeyboardKey.keyD) {
        if (_panSpeed == 0) {
          setState(() {
            _initialLongitude = _cameraLongitude.value;
            _panSpeed = -1.5;
          });
        }
      } else if (event.logicalKey == LogicalKeyboardKey.equal || event.logicalKey == LogicalKeyboardKey.numpadAdd) {
        setState(() { _zoomLevel += 0.2; });
      } else if (event.logicalKey == LogicalKeyboardKey.minus || event.logicalKey == LogicalKeyboardKey.numpadSubtract) {
        setState(() { _zoomLevel = math.max(0.2, _zoomLevel - 0.2); });
      }
    } else if (event is KeyUpEvent) {
      if (event.logicalKey == LogicalKeyboardKey.keyA || event.logicalKey == LogicalKeyboardKey.keyD) {
        setState(() {
          _initialLongitude = _cameraLongitude.value;
          _panSpeed = 0.0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch this to trigger the prefetching logic silently
    ref.watch(prefetchControllerProvider);
    
    final currentId = ref.watch(currentPanoramaIdProvider);
    final currentNode = currentId != null ? ref.watch(nodeByIdProvider(currentId)) : null;

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
            Consumer(
              builder: (context, ref, _) {
                final file = ref.watch(localPanoramaFileProvider(_backgroundId!)).value;
                final String url = 'https://pub-2e6c9cb2a1eb4eb98c8bae3105ebf165.r2.dev/${_backgroundId!}.webp';
                
                final image = (!kIsWeb && file != null)
                    ? Image(image: FileImage(file as dynamic), fit: BoxFit.cover)
                    : Image(image: kIsWeb ? NetworkImage(url) : CachedNetworkImageProvider(url) as ImageProvider, fit: BoxFit.cover);
                
                return PanoramaViewer(
                  key: ValueKey(_backgroundId),
                  longitude: _initialLongitude,
                  animSpeed: 0.0,
                  zoom: _zoomLevel,
                  sensorControl: SensorControl.none,
                  sensitivity: 2.5,
                  child: image,
                );
              }
            ),
          
          // Foreground Layer (fades out during transition)
          GestureDetector(
            behavior: HitTestBehavior.deferToChild,
            onTapUp: (details) {
              final screenHeight = MediaQuery.of(context).size.height;
              // If clicked in the top 75% of the screen, move forward.
              // If clicked in the bottom 25% of the screen, move backward.
              if (details.localPosition.dy < screenHeight * 0.75) {
                _moveInDirection(0);
              } else {
                _moveInDirection(180);
              }
            },
            child: AnimatedOpacity(
              opacity: _isTransitioning ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 500),
              child: Consumer(
                builder: (context, ref, _) {
                  final file = ref.watch(localPanoramaFileProvider(_foregroundId!)).value;
                  final String url = 'https://pub-2e6c9cb2a1eb4eb98c8bae3105ebf165.r2.dev/${_foregroundId!}.webp';

                  final image = (!kIsWeb && file != null)
                      ? Image(image: FileImage(file as dynamic), fit: BoxFit.cover)
                      : Image(image: kIsWeb ? NetworkImage(url) : CachedNetworkImageProvider(url) as ImageProvider, fit: BoxFit.cover);

                  final buildings = ref.watch(buildingsProvider).value ?? [];
                  List<Hotspot> hotspots = [];
                  if (currentNode != null) {
                  final filterStatus = ref.watch(filterStatusProvider);
                  List<Map<String, dynamic>> visibleBuildings = [];
                  for (var building in buildings) {
                    if (filterStatus == FilterStatus.pending && building.collectedCount > 0) continue;
                    if (filterStatus == FilterStatus.partial && (building.collectedCount == 0 || building.collectedCount >= building.totalUnits)) continue;
                    if (filterStatus == FilterStatus.completed && building.collectedCount < building.totalUnits) continue;
                      double distance = Geolocator.distanceBetween(
                        currentNode.lat, currentNode.lon, building.lat, building.lng,
                      );
                      if (distance <= 16) {
                        double bearing = Geolocator.bearingBetween(
                          currentNode.lat, currentNode.lon, building.lat, building.lng,
                        );
                        if (bearing < 0) bearing += 360;
                        double currentHeadingDegrees = currentNode.heading * (180.0 / math.pi);
                        double baseYaw = bearing - currentHeadingDegrees;
                        while (baseYaw < -180) baseYaw += 360;
                        while (baseYaw > 180) baseYaw -= 360;
                        
                        visibleBuildings.add({
                          'building': building,
                          'distance': distance,
                          'yaw': baseYaw,
                        });
                      }
                    }

                    // Sort closest to furthest
                    visibleBuildings.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));

                    // Filter occluded buildings (within 15 degrees of a closer building)
                    List<Map<String, dynamic>> finalVisible = [];
                    for (var bInfo in visibleBuildings) {
                      double currentYaw = bInfo['yaw'] as double;
                      bool occluded = false;
                      for (var closerInfo in finalVisible) {
                        double closerYaw = closerInfo['yaw'] as double;
                        double diff = (currentYaw - closerYaw).abs();
                        if (diff > 180) diff = 360 - diff;
                        if (diff <= 40.0) {
                          occluded = true;
                          break;
                        }
                      }
                      if (!occluded) {
                        finalVisible.add(bInfo);
                      }
                    }

                    // Generate hotspots
                    for (var bInfo in finalVisible) {
                      var building = bInfo['building'];
                      double distance = bInfo['distance'] as double;
                      double baseYaw = bInfo['yaw'] as double;
                      
                      double scale = 1.0 - (distance / 10).clamp(0.0, 0.5);

                      hotspots.add(Hotspot(
                          longitude: baseYaw,
                          latitude: 10.0, // Move it slightly higher up on the building wall
                          width: 1000.0,
                          height: 1000.0,
                          widget: Transform.scale(
                            scale: scale,
                            child: AnimatedBuildingBadge(
                              child: Center(
                                child: GestureDetector(
                                  onTap: () {
                                    showCollectionBottomSheet(context, ref, building);
                                  },
                                  child: Container(
                                    constraints: const BoxConstraints(maxWidth: 280, minWidth: 100),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: building.collectedCount == building.totalUnits 
                                          ? Colors.green.withOpacity(0.9)
                                          : (building.collectedCount > 0 
                                              ? Colors.amber.withOpacity(0.9)
                                              : Colors.redAccent.withOpacity(0.9)),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.white, width: 2),
                                      boxShadow: const [
                                        BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 5))
                                      ],
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          building.name,
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '₹${building.totalCollected.toInt()}',
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ));
                      }
                  }

                  return Listener(
                    onPointerSignal: (pointerSignal) {
                      if (pointerSignal is PointerScrollEvent) {
                        setState(() {
                          if (pointerSignal.scrollDelta.dy > 0) {
                             _zoomLevel = math.max(1.0, _zoomLevel - 0.2); // zoom out
                          } else {
                             _zoomLevel = math.min(5.0, _zoomLevel + 0.2); // zoom in
                          }
                        });
                      }
                    },
                    child: PanoramaViewer(
                      key: ValueKey(_foregroundId),
                      longitude: _initialLongitude,
                      animSpeed: _panSpeed,
                      zoom: _zoomLevel,
                      sensorControl: SensorControl.none,
                      sensitivity: 2.5,
                      hotspots: hotspots,
                      onViewChanged: (longitude, latitude, tilt) {
                        _cameraLongitude.value = longitude;
                      },
                      onLongPressStart: (longitude, latitude, tilt) {
                        if (currentNode != null) {
                          // Convert tapped longitude (yaw) to geographic bearing
                          double currentHeadingDegrees = currentNode.heading * (180.0 / math.pi);
                          double targetBearing = longitude + currentHeadingDegrees;
                          
                          // Project a point 5 meters away in the direction of the tap
                          final constDistance = const latlong.Distance();
                          final projectedLatLng = constDistance.offset(
                            latlong.LatLng(currentNode.lat, currentNode.lon),
                            5.0, // 5 meters distance 
                            targetBearing,
                          );

                          showCreateBuildingDialog(
                            context,
                            ref,
                            projectedLatLng
                          );
                        }
                      },
                      child: image,
                    ),
                  );
                }
              ),
            ),
          ),
          
          // Filter UI at the top right
          Positioned(
            top: 70, // Account for app bar
            right: 16,
            child: Consumer(
                builder: (context, ref, _) {
                  final filterStatus = ref.watch(filterStatusProvider);
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.filter_list, color: Colors.white70, size: 18),
                        const SizedBox(width: 8),
                        DropdownButton<FilterStatus>(
                          value: filterStatus,
                          dropdownColor: Colors.black87,
                          icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                          underline: const SizedBox(),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          onChanged: (FilterStatus? newValue) {
                            if (newValue != null) {
                              ref.read(filterStatusProvider.notifier).setStatus(newValue);
                            }
                          },
                          items: const [
                            DropdownMenuItem(value: FilterStatus.all, child: Text('All Buildings')),
                            DropdownMenuItem(value: FilterStatus.pending, child: Text('Pending Only')),
                            DropdownMenuItem(value: FilterStatus.partial, child: Text('Partially Collected')),
                            DropdownMenuItem(value: FilterStatus.completed, child: Text('Completed Only')),
                          ],
                        ),
                      ],
                    ),
                  );
                }
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
    ));
  }
}

class AnimatedBuildingBadge extends StatefulWidget {
  final Widget child;
  const AnimatedBuildingBadge({super.key, required this.child});

  @override
  State<AnimatedBuildingBadge> createState() => _AnimatedBuildingBadgeState();
}

class _AnimatedBuildingBadgeState extends State<AnimatedBuildingBadge> with SingleTickerProviderStateMixin {
  late AnimationController _entranceController;

  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    // One-time entrance animation
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: const Interval(0.0, 0.5, curve: Curves.easeIn)),
    );
    
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.elasticOut),
    );

    // Slide up from the ground
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 4.0), end: Offset.zero).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.elasticOut),
    );

    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: widget.child,
        ),
      ),
    );
  }
}


