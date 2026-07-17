import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import '../providers/auth_provider.dart';
import '../providers/map_provider.dart';
import '../widgets/building_bottom_sheet.dart';
import '../models/building.dart';
import '../models/unit.dart';
import 'street_view_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final double? initialLat;
  final double? initialLng;

  const HomeScreen({Key? key, this.initialLat, this.initialLng}) : super(key: key);

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final MapController _mapController = MapController();
  String _selectedFilter = 'All'; // 'All', 'Uncollected', 'Pending', 'Completed'

  void _getCurrentLocation() async {
    // If we have initial coordinates from router, move there immediately
    if (widget.initialLat != null && widget.initialLng != null) {
      if (mounted) {
        _mapController.move(LatLng(widget.initialLat!, widget.initialLng!), 18);
        return; // Don't fetch current location if we are navigating to a specific building
      }
    }

    try {
      Position position = await Geolocator.getCurrentPosition();
    } catch (e) {
      // Handle error
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = ref.read(authServiceProvider);
    final locationAsync = ref.watch(currentLocationProvider);
    final liveLocationAsync = ref.watch(liveLocationProvider);
    final buildingsAsync = ref.watch(buildingsProvider);
    final collectorAsync = ref.watch(collectorProfileProvider);
    final isAdmin = collectorAsync.value?.role == 'admin';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ganesha Tracker'),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings, color: Colors.amber),
              tooltip: 'Admin Dashboard',
              onPressed: () {
                context.push('/admin');
              },
            ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Reports',
            onPressed: () {
              context.push('/reports');
            },
          ),
          IconButton(
            icon: const Icon(Icons.view_in_ar),
            tooltip: 'AR Street View',
            onPressed: () {
              context.push('/ar');
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await authService.signOut();
            },
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'streetViewBtn',
            backgroundColor: Colors.indigo,
            onPressed: () {
              final pos = ref.read(liveLocationProvider).value;
              if (pos != null) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => StreetViewScreen(
                      lat: pos.latitude,
                      lon: pos.longitude,
                    ),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Waiting for location...')),
                );
              }
            },
            child: const Icon(Icons.streetview, color: Colors.white),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'myLocationBtn',
            onPressed: () {
              final pos = ref.read(liveLocationProvider).value;
              if (pos != null) {
                _mapController.move(
                  LatLng(pos.latitude, pos.longitude), 
                  _mapController.camera.zoom,
                );
              }
            },
            child: const Icon(Icons.my_location),
          ),
          FloatingActionButton(
            heroTag: 'tagHereBtn',
            backgroundColor: Colors.green,
            onPressed: () async {
              final pos = ref.read(liveLocationProvider).value;
              if (pos == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Waiting for location...')),
                );
                return;
              }
              if (pos.accuracy > 25.0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('GPS accuracy too low (${pos.accuracy.toStringAsFixed(1)}m). Please wait for a better signal.')),
                );
                return;
              }
              _showCreateBuildingDialog(context, ref, LatLng(pos.latitude, pos.longitude));
            },
            child: const Icon(Icons.add_location_alt, color: Colors.white),
          ),
          const SizedBox(height: 16),
        ],
      ),
      body: locationAsync.when(
        data: (position) {
          if (position == null) {
            return const Center(child: Text('Location permission denied.'));
          }

          final initialCenter = LatLng(position.latitude, position.longitude);

          return Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: initialCenter,
                  initialZoom: 18.0, // Zoom in a bit more for building view
                  cameraConstraint: CameraConstraint.contain(
                    bounds: LatLngBounds(
                      const LatLng(13.304145, 77.541547),
                      const LatLng(13.314836, 77.552447),
                    ),
                  ),
                  onTap: (tapPosition, point) {
                    final moveBuilding = ref.read(moveBuildingProvider);
                    if (moveBuilding != null) {
                      // Admin is moving a building
                      showDialog(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('Update Location?'),
                          content: Text('Move ${moveBuilding.name} to this location?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('CANCEL')),
                            TextButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text('UPDATE', style: TextStyle(color: Colors.blue)),
                            ),
                          ],
                        ),
                      ).then((confirm) {
                        if (confirm == true) {
                          ref.read(buildingServiceProvider).updateBuildingLocation(moveBuilding.id, point.latitude, point.longitude);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location updated.')));
                          ref.read(moveBuildingProvider.notifier).setState(null);
                        }
                      });
                      return;
                    }

                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => StreetViewScreen(
                          lat: point.latitude,
                          lon: point.longitude,
                        ),
                      ),
                    );
                  },
                  onLongPress: (tapPosition, point) {
                    if (isAdmin) {
                      _showCreateBuildingDialog(context, ref, point);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please use the green "Tag Here" button to create a tag at your current location.')),
                      );
                    }
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}',
                    userAgentPackageName: 'com.Dcross.ganeshtracker',
                  ),
                  MarkerLayer(
                    markers: buildingsAsync.when(
                      data: (buildings) => _buildMarkers(context, ref, buildings),
                      loading: () => [],
                      error: (err, stack) => [],
                    ),
                  ),
                  MarkerLayer(
                    markers: liveLocationAsync.maybeWhen(
                      data: (pos) => pos == null ? [] : [
                        Marker(
                          point: LatLng(pos.latitude, pos.longitude),
                          width: 30,
                          height: 30,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black45)],
                            ),
                            child: const Icon(Icons.person, color: Colors.white, size: 18),
                          ),
                        ),
                      ],
                      orElse: () => [],
                    ),
                  ),
                ],
              ),
              Positioned(
                top: 10,
                left: 10,
                right: 10,
                child: Consumer(builder: (context, ref, child) {
                  final moveBuilding = ref.watch(moveBuildingProvider);
                  if (moveBuilding != null) {
                    return Card(
                      color: Colors.blue.shade100,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            const Icon(Icons.touch_app, color: Colors.blue),
                            const SizedBox(width: 8),
                            Expanded(child: Text('Tap on the map to move ${moveBuilding.name}')),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => ref.read(moveBuildingProvider.notifier).setState(null),
                            )
                          ],
                        ),
                      ),
                    );
                  }

                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('All', 'All', Colors.grey),
                        const SizedBox(width: 8),
                        _buildFilterChip('Uncollected (Red)', 'Uncollected', Colors.red),
                        const SizedBox(width: 8),
                        _buildFilterChip('Pending (Orange)', 'Pending', Colors.orange),
                        const SizedBox(width: 8),
                        _buildFilterChip('Completed (Green)', 'Completed', Colors.green),
                      ],
                    ),
                  );
                }),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error getting location: \$err')),
      ),
    );
  }

  Widget _buildFilterChip(String label, String filterValue, Color color) {
    final isSelected = _selectedFilter == filterValue;
    return FilterChip(
      label: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontSize: 12)),
      selected: isSelected,
      selectedColor: color,
      backgroundColor: Colors.white.withOpacity(0.9),
      checkmarkColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: isSelected ? color : Colors.grey.shade300),
      ),
      onSelected: (bool selected) {
        setState(() {
          _selectedFilter = filterValue;
        });
      },
    );
  }

  List<Marker> _buildMarkers(BuildContext context, WidgetRef ref, List<Building> buildings) {
    return buildings.where((building) {
      if (_selectedFilter == 'All') return true;
      if (_selectedFilter == 'Uncollected' && building.collectedCount == 0) return true;
      if (_selectedFilter == 'Completed' && building.collectedCount >= building.totalUnits) return true;
      if (_selectedFilter == 'Pending' && building.collectedCount > 0 && building.collectedCount < building.totalUnits) return true;
      return false;
    }).map((building) {
      Color pinColor;
      if (building.collectedCount == 0) {
        pinColor = Colors.red;
      } else if (building.collectedCount >= building.totalUnits) {
        pinColor = Colors.green;
      } else {
        pinColor = Colors.orange;
      }

      return Marker(
        point: LatLng(building.lat, building.lng),
        width: 80,
        height: 80,
        child: GestureDetector(
          onTap: () {
            showBuildingDetailsBottomSheet(context, ref, building);
          },
          child: Column(
            children: [
              if (building.collectedCount > 0 && building.collectedCount < building.totalUnits)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey),
                  ),
                  child: Text(
                    '${building.collectedCount}/${building.totalUnits}',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              Icon(Icons.location_on, color: pinColor, size: 40),
            ],
          ),
        ),
      );
    }).toList();
  }

  void _showCreateBuildingDialog(BuildContext context, WidgetRef ref, LatLng point) {
    final nameController = TextEditingController();
    final unitsController = TextEditingController();
    List<TextEditingController> unitLabelControllers = [];
    bool isApartment = false;
    bool isSubmitting = false;

    void updateUnitControllers(String value) {
      final units = int.tryParse(value) ?? 0;
      if (units > 50) return; // safeguard
      
      if (unitLabelControllers.length < units) {
        for (int i = unitLabelControllers.length; i < units; i++) {
          unitLabelControllers.add(TextEditingController(text: 'House ${i + 1}'));
        }
      } else if (unitLabelControllers.length > units) {
        unitLabelControllers.length = units;
      }
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Add Building'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
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
                          onChanged: (val) {
                            setState(() {
                              updateUnitControllers(val);
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        if (unitLabelControllers.isNotEmpty)
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: unitLabelControllers.length,
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: TextField(
                                  controller: unitLabelControllers[index],
                                  decoration: InputDecoration(
                                    labelText: 'Unit ${index + 1} Name',
                                    isDense: true,
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    ],
                  ),
                ),
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
                    if (authUser == null) return;

                    final buildingService = ref.read(buildingServiceProvider);
                    
                    setState(() => isSubmitting = true);
                    
                    try {
                      if (isApartment) {
                        final units = int.tryParse(unitsController.text) ?? 1;
                        final labels = unitLabelControllers.map((c) => c.text.trim()).toList();
                        // fallback if empty
                        if (labels.isEmpty) {
                          for(int i=0; i<units; i++) labels.add('House ${i+1}');
                        }
                        
                        await buildingService.createMultiUnitBuilding(
                          lat: point.latitude,
                          lng: point.longitude,
                          name: nameController.text.trim(),
                          unitLabels: labels,
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
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('CREATE'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  // _showCollectionBottomSheet replaced by shared showBuildingDetailsBottomSheet
}
