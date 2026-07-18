import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import '../providers/auth_provider.dart';
import '../providers/map_provider.dart';
import '../models/building.dart';
import '../models/unit.dart';
import '../main.dart';
import 'street_view_screen.dart';
import 'panorama_download_screen.dart';
import '../utils/building_dialogs.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final double? initialLat;
  final double? initialLng;

  const HomeScreen({Key? key, this.initialLat, this.initialLng}) : super(key: key);

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final MapController _mapController = MapController();
  String _selectedFilter = 'all';

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
        backgroundColor: const Color(0xF50A0D14),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🙏', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [AppColors.gold, AppColors.saffron],
              ).createShader(bounds),
              child: Text(
                'Ganesha Tracker',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (isAdmin)
            _NavIconButton(
              icon: Icons.admin_panel_settings,
              tooltip: 'Admin Dashboard',
              color: AppColors.gold,
              onPressed: () => context.push('/admin'),
            ),
          _NavIconButton(
            icon: Icons.bar_chart,
            tooltip: 'Reports',
            onPressed: () => context.push('/reports'),
          ),
          _NavIconButton(
            icon: Icons.threesixty,
            tooltip: '360 Street View',
            color: AppColors.gold,
            onPressed: () {
              final pos = ref.read(liveLocationProvider).value;
              if (pos != null) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PanoramaDownloadScreen(
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
          ),
          _NavIconButton(
            icon: Icons.view_in_ar,
            tooltip: 'AR Street View',
            onPressed: () => context.push('/ar'),
          ),
          _NavIconButton(
            icon: Icons.logout,
            tooltip: 'Logout',
            onPressed: () async => await authService.signOut(),
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
              onTap: (tapPosition, point) {
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
                showCreateBuildingDialog(context, ref, point);
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
        error: (err, stack) => Center(child: Text('Error getting location: $err')),
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
    return buildings.map((building) {
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
            showCollectionBottomSheet(context, ref, building);
          },
          child: Column(
            children: [
              if (building.collectedCount > 0 && building.collectedCount < building.totalUnits)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.bgCard,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.borderLight),
                    boxShadow: [
                      BoxShadow(color: Colors.black54, blurRadius: 4),
                    ],
                  ),
                  child: Text(
                    '${building.collectedCount}/${building.totalUnits}',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.gold,
                    ),
                  ),
                ),
              Icon(Icons.location_on, color: pinColor, size: 40),
            ],
          ),
        ),
      );
    }).toList();
  }

}

class _NavIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;

  const _NavIconButton({
    Key? key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: color ?? Colors.white),
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }
}
