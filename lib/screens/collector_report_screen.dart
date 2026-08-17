import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/building.dart';
import '../models/unit.dart';
import '../utils/building_dialogs.dart';
import '../providers/map_provider.dart';
import '../main.dart';
import 'package:intl/intl.dart';

class CollectorReportScreen extends ConsumerStatefulWidget {
  final String collectorName;
  final String collectorId;
  final bool isViewer;

  const CollectorReportScreen({
    super.key,
    required this.collectorName,
    required this.collectorId,
    this.isViewer = false,
  });

  @override
  ConsumerState<CollectorReportScreen> createState() => _CollectorReportScreenState();
}

class _CollectorReportScreenState extends ConsumerState<CollectorReportScreen> {
  Future<List<Map<String, dynamic>>>? _collectionsFuture;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    _collectionsFuture = ref
        .read(buildingServiceProvider)
        .getDetailedCollections(filterCollectorId: widget.collectorId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _collectionsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Scaffold(
            backgroundColor: AppColors.bgBase,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final collections = snapshot.data ?? [];
        double totalCollected = 0.0;
        for (var item in collections) {
          final Unit unit = item['unit'];
          totalCollected += unit.amount;
        }

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text(
          '${widget.collectorName} Reports',
          style: GoogleFonts.plusJakartaSans(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Column(
        children: [
          if (!widget.isViewer)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                color: AppColors.accent.withValues(alpha: 0.15),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: AppColors.accent.withValues(alpha: 0.3),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Collected',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        '₹${totalCollected.toStringAsFixed(0)}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: collections.isEmpty
                ? Center(
                    child: Text(
                      'No collections yet.',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: collections.length,
                    itemBuilder: (context, index) {
                      final item = collections[index];
                      final Unit unit = item['unit'];
                      final Building building = item['building'];
                      final date = unit.collectedAt;

                      final dateStr = date != null
                          ? '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}'
                          : 'Unknown Date';
                      final timeStr = date != null
                          ? DateFormat('h:mm a').format(date.toLocal())
                          : '';

                      return Card(
                        color: AppColors.bgCard,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: AppColors.borderLight),
                        ),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: unit.photoBase64 != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.memory(
                                    base64Decode(unit.photoBase64!),
                                    width: 50,
                                    height: 50,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : const Icon(
                                  LucideIcons.imageOff,
                                  size: 40,
                                  color: AppColors.textMuted,
                                ),
                          title: Text(
                            '${building.name} - ${unit.unitLabel}',
                            style: GoogleFonts.plusJakartaSans(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Row(
                            children: [
                              Text(
                                '$dateStr $timeStr',
                                style: GoogleFonts.plusJakartaSans(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: unit.paymentMethod == 'UPI'
                                      ? Colors.purple.shade100
                                      : Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  unit.paymentMethod ?? 'Unknown',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
                                    color: unit.paymentMethod == 'UPI'
                                        ? Colors.purple.shade700
                                        : Colors.orange.shade700,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          trailing: Text(
                            '₹${unit.amount.toStringAsFixed(0)}',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: AppColors.green,
                            ),
                          ),
                          onTap: () async {
                            await showUnitAmountForm(
                              context,
                              ref,
                              building,
                              unit,
                              fromReports: true,
                            );
                            setState(() {
                              _loadData();
                            });
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
      },
    );
  }
}
