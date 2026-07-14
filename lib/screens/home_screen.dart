import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../providers/map_provider.dart';
import '../models/building.dart';
import '../models/unit.dart';
import 'street_view_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final MapController _mapController = MapController();

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
        ],
      ),
      body: locationAsync.when(
        data: (position) {
          if (position == null) {
            return const Center(child: Text('Location permission denied.'));
          }

          final initialCenter = LatLng(position.latitude, position.longitude);

          return FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: 18.0, // Zoom in a bit more for building view
              onLongPress: (tapPosition, point) {
                _showCreateBuildingDialog(context, ref, point);
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
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error getting location: \$err')),
      ),
    );
  }

  List<Marker> _buildMarkers(BuildContext context, WidgetRef ref, List<Building> buildings) {
    return buildings.map((building) {
      Color pinColor;
      if (building.collectedCount == 0) {
        pinColor = Colors.red;
      } else if (building.collectedCount >= building.totalUnits) {
        pinColor = Colors.green;
      } else {
        pinColor = Colors.yellow;
      }

      return Marker(
        point: LatLng(building.lat, building.lng),
        width: 60,
        height: 60,
        child: GestureDetector(
          onTap: () {
            _showCollectionBottomSheet(context, ref, building);
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
                    if (authUser == null) return;

                    final buildingService = ref.read(buildingServiceProvider);
                    
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

  void _showCollectionBottomSheet(BuildContext context, WidgetRef ref, Building building) {
    final buildingService = ref.read(buildingServiceProvider);
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StreamBuilder<List<Unit>>(
          stream: buildingService.streamUnits(building.id),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            
            final units = snapshot.data!;
            if (units.isEmpty) return const Center(child: Text('No units found.'));
            
            if (building.totalUnits > 1) {
              return DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.6,
                builder: (context, scrollController) {
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text('${building.name} - Units', style: Theme.of(context).textTheme.titleLarge),
                      ),
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          itemCount: units.length,
                          itemBuilder: (context, index) {
                            final unit = units[index];
                            final isCollected = unit.status == 'collected';
                            return ListTile(
                              title: Text(unit.unitLabel),
                              trailing: Chip(
                                label: Text(isCollected ? 'Collected' : 'Pending', 
                                  style: TextStyle(color: isCollected ? Colors.white : Colors.black)
                                ),
                                backgroundColor: isCollected ? Colors.green : Colors.grey[300],
                              ),
                              onTap: () {
                                _showUnitAmountForm(context, ref, building, unit);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              );
            } else {
              // Single unit logic
              final unit = units.first;
              return Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
                child: _buildAmountForm(context, ref, building, unit),
              );
            }
          },
        );
      },
    );
  }

  void _showUnitAmountForm(BuildContext context, WidgetRef ref, Building building, Unit unit) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: _buildAmountForm(ctx, ref, building, unit),
        );
      },
    );
  }

  Widget _buildAmountForm(BuildContext context, WidgetRef ref, Building building, Unit unit) {
    final isAdmin = ref.read(collectorProfileProvider).value?.role == 'admin';
    final isAlreadyCollected = unit.status == 'collected';

    if (isAlreadyCollected && !isAdmin) {
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${building.name} - ${unit.unitLabel}', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            if (unit.photoBase64 != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  base64Decode(unit.photoBase64!),
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 16),
            ],
            const Icon(Icons.check_circle, color: Colors.green, size: 64),
            const SizedBox(height: 16),
            Text('Amount Collected: ₹${unit.amount}'),
            const SizedBox(height: 24),
            const Text('Only admins can edit collected units.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    final amountController = TextEditingController(text: isAlreadyCollected ? unit.amount.toString() : '');
    bool isSubmitting = false;
    String? photoBase64 = unit.photoBase64;

    return StatefulBuilder(
      builder: (ctx, setState) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Collect for: ${building.name} - ${unit.unitLabel}', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              if (photoBase64 != null) ...[
                Stack(
                  alignment: Alignment.topRight,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        base64Decode(photoBase64!),
                        height: 150,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => setState(() => photoBase64 = null),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Amount (₹)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.camera_alt, size: 32, color: Colors.blue),
                    onPressed: () async {
                      final picker = ImagePicker();
                      final image = await picker.pickImage(
                        source: ImageSource.camera,
                        imageQuality: 30, // heavy compression
                        maxWidth: 600,
                      );
                      if (image != null) {
                        final bytes = await image.readAsBytes();
                        setState(() {
                          photoBase64 = base64Encode(bytes);
                        });
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isSubmitting ? null : () async {
                    final amount = double.tryParse(amountController.text) ?? 0.0;
                    if (amount <= 0) return;

                    final authUser = ref.read(authStateProvider).value;
                    if (authUser == null) return;

                    setState(() => isSubmitting = true);
                    
                    try {
                      final buildingService = ref.read(buildingServiceProvider);
                      await buildingService.markUnitCollected(
                        buildingId: building.id,
                        unitId: unit.id,
                        amount: amount,
                        collectedBy: authUser.uid,
                        photoBase64: photoBase64,
                      );
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    } catch (e) {
                       setState(() => isSubmitting = false);
                       if (ctx.mounted) {
                         ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e')));
                       }
                    }
                  },
                  child: isSubmitting 
                      ? const CircularProgressIndicator()
                      : Text(isAlreadyCollected ? 'UPDATE AMOUNT' : 'MARK COLLECTED'),
                ),
              ),
            ],
          ),
        );
      }
    );
  }
}
