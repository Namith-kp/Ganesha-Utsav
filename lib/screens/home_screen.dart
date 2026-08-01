import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../providers/auth_provider.dart';
import '../providers/map_provider.dart';
import '../models/building.dart';
import '../main.dart';
import 'street_view_screen.dart';
import '../utils/building_dialogs.dart';
import '../utils/add_tag_notifier.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final double? initialLat;
  final double? initialLng;
  final String? targetBuildingId;

  const HomeScreen({
    Key? key,
    this.initialLat,
    this.initialLng,
    this.targetBuildingId,
  }) : super(key: key);

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  String _selectedFilter = 'all';
  bool _hasZoomedToTarget = false;
  bool _hasCenteredOnUser = false;
  bool _isLocating = true;
  LatLng? _cachedCenter;
  bool _isPickingLocation = false;
  StreamSubscription<void>? _addTagSub;

  void _setPickingLocation(bool active) {
    if (_isPickingLocation != active) {
      setState(() => _isPickingLocation = active);
      HomeScreenAddTagNotifier.setPicking(active);
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchCachedLocation();
    _addTagSub = HomeScreenAddTagNotifier.stream.listen((_) {
      if (mounted) _setPickingLocation(true);
    });
  }

  @override
  void dispose() {
    _addTagSub?.cancel();
    HomeScreenAddTagNotifier.setPicking(false);
    super.dispose();
  }

  Future<void> _fetchCachedLocation() async {
    if (widget.initialLat != null) {
      if (mounted) setState(() => _isLocating = false);
      return;
    }
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null && mounted) {
        _cachedCenter = LatLng(pos.latitude, pos.longitude);
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isLocating = false;
      });
    }
  }

  void _animatedMapMove(LatLng destLocation, double destZoom) {
    final latTween = Tween<double>(
      begin: _mapController.camera.center.latitude,
      end: destLocation.latitude,
    );
    final lngTween = Tween<double>(
      begin: _mapController.camera.center.longitude,
      end: destLocation.longitude,
    );
    final zoomTween = Tween<double>(
      begin: _mapController.camera.zoom,
      end: destZoom,
    );

    final controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    final Animation<double> animation = CurvedAnimation(
      parent: controller,
      curve: Curves.fastOutSlowIn,
    );

    controller.addListener(() {
      _mapController.move(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoomTween.evaluate(animation),
      );
    });

    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        controller.dispose();
      }
    });

    controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    final buildingsAsync = ref.watch(buildingsProvider);
    final collectorAsync = ref.watch(collectorProfileProvider);
    final profile = collectorAsync.value;
    final canCreate = profile?.canCreate ?? false;
    final canSeeAllTags = profile?.canSeeAllTags ?? false;

    // Automatically snap to user's location on startup once GPS is acquired
    ref.listen<AsyncValue<Position?>>(liveLocationProvider, (previous, next) {
      if (!_hasCenteredOnUser && next.value != null && widget.initialLat == null) {
        _hasCenteredOnUser = true;
        _animatedMapMove(
          LatLng(next.value!.latitude, next.value!.longitude),
          18.0,
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xF50A0D14),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [AppColors.accent, AppColors.accentLight],
                ).createShader(bounds),
                child: Text(
                  'Ganesha Utsava',
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
      floatingActionButton: FloatingActionButton(
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
      body: Builder(
        builder: (context) {
          if (_isLocating) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            );
          }

          LatLng initialCenter = const LatLng(20.5937, 78.9629); // Center of India fallback
          if (_cachedCenter != null) {
            initialCenter = _cachedCenter!;
          } else {
            final buildings = buildingsAsync.value ?? [];
            if (buildings.isNotEmpty) {
              initialCenter = LatLng(buildings.first.lat, buildings.first.lng);
            }
          }

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
                  initialCenter:
                      (widget.initialLat != null && widget.initialLng != null)
                      ? LatLng(widget.initialLat!, widget.initialLng!)
                      : initialCenter,
                  initialZoom: widget.targetBuildingId != null ? 17.0 : 18.0,
                  onMapReady: () {
                    if (widget.targetBuildingId != null &&
                        !_hasZoomedToTarget) {
                      _hasZoomedToTarget = true;
                      Future.delayed(const Duration(milliseconds: 300), () {
                        if (mounted &&
                            widget.initialLat != null &&
                            widget.initialLng != null) {
                          _animatedMapMove(
                            LatLng(widget.initialLat!, widget.initialLng!),
                            19.5,
                          );
                        }
                      });
                    }
                  },
                  onTap: (tapPosition, point) {
                    // In pick mode, taps are ignored — user uses the Confirm button.
                    if (_isPickingLocation) return;
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
                        const SnackBar(
                          content: Text(
                            'You do not have permission to create tags.',
                          ),
                        ),
                      );
                    }
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}',
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
                      _buildFilterChip(
                        'Not Collected',
                        'red',
                        AppColors.crimson,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip('Pending', 'orange', AppColors.amber),
                      const SizedBox(width: 8),
                      _buildFilterChip('Completed', 'green', AppColors.green),
                    ],
                  ),
                ),
              ),
              // ── Uber-style pick-location overlay ──────────────────────────
              if (_isPickingLocation) ...[
                // Top instruction banner
                Positioned(
                  top: 60,
                  left: 16,
                  right: 16,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.bgCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                        boxShadow: const [
                          BoxShadow(blurRadius: 12, color: Colors.black54),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.touch_app_rounded,
                            color: AppColors.accent,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            HomeScreenAddTagNotifier.pendingData != null
                                ? 'Position pin for "${HomeScreenAddTagNotifier.pendingData!.name}"'
                                : 'Drag the map to position the pin',
                            style: GoogleFonts.plusJakartaSans(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Fixed center pin (Uber-style)
                // The pin tip (bottom of stem) must sit at screen center so
                // camera.center returns the precise coordinate the user aimed at.
                //
                // Layout math:
                //   head   = 44 px
                //   stem   = 14 px  → tip at 58 px from column top
                //   shadow =  5 px
                //   total  = 63 px  → column center at 31.5 px from top
                //   tip below column center = 58 - 31.5 = 26.5 px
                //   → shift the whole widget UP by 26 px so the tip lands at
                //     screen center (= camera.center).
                IgnorePointer(
                  child: Center(
                    child: Transform.translate(
                      // Move rendered widget up; layout box stays at center.
                      offset: const Offset(0, -26),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Pin head
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      AppColors.accent.withValues(alpha: 0.45),
                                  blurRadius: 16,
                                  spreadRadius: 4,
                                ),
                                const BoxShadow(
                                  color: Colors.black54,
                                  blurRadius: 8,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.add_location_alt_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          // Pin stem
                          Container(
                            width: 3,
                            height: 14,
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          // Ground shadow dot — its top edge is the precise point
                          Container(
                            width: 10,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.black38,
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Bottom action bar: Cancel + Confirm
                Positioned(
                  bottom: 24,
                  left: 16,
                  right: 16,
                  child: Row(
                    children: [
                      // Cancel
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _setPickingLocation(false),
                          icon: const Icon(LucideIcons.x, size: 16),
                          label: Text(
                            'Cancel',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textPrimary,
                            side: const BorderSide(color: AppColors.border),
                            backgroundColor: AppColors.bgCard,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Confirm
                      Expanded(
                        flex: 2,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.accent, AppColors.accentLight],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.accent.withValues(alpha: 0.4),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final pickedPoint = _mapController.camera.center;
                              final pending = HomeScreenAddTagNotifier.pendingData;
                              HomeScreenAddTagNotifier.cancelPicking();
                              _setPickingLocation(false);

                              if (pending != null) {
                                final authUser =
                                    ref.read(authStateProvider).value;
                                if (authUser == null) return;
                                final buildingService =
                                    ref.read(buildingServiceProvider);

                                try {
                                  if (pending.isApartment) {
                                    await buildingService
                                        .createMultiUnitBuilding(
                                      lat: pickedPoint.latitude,
                                      lng: pickedPoint.longitude,
                                      name: pending.name,
                                      unitLabels: List.generate(
                                        pending.unitsCount,
                                        (i) => 'House ${i + 1}',
                                      ),
                                      createdBy: authUser.uid,
                                    );
                                  } else {
                                    await buildingService
                                        .createSingleUnitBuilding(
                                      lat: pickedPoint.latitude,
                                      lng: pickedPoint.longitude,
                                      name: pending.name,
                                      type: 'house',
                                      createdBy: authUser.uid,
                                    );
                                  }
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Added "${pending.name}" at location!',
                                        ),
                                        backgroundColor: AppColors.green,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Error adding tag: $e'),
                                        backgroundColor: AppColors.crimson,
                                      ),
                                    );
                                  }
                                }
                              } else {
                                showCreateBuildingDialog(
                                  context,
                                  ref,
                                  pickedPoint,
                                );
                              }
                            },
                            icon: const Icon(
                              Icons.check_circle_outline_rounded,
                              size: 18,
                              color: Colors.white,
                            ),
                            label: Text(
                              'Confirm Location',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterChip(String label, String filterValue, Color color) {
    final isSelected = _selectedFilter == filterValue;
    return FilterChip(
      label: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          color: isSelected ? Colors.white : AppColors.textSecondary,
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      selected: isSelected,
      selectedColor: color,
      backgroundColor: AppColors.bgCard.withValues(alpha: 0.9),
      checkmarkColor: Colors.white,
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: isSelected ? color : AppColors.border,
          width: 1,
        ),
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
      if (_selectedFilter == 'green' &&
          building.collectedCount >= building.totalUnits)
        return true;
      if (_selectedFilter == 'orange' &&
          building.collectedCount > 0 &&
          building.collectedCount < building.totalUnits)
        return true;
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
        width: 72,
        height: 72,
        child: GestureDetector(
          onTap: () {
            _animatedMapMove(LatLng(building.lat, building.lng), 19.5);
            showCollectionBottomSheet(context, ref, building);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (building.collectedCount > 0 &&
                  building.collectedCount < building.totalUnits)
                Container(
                  constraints: const BoxConstraints(maxWidth: 56),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
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

          return state._buildMarkers(context, ref, buildings, canSeeAllTags);
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
                      boxShadow: const [
                        BoxShadow(blurRadius: 8, color: Colors.black54),
                      ],
                    ),
                    child: const Icon(
                      LucideIcons.user,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ],
        orElse: () => const <Marker>[],
      ),
    );
  }
}
