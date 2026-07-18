import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/auth_provider.dart';
import '../providers/map_provider.dart';
import '../models/building.dart';
import '../models/unit.dart';
import '../main.dart';
import 'street_view_screen.dart';
import 'panorama_download_screen.dart';
import '../utils/building_dialogs.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final MapController _mapController = MapController();
  bool _isPinningMode = false;

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
          if (_isPinningMode) ...[
            FloatingActionButton.extended(
              heroTag: 'confirmPinBtn',
              backgroundColor: Colors.green,
              icon: const Icon(Icons.check, color: Colors.white),
              label: const Text('Confirm Pin', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onPressed: () {
                final center = _mapController.camera.center;
                setState(() => _isPinningMode = false);
                showCreateBuildingDialog(context, ref, center);
              },
            ),
            const SizedBox(height: 16),
            FloatingActionButton.extended(
              heroTag: 'cancelPinBtn',
              backgroundColor: Colors.redAccent,
              icon: const Icon(Icons.close, color: Colors.white),
              label: const Text('Cancel', style: TextStyle(color: Colors.white)),
              onPressed: () {
                setState(() => _isPinningMode = false);
              },
            ),
          ] else ...[
            FloatingActionButton(
              heroTag: 'addPinBtn',
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              tooltip: 'Add Building at Crosshair',
              onPressed: () {
                setState(() => _isPinningMode = true);
              },
              child: const Icon(Icons.add_location_alt),
            ),
            const SizedBox(height: 16),
            FloatingActionButton(
              heroTag: 'streetViewBtn',
              backgroundColor: AppColors.bgCard,
              foregroundColor: AppColors.gold,
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
              child: const Icon(Icons.streetview),
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
          ),

          // Filter UI at the top of the map
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Consumer(
                builder: (context, ref, _) {
                  final filterStatus = ref.watch(filterStatusProvider);
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                      boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
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
          ),
          
          if (_isPinningMode)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 40.0), // Adjust so tip of icon is at center
                child: Icon(Icons.location_on, size: 40, color: Colors.orange),
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

  List<Marker> _buildMarkers(BuildContext context, WidgetRef ref, List<Building> buildings) {
    final filterStatus = ref.watch(filterStatusProvider);
    
    return buildings.where((building) {
      if (filterStatus == FilterStatus.pending && building.collectedCount > 0) return false;
      if (filterStatus == FilterStatus.partial && (building.collectedCount == 0 || building.collectedCount >= building.totalUnits)) return false;
      if (filterStatus == FilterStatus.completed && building.collectedCount < building.totalUnits) return false;
      return true;
    }).map((building) {
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

// ─────────────────────────────────────────────────────────────────────────────
// Nav icon button with hover-style active colour
// ─────────────────────────────────────────────────────────────────────────────
class _NavIconButton extends StatelessWidget {
  const _NavIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
  });
  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: color ?? AppColors.textSecondary, size: 22),
      tooltip: tooltip,
      onPressed: onPressed,
      splashColor: AppColors.gold.withOpacity(0.15),
      highlightColor: AppColors.gold.withOpacity(0.08),
    );
  }
}
