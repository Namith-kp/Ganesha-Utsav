import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../providers/auth_provider.dart';
import '../providers/map_provider.dart';
import '../models/building.dart';
import '../models/unit.dart';
import '../main.dart';
import 'street_view_screen.dart';

import '../utils/building_dialogs.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final double? initialLat;
  final double? initialLng;
  final String? targetBuildingId;

  const HomeScreen({Key? key, this.initialLat, this.initialLng, this.targetBuildingId}) : super(key: key);

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  String _selectedFilter = 'all';
  bool _hasZoomedToTarget = false;

  void _animatedMapMove(LatLng destLocation, double destZoom) {
    final latTween = Tween<double>(begin: _mapController.camera.center.latitude, end: destLocation.latitude);
    final lngTween = Tween<double>(begin: _mapController.camera.center.longitude, end: destLocation.longitude);
    final zoomTween = Tween<double>(begin: _mapController.camera.zoom, end: destZoom);

    final controller = AnimationController(duration: const Duration(milliseconds: 600), vsync: this);
    final Animation<double> animation = CurvedAnimation(parent: controller, curve: Curves.fastOutSlowIn);

    controller.addListener(() {
      _mapController.move(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoomTween.evaluate(animation),
      );
    });

    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
        controller.dispose();
      }
    });

    controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    final authService = ref.read(authServiceProvider);
    final locationAsync = ref.watch(currentLocationProvider);
    final collectorAsync = ref.watch(collectorProfileProvider);
    final profile = collectorAsync.value;
    final canCreate = profile?.canCreate ?? false;
    final canSeeAllTags = profile?.canSeeAllTags ?? false;

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
            Flexible(
              child: ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [AppColors.accent, AppColors.accentLight],
                ).createShader(bounds),
                child: Text(
                  'Ganesha Tracker',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    letterSpacing: -0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
        actions: [
          // Nav bar handles other screens now
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'myLocationBtn',
            backgroundColor: AppColors.bgCard,
            foregroundColor: AppColors.textPrimary,
            onPressed: () {
              final pos = ref.read(liveLocationProvider).value;
              if (pos != null) {
                double targetZoom = _mapController.camera.zoom;
                if (targetZoom < 18.0) {
                  targetZoom = 18.0;
                } else if (targetZoom < 19.0) {
                  targetZoom += 0.5;
                }
                _animatedMapMove(
                  LatLng(pos.latitude, pos.longitude),
                  targetZoom,
                );
              }
            },
            child: const Icon(LucideIcons.navigation),
          ),
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
                  backgroundColor: AppColors.bgBase,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    enableMultiFingerGestureRace: true,
                    pinchZoomThreshold: 0.1,
                    pinchMoveThreshold: 8,
                  ),
                  initialCenter: (widget.initialLat != null && widget.initialLng != null)
                      ? LatLng(widget.initialLat!, widget.initialLng!)
                      : initialCenter,
                  initialZoom: widget.targetBuildingId != null ? 17.0 : 18.0,
                  onMapReady: () {
                    if (widget.targetBuildingId != null && !_hasZoomedToTarget) {
                      _hasZoomedToTarget = true;
                      Future.delayed(const Duration(milliseconds: 300), () {
                        if (mounted && widget.initialLat != null && widget.initialLng != null) {
                          _animatedMapMove(
                            LatLng(widget.initialLat!, widget.initialLng!),
                            19.5,
                          );
                        }
                      });
                    }
                  },
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
                    if (canCreate) {
                      showCreateBuildingDialog(context, ref, point);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('You do not have permission to create tags.')),
                      );
                    }
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}',
                    userAgentPackageName: 'com.Dcross.ganeshtracker',
                    // Keep nearby tiles in memory and skip per-tile fade
                    // animations so panning and zooming stay responsive.
                    keepBuffer: 4,
                    panBuffer: 1,
                    tileDisplay: const TileDisplay.instantaneous(),
                  ),
                  _BuildingsMarkerLayer(
                    selectedFilter: _selectedFilter,
                    targetBuildingId: widget.targetBuildingId,
                    canSeeAllTags: canSeeAllTags,
                  ),
                  const _LiveLocationMarkerLayer(),
                ],
              ),
              Positioned(
                top: 10,
                left: 10,
                right: 10,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('All', 'all', AppColors.accent),
                      const SizedBox(width: 8),
                      _buildFilterChip('Not Collected', 'red', AppColors.crimson),
                      const SizedBox(width: 8),
                      _buildFilterChip('Pending', 'orange', AppColors.amber),
                      const SizedBox(width: 8),
                      _buildFilterChip('Completed', 'green', AppColors.green),
                    ],
                  ),
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
      label: Text(label, style: GoogleFonts.plusJakartaSans(
        color: isSelected ? Colors.white : AppColors.textSecondary, 
        fontSize: 13,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
      )),
      selected: isSelected,
      selectedColor: color,
      backgroundColor: AppColors.bgCard.withOpacity(0.9),
      checkmarkColor: Colors.white,
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: isSelected ? color : AppColors.border, width: 1),
      ),
      onSelected: (bool selected) {
        setState(() {
          _selectedFilter = filterValue;
        });
      },
    );
  }

  List<Marker> _buildMarkers(
    BuildContext context,
    WidgetRef ref,
    List<Building> buildings,
    bool canSeeAllTags,
  ) {

    var filteredBuildings = buildings.where((building) {
      if (widget.targetBuildingId != null) {
        return building.id == widget.targetBuildingId;
      }
      if (!canSeeAllTags && building.collectedCount == 0) return false;
      
      if (_selectedFilter == 'all') return true;
      if (_selectedFilter == 'red' && building.collectedCount == 0) return true;
      if (_selectedFilter == 'green' && building.collectedCount >= building.totalUnits) return true;
      if (_selectedFilter == 'orange' && building.collectedCount > 0 && building.collectedCount < building.totalUnits) return true;
      return false;
    }).toList();

    return filteredBuildings.map((building) {
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
        width: 44,
        height: 44,
        child: GestureDetector(
          onTap: () {
            _animatedMapMove(LatLng(building.lat, building.lng), 19.5);
            showCollectionBottomSheet(context, ref, building);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              const SizedBox(height: 3),
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: pinColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 4),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

}

class _BuildingsMarkerLayer extends ConsumerWidget {
  final String selectedFilter;
  final String? targetBuildingId;
  final bool canSeeAllTags;

  const _BuildingsMarkerLayer({
    required this.selectedFilter,
    required this.targetBuildingId,
    required this.canSeeAllTags,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buildingsAsync = ref.watch(buildingsProvider);

    return MarkerLayer(
      markers: buildingsAsync.when(
        data: (buildings) {
          final state = context.findAncestorStateOfType<_HomeScreenState>();
          if (state == null) return const <Marker>[];

          return state._buildMarkers(
            context,
            ref,
            buildings,
            canSeeAllTags,
          );
        },
        loading: () => const <Marker>[],
        error: (err, stack) => const <Marker>[],
      ),
    );
  }
}

class _LiveLocationMarkerLayer extends ConsumerWidget {
  const _LiveLocationMarkerLayer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveLocationAsync = ref.watch(liveLocationProvider);

    return MarkerLayer(
      markers: liveLocationAsync.maybeWhen(
        data: (pos) => pos == null
            ? const <Marker>[]
            : [
                Marker(
                  point: LatLng(pos.latitude, pos.longitude),
                  width: 32,
                  height: 32,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.bgBase, width: 3),
                      boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black54)],
                    ),
                    child: const Icon(LucideIcons.user, color: Colors.white, size: 18),
                  ),
                ),
              ],
        orElse: () => const <Marker>[],
      ),
    );
  }
}
