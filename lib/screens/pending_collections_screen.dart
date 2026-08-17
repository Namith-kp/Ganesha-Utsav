import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/building.dart';
import '../models/unit.dart';
import '../utils/building_dialogs.dart';
import '../providers/map_provider.dart';
import '../main.dart';
import 'street_view_screen.dart';

// ─── Pending Collections List Screen ─────────────────────────────────────────

class PendingCollectionsScreen extends ConsumerStatefulWidget {
  const PendingCollectionsScreen({super.key});

  @override
  ConsumerState<PendingCollectionsScreen> createState() =>
      _PendingCollectionsScreenState();
}

class _PendingCollectionsScreenState
    extends ConsumerState<PendingCollectionsScreen> {
  @override
  Widget build(BuildContext context) {
    final buildingService = ref.watch(buildingServiceProvider);

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text(
          'Pending Collections',
          style: GoogleFonts.plusJakartaSans(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          // Map view button
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: buildingService.streamPendingCollections(),
            builder: (context, snapshot) {
              final items = snapshot.data ?? [];
              return IconButton(
                icon: const Icon(LucideIcons.map, color: AppColors.textPrimary),
                tooltip: 'View on Map',
                onPressed: items.isEmpty
                    ? null
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PendingMapScreen(
                              pendingItems: items,
                            ),
                          ),
                        );
                      },
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: buildingService.streamPendingCollections(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error: ${snapshot.error}',
                style: GoogleFonts.plusJakartaSans(color: AppColors.crimson),
              ),
            );
          }

          final allPending = snapshot.data ?? [];
          // Filter to show only pending units with a non-zero expected amount
          final pendingWithAmount = allPending.where((item) {
            final Unit unit = item['unit'];
            return unit.amount > 0;
          }).toList();

          double totalPending = 0.0;
          for (var item in pendingWithAmount) {
            final Unit unit = item['unit'];
            totalPending += unit.amount;
          }

          return Column(
            children: [
              // Summary card
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Card(
                  color: AppColors.blue.withValues(alpha: 0.15),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: AppColors.blue.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total Pending Amount',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '₹${totalPending.toStringAsFixed(0)}',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: AppColors.blue,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${pendingWithAmount.length} house${pendingWithAmount.length == 1 ? '' : 's'}',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            // Quick map button in summary card
                            if (pendingWithAmount.isNotEmpty)
                              GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => PendingMapScreen(
                                        pendingItems: pendingWithAmount,
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  margin: const EdgeInsets.only(right: 10),
                                  decoration: BoxDecoration(
                                    color: AppColors.blue.withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    LucideIcons.map,
                                    color: AppColors.blue,
                                    size: 22,
                                  ),
                                ),
                              ),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.blue.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                LucideIcons.clock,
                                color: AppColors.blue,
                                size: 28,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: pendingWithAmount.isEmpty
                    ? Center(
                        child: Text(
                          'No pending collections found.',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppColors.textSecondary,
                            fontSize: 16,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: pendingWithAmount.length,
                        itemBuilder: (context, index) {
                          final item = pendingWithAmount[index];
                          final Unit unit = item['unit'];
                          final Building building = item['building'];

                          return Card(
                            color: AppColors.bgCard,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: const BorderSide(color: AppColors.border),
                            ),
                            margin: const EdgeInsets.only(bottom: 12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                showCollectionBottomSheet(
                                    context, ref, building);
                              },
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Title row
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            building.name,
                                            style: GoogleFonts.plusJakartaSans(
                                              color: AppColors.textPrimary,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '₹${unit.amount.toStringAsFixed(0)}',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 18,
                                            color: AppColors.blue,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    // Unit label
                                    Text(
                                      'Unit: ${unit.unitLabel}',
                                      style: GoogleFonts.plusJakartaSans(
                                        color: AppColors.textSecondary,
                                        fontSize: 13,
                                      ),
                                    ),
                                    // Phone
                                    if (unit.phoneNumber != null &&
                                        unit.phoneNumber!.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Icon(
                                            LucideIcons.phone,
                                            size: 13,
                                            color: AppColors.textSecondary,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            unit.phoneNumber!,
                                            style: GoogleFonts.plusJakartaSans(
                                              color: AppColors.textSecondary,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    const SizedBox(height: 10),
                                    // Action buttons row
                                    Row(
                                      children: [
                                        // 2D Map button
                                        _ActionChip(
                                          icon: LucideIcons.map,
                                          label: 'Map',
                                          color: AppColors.green,
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    _SingleBuildingMapScreen(
                                                  building: building,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                        const SizedBox(width: 8),
                                        // Street View button
                                        _ActionChip(
                                          icon: LucideIcons.eye,
                                          label: 'Street View',
                                          color: AppColors.amber,
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => StreetViewScreen(
                                                  lat: building.lat,
                                                  lon: building.lng,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Action Chip Widget ───────────────────────────────────────────────────────

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── All Pending Locations on Map ─────────────────────────────────────────────

class PendingMapScreen extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> pendingItems;

  const PendingMapScreen({super.key, required this.pendingItems});

  @override
  ConsumerState<PendingMapScreen> createState() => _PendingMapScreenState();
}

class _PendingMapScreenState extends ConsumerState<PendingMapScreen> {
  final MapController _mapController = MapController();
  Building? _selectedBuilding;

  LatLng get _center {
    if (widget.pendingItems.isEmpty) return const LatLng(20.5937, 78.9629);
    double latSum = 0, lngSum = 0;
    for (var item in widget.pendingItems) {
      final Building b = item['building'];
      latSum += b.lat;
      lngSum += b.lng;
    }
    return LatLng(
      latSum / widget.pendingItems.length,
      lngSum / widget.pendingItems.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text(
          'Pending on Map',
          style: GoogleFonts.plusJakartaSans(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.blue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${widget.pendingItems.length} pending',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppColors.blue,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              backgroundColor: AppColors.bgBase,
              initialCenter: _center,
              initialZoom: 17.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onTap: (tapPos, point) {
                setState(() => _selectedBuilding = null);
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}',
                userAgentPackageName: 'com.Dcross.ganeshtracker',
                keepBuffer: 4,
                panBuffer: 1,
                tileDisplay: const TileDisplay.instantaneous(),
              ),
              MarkerLayer(
                markers: widget.pendingItems.map((item) {
                  final Building building = item['building'];
                  final Unit unit = item['unit'];
                  final bool isSelected =
                      _selectedBuilding?.id == building.id;
                  return Marker(
                    point: LatLng(building.lat, building.lng),
                    width: isSelected ? 200 : 44,
                    height: isSelected ? 58 : 44,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedBuilding =
                              isSelected ? null : building;
                        });
                        _mapController.move(
                          LatLng(building.lat, building.lng),
                          18.5,
                        );
                      },
                      child: isSelected
                          ? _SelectedPendingMarker(
                              building: building,
                              unit: unit,
                            )
                          : _PendingMarkerDot(amount: unit.amount),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          // Bottom sheet for selected building actions
          if (_selectedBuilding != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _PendingLocationCard(
                building: _selectedBuilding!,
                pendingItems: widget.pendingItems,
                onDismiss: () =>
                    setState(() => _selectedBuilding = null),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Pending Marker Dot ───────────────────────────────────────────────────────

class _PendingMarkerDot extends StatelessWidget {
  final double amount;
  const _PendingMarkerDot({required this.amount});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.9),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 3))
        ],
      ),
      child: Center(
        child: Text(
          '₹${amount >= 1000 ? '${(amount / 1000).toStringAsFixed(0)}K' : amount.toStringAsFixed(0)}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ─── Selected Pending Marker (expanded callout) ───────────────────────────────

class _SelectedPendingMarker extends StatelessWidget {
  final Building building;
  final Unit unit;
  const _SelectedPendingMarker(
      {required this.building, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.amber, width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 8,
                offset: Offset(0, 3),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                building.name,
                style: GoogleFonts.plusJakartaSans(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '₹${unit.amount.toStringAsFixed(0)} pending',
                style: GoogleFonts.plusJakartaSans(
                  color: AppColors.amber,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        // Pin triangle
        CustomPaint(
          size: const Size(14, 8),
          painter: _TrianglePainter(color: AppColors.bgCard),
        ),
      ],
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final Color color;
  const _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => old.color != color;
}

// ─── Bottom Card for Selected Pending Location ────────────────────────────────

class _PendingLocationCard extends StatelessWidget {
  final Building building;
  final List<Map<String, dynamic>> pendingItems;
  final VoidCallback onDismiss;

  const _PendingLocationCard({
    required this.building,
    required this.pendingItems,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    // Get units for this building
    final units = pendingItems
        .where((item) {
          final Building b = item['building'];
          return b.id == building.id;
        })
        .map((item) => item['unit'] as Unit)
        .toList();

    final double totalForBuilding =
        units.fold(0.0, (sum, u) => sum + u.amount);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: AppColors.border),
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            building.name,
                            style: GoogleFonts.plusJakartaSans(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${units.length} unit${units.length == 1 ? '' : 's'} • ₹${totalForBuilding.toStringAsFixed(0)} pending',
                            style: GoogleFonts.plusJakartaSans(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        LucideIcons.x,
                        color: AppColors.textMuted,
                        size: 20,
                      ),
                      onPressed: onDismiss,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _LocationActionButton(
                        icon: LucideIcons.mapPin,
                        label: '2D Map',
                        color: AppColors.green,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => _SingleBuildingMapScreen(
                                building: building,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _LocationActionButton(
                        icon: LucideIcons.eye,
                        label: 'Street View',
                        color: AppColors.amber,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => StreetViewScreen(
                                lat: building.lat,
                                lon: building.lng,
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
        ],
      ),
    );
  }
}

// ─── Location Action Button ───────────────────────────────────────────────────

class _LocationActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _LocationActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Single Building Focused Map ──────────────────────────────────────────────

class _SingleBuildingMapScreen extends StatelessWidget {
  final Building building;
  const _SingleBuildingMapScreen({required this.building});

  @override
  Widget build(BuildContext context) {
    final pos = LatLng(building.lat, building.lng);
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text(
          building.name,
          style: GoogleFonts.plusJakartaSans(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          // Open in Street View from here too
          IconButton(
            icon: const Icon(LucideIcons.eye, color: AppColors.textPrimary),
            tooltip: 'Street View',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      StreetViewScreen(lat: building.lat, lon: building.lng),
                ),
              );
            },
          ),
        ],
      ),
      body: FlutterMap(
        options: MapOptions(
          backgroundColor: AppColors.bgBase,
          initialCenter: pos,
          initialZoom: 19.5,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
          ),
          onTap: (_, point) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StreetViewScreen(
                  lat: point.latitude,
                  lon: point.longitude,
                ),
              ),
            );
          },
        ),
        children: [
          TileLayer(
            urlTemplate:
                'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}',
            userAgentPackageName: 'com.Dcross.ganeshtracker',
            keepBuffer: 4,
            panBuffer: 1,
            tileDisplay: const TileDisplay.instantaneous(),
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: pos,
                width: 60,
                height: 60,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black54,
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      )
                    ],
                  ),
                  child: const Icon(
                    LucideIcons.clock,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
