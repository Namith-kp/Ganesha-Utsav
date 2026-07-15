import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:panorama_viewer/panorama_viewer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/street_view_provider.dart';
import 'dart:math' as math;
import '../models/street_view_node.dart';

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

double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
  final phi1 = lat1 * math.pi / 180;
  final phi2 = lat2 * math.pi / 180;
  final deltaLambda = (lon2 - lon1) * math.pi / 180;

  final y = math.sin(deltaLambda) * math.cos(phi2);
  final x = math.cos(phi1) * math.sin(phi2) -
      math.sin(phi1) * math.cos(phi2) * math.cos(deltaLambda);

  final bearing = math.atan2(y, x);
  return (bearing * 180 / math.pi + 360) % 360;
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

  @override
  void initState() {
    super.initState();
    // Foreground ID will be resolved in build() based on lat/lon
  }

  void _navigateToNeighbor(String nextId) {
    if (_isTransitioning) return;
    
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
            AnimatedScale(
              scale: _isTransitioning ? 1.0 : 0.8, // Pushes into view
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              child: PanoramaViewer(
                animSpeed: 0.0,
                sensorControl: SensorControl.none,
                sensitivity: 2.5, // Increased sensitivity for easier panning
                child: Image(
                  image: CachedNetworkImageProvider('$baseUrl/$_backgroundId.webp'),
                ),
              ),
            ),
          
          // Foreground Layer (fades out during transition)
          AnimatedOpacity(
            opacity: _isTransitioning ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOut,
            child: AnimatedScale(
              scale: _isTransitioning ? 1.5 : 1.0, // Zooms past the camera like Street View
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInCubic,
              child: PanoramaViewer(
                animSpeed: 0.0,
                sensorControl: SensorControl.none,
                sensitivity: 2.5, // Increased sensitivity for easier panning
              hotspots: currentNode != null
                  ? currentNode.neighbors.map((neighborId) {
                      final allNodes = ref.read(streetViewNodesProvider).value ?? [];
                      StreetViewNode? neighborNode;
                      try {
                        neighborNode = allNodes.firstWhere((n) => n.id == neighborId);
                      } catch (e) {}

                      double hotspotLongitude = 0.0;
                      if (neighborNode != null) {
                        double bearing = _calculateBearing(
                            currentNode.lat, currentNode.lon,
                            neighborNode.lat, neighborNode.lon);
                        
                        double headingDegrees = currentNode.heading * 180 / math.pi;
                        hotspotLongitude = bearing - headingDegrees;
                        hotspotLongitude = (hotspotLongitude + 180) % 360 - 180;
                      }

                      return Hotspot(
                        latitude: -25.0, // Look further down on the road
                        longitude: hotspotLongitude,
                        width: 120,
                        height: 120,
                        widget: GestureDetector(
                          onTap: () => _navigateToNeighbor(neighborId),
                          child: Transform(
                            transform: Matrix4.identity()
                              ..setEntry(3, 2, 0.002) // Add 3D perspective
                              ..rotateX(1.2), // Lay it flat on the ground
                            alignment: FractionalOffset.center,
                            child: Icon(
                              Icons.keyboard_double_arrow_up_rounded,
                              color: Colors.white.withOpacity(0.85),
                              size: 120,
                              shadows: const [
                                Shadow(
                                  blurRadius: 15.0,
                                  color: Colors.black87,
                                  offset: Offset(0, 5),
                                )
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList()
                  : [],
              child: Image(
                image: CachedNetworkImageProvider('$baseUrl/$_foregroundId.webp'),
              ),
            ),
          ),
          ),
          
          // Overlay information
          if (currentNode != null)
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
                      'ID: ${currentNode.id}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    if (currentNode.address.isNotEmpty)
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
