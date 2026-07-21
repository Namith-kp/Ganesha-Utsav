import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/building.dart';
import '../models/unit.dart';
import '../providers/auth_provider.dart';
import '../providers/map_provider.dart';
import '../main.dart';
import '../screens/home_screen.dart';
import '../screens/street_view_screen.dart';
void _showAddUnitDialog(BuildContext context, WidgetRef ref, Building building) {
  final controller = TextEditingController();
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: AppColors.borderLight)),
      title: Text('Add New Unit', style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
      content: TextField(
        controller: controller,
        style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary),
        decoration: InputDecoration(
          labelText: 'Unit Name (e.g. Unit 3)',
          labelStyle: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.borderLight), borderRadius: BorderRadius.circular(8)),
          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.accent), borderRadius: BorderRadius.circular(8)),
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text('CANCEL', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          onPressed: () async {
            if (controller.text.trim().isNotEmpty) {
              final buildingService = ref.read(buildingServiceProvider);
              await buildingService.addUnitToBuilding(
                building.id,
                controller.text.trim(),
              );
              if (ctx.mounted) Navigator.pop(ctx);
            }
          },
          child: Text('ADD', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );
}

Future<void> showCollectionBottomSheet(BuildContext context, WidgetRef ref, Building building) async {
  final buildingService = ref.read(buildingServiceProvider);
  
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.bgBase,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) {
      return StreamBuilder<List<Unit>>(
        stream: buildingService.streamUnits(building.id),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final units = snapshot.data!;
          if (units.isEmpty) return const Center(child: Text('No units found.'));
          
          final profile = ref.read(collectorProfileProvider).value;
          final isAdmin = profile?.isAdmin ?? false;
          final canCreate = profile?.canCreate ?? false;

          if (building.totalUnits > 1) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.6,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('${building.name} - Units', style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                          ),
                          if (isAdmin)
                            IconButton(
                              icon: const Icon(LucideIcons.plusCircle, color: AppColors.accent),
                              tooltip: 'Add Unit',
                              onPressed: () => _showAddUnitDialog(context, ref, building),
                            ),
                          if (isAdmin)
                            IconButton(
                              icon: const Icon(LucideIcons.trash2, color: AppColors.crimson),
                              tooltip: 'Delete Building',
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: AppColors.bgCard,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: AppColors.borderLight)),
                                    title: Text('Delete Building?', style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                                    content: Text('This will delete the building and all its units forever.', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary)),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('CANCEL', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary))),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.crimson, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: Text('DELETE', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await buildingService.deleteBuilding(building.id);
                                  if (context.mounted) Navigator.pop(context);
                                }
                              },
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: units.length,
                        itemBuilder: (context, index) {
                          final unit = units[index];
                          final isCollected = unit.status == 'collected';
                          return ListTile(
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(unit.unitLabel,
                                    style: GoogleFonts.inter(color: AppColors.textPrimary)),
                                ),
                                if (isAdmin)
                                  IconButton(
                                    icon: const Icon(LucideIcons.edit2, size: 16, color: AppColors.textSecondary),
                                    onPressed: () {
                                      final unitController = TextEditingController(text: unit.unitLabel);
                                      final buildingController = TextEditingController(text: building.name);
                                      showDialog(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          backgroundColor: AppColors.bgCard,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: AppColors.borderLight)),
                                          title: Text('Rename Details', style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                                          content: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              TextField(
                                                controller: buildingController,
                                                style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary),
                                                decoration: InputDecoration(
                                                  labelText: 'Building Name',
                                                  labelStyle: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary),
                                                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.borderLight), borderRadius: BorderRadius.circular(8)),
                                                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.accent), borderRadius: BorderRadius.circular(8)),
                                                ),
                                              ),
                                              const SizedBox(height: 16),
                                              TextField(
                                                controller: unitController,
                                                style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary),
                                                decoration: InputDecoration(
                                                  labelText: 'Unit Name',
                                                  labelStyle: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary),
                                                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.borderLight), borderRadius: BorderRadius.circular(8)),
                                                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.accent), borderRadius: BorderRadius.circular(8)),
                                                ),
                                              ),
                                            ],
                                          ),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('CANCEL', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary))),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                                              onPressed: () async {
                                                final buildingService = ref.read(buildingServiceProvider);
                                                if (buildingController.text.trim().isNotEmpty && buildingController.text.trim() != building.name) {
                                                  await buildingService.updateBuildingName(building.id, buildingController.text.trim());
                                                }
                                                if (unitController.text.trim().isNotEmpty && unitController.text.trim() != unit.unitLabel) {
                                                  await buildingService.renameUnit(
                                                    buildingId: building.id,
                                                    unitId: unit.id,
                                                    newName: unitController.text.trim(),
                                                  );
                                                }
                                                if (ctx.mounted) Navigator.pop(ctx);
                                              },
                                              child: const Text('SAVE'),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                            trailing: Chip(
                              label: Text(
                                isCollected ? 'Collected' : 'Pending',
                                style: GoogleFonts.inter(
                                  color: isCollected ? Colors.white : AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              backgroundColor: isCollected
                                  ? AppColors.greenPin.withValues(alpha: 0.2)
                                  : AppColors.bgGlass,
                              side: BorderSide(
                                color: isCollected ? AppColors.greenPin : AppColors.borderLight,
                              ),
                            ),
                            onTap: () {
                              if (canCreate || isCollected) {
                                showUnitAmountForm(context, ref, building, unit);
                              }
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (isAdmin)
                        IconButton(
                          icon: const Icon(LucideIcons.plusCircle, color: AppColors.accent),
                          tooltip: 'Add Unit',
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showAddUnitDialog(context, ref, building);
                          },
                        ),
                      if (isAdmin)
                        IconButton(
                          icon: const Icon(LucideIcons.trash2, color: AppColors.crimson),
                          tooltip: 'Delete Building',
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx2) => AlertDialog(
                                backgroundColor: AppColors.bgCard,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: AppColors.borderLight)),
                                title: Text('Delete Building?', style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                                content: Text('This will delete the building and all its units forever.', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary)),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx2, false), child: Text('CANCEL', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary))),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.crimson, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                                    onPressed: () => Navigator.pop(ctx2, true),
                                    child: Text('DELETE', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await buildingService.deleteBuilding(building.id);
                              if (context.mounted) Navigator.pop(context);
                            }
                          },
                        ),
                    ],
                  ),
                  if (canCreate || unit.status == 'collected')
                    _AmountFormWidget(building: building, unit: unit),
                ],
              ),
            );
          }
        },
      );
    },
  );
}

Future<void> showUnitAmountForm(BuildContext context, WidgetRef ref, Building building, Unit unit, {bool fromReports = false}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.bgBase,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: _AmountFormWidget(building: building, unit: unit, fromReports: fromReports),
        ),
      );
    },
  );
}

class _AmountFormWidget extends ConsumerStatefulWidget {
  final Building building;
  final Unit unit;
  final bool fromReports;

  const _AmountFormWidget({
    required this.building,
    required this.unit,
    this.fromReports = false,
  });

  @override
  ConsumerState<_AmountFormWidget> createState() => _AmountFormWidgetState();
}

class _AmountFormWidgetState extends ConsumerState<_AmountFormWidget> {
  bool isEditing = false;
  late TextEditingController amountController;
  late TextEditingController donationItemController;
  late TextEditingController phoneController;
  bool isSubmitting = false;
  String? photoBase64;
  String? paymentMethod;

  @override
  void initState() {
    super.initState();
    final isAlreadyCollected = widget.unit.status == 'collected';
    amountController = TextEditingController(text: isAlreadyCollected ? widget.unit.amount.toString() : '');
    donationItemController = TextEditingController(text: widget.unit.donationItem ?? '');
    phoneController = TextEditingController(text: widget.unit.phoneNumber ?? '');
    amountController.addListener(_onFieldChanged);
    donationItemController.addListener(_onFieldChanged);
    phoneController.addListener(_onFieldChanged);
    photoBase64 = widget.unit.photoBase64;
    paymentMethod = widget.unit.paymentMethod;
  }

  void _onFieldChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    amountController.removeListener(_onFieldChanged);
    donationItemController.removeListener(_onFieldChanged);
    phoneController.removeListener(_onFieldChanged);
    amountController.dispose();
    donationItemController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  bool get _isSubmitValid {
    if (isSubmitting || photoBase64 == null) return false;
    final amount = double.tryParse(amountController.text) ?? 0.0;
    final donation = donationItemController.text.trim();
    
    // Require payment method if they entered an amount
    if (amount > 0 && paymentMethod == null) return false;
    
    // Require either amount > 0 OR a donation item (unless resetting)
    if (amount <= 0 && donation.isEmpty && widget.unit.status != 'collected') return false;
    
    return true;
  }

  void showZoomableImage(BuildContext ctx, String base64String) {
    showDialog(
      context: ctx,
      builder: (c) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(10),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4,
              child: Image.memory(base64Decode(base64String)),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.of(c).pop(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.read(collectorProfileProvider).value;
    final isAdmin = profile?.isAdmin ?? false;
    final canCreate = profile?.canCreate ?? false;
    final isAlreadyCollected = widget.unit.status == 'collected';

    if (isAlreadyCollected && !isEditing) {
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text('${widget.building.name} - ${widget.unit.unitLabel}', style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                ),
                if (isAdmin)
                  IconButton(
                    icon: const Icon(LucideIcons.edit2, size: 20, color: AppColors.textSecondary),
                    onPressed: () {
                      final unitController = TextEditingController(text: widget.unit.unitLabel);
                      final buildingController = TextEditingController(text: widget.building.name);
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: AppColors.bgCard,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: AppColors.borderLight)),
                          title: Text('Rename Details', style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextField(
                                controller: buildingController,
                                style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary),
                                decoration: InputDecoration(
                                  labelText: 'Building Name',
                                  labelStyle: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary),
                                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.borderLight), borderRadius: BorderRadius.circular(8)),
                                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.accent), borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: unitController,
                                style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary),
                                decoration: InputDecoration(
                                  labelText: 'Unit Name',
                                  labelStyle: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary),
                                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.borderLight), borderRadius: BorderRadius.circular(8)),
                                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.accent), borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ],
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary))),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                              onPressed: () async {
                                final buildingService = ref.read(buildingServiceProvider);
                                if (buildingController.text.trim().isNotEmpty && buildingController.text.trim() != widget.building.name) {
                                  await buildingService.updateBuildingName(widget.building.id, buildingController.text.trim());
                                }
                                if (unitController.text.trim().isNotEmpty && unitController.text.trim() != widget.unit.unitLabel) {
                                  await buildingService.renameUnit(
                                    buildingId: widget.building.id,
                                    unitId: widget.unit.id,
                                    newName: unitController.text.trim(),
                                  );
                                }
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (context.mounted) Navigator.pop(context);
                              },
                              child: Text('Save', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (widget.unit.photoBase64 != null) ...[
              GestureDetector(
                onTap: () => showZoomableImage(context, widget.unit.photoBase64!),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    base64Decode(widget.unit.photoBase64!),
                    height: 150,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            const Icon(LucideIcons.checkCircle2, color: AppColors.greenPin, size: 64),
            const SizedBox(height: 16),
            Text('₹${widget.unit.amount}', style: GoogleFonts.plusJakartaSans(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            Builder(
              builder: (context) {
                final paymentMethod = widget.unit.paymentMethod ?? 'Cash';
                final isUpi = paymentMethod == 'UPI';
                final color = isUpi ? AppColors.purple : AppColors.amber;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: color.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(isUpi ? LucideIcons.smartphone : LucideIcons.banknote, size: 16, color: color),
                      const SizedBox(width: 8),
                      Text(paymentMethod, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
                    ],
                  ),
                );
              }
            ),
            if (widget.unit.donationItem != null && widget.unit.donationItem!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.gift, size: 16, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Flexible(child: Text('Donated: ${widget.unit.donationItem!}', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.accent), textAlign: TextAlign.center)),
                  ],
                ),
              ),
            ],
            if (widget.unit.phoneNumber != null && widget.unit.phoneNumber!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.greenPin.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.greenPin.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.phone, size: 16, color: AppColors.greenPin),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Phone: ${widget.unit.phoneNumber!}',
                        style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.greenPin),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (widget.unit.collectedBy != null && widget.unit.collectedBy!.isNotEmpty) ...[
              const SizedBox(height: 12),
              FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('collectors').doc(widget.unit.collectedBy).get(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || !snapshot.data!.exists) {
                    return Text('Collected By: Unknown', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 14));
                  }
                  final collectorData = snapshot.data!.data() as Map<String, dynamic>;
                  final collectorName = collectorData['name'] ?? 'Unknown';
                  return Text('Collected by $collectorName', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 14));
                }
              ),
            ],
            if (widget.unit.collectedAt != null) ...[
              const SizedBox(height: 4),
              Text('${widget.unit.collectedAt!.toLocal().toString().split(' ')[0]} at ${widget.unit.collectedAt!.toLocal().toString().split(' ')[1].split('.')[0]}', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 14)),
            ],
            // Show last edited info if the unit has been corrected
            if (widget.unit.originalAmount != null) ...[
              const SizedBox(height: 12),
              FutureBuilder<QuerySnapshot>(
                future: FirebaseFirestore.instance
                    .collection('corrections')
                    .where('unitId', isEqualTo: widget.unit.id)
                    .orderBy('timestamp', descending: true)
                    .limit(1)
                    .get(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const SizedBox.shrink();
                  final corrData = snapshot.data!.docs.first.data() as Map<String, dynamic>;
                  final editorName = corrData['correctedByName'] as String? ?? 'Admin';
                  final double oldAmt = (corrData['oldAmount'] as num?)?.toDouble() ?? 0.0;
                  final double newAmt = (corrData['newAmount'] as num?)?.toDouble() ?? 0.0;
                  final DateTime? editTime = (corrData['timestamp'] as Timestamp?)?.toDate();
                  final editTimeStr = editTime != null
                      ? '${editTime.toLocal().toString().split(' ')[0]} at ${editTime.toLocal().toString().split(' ')[1].split('.')[0]}'
                      : '';
                  return Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(LucideIcons.pencil, size: 13, color: Colors.amber),
                            const SizedBox(width: 6),
                            Text('Edited by $editorName', style: GoogleFonts.plusJakartaSans(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('₹${oldAmt.toStringAsFixed(0)} → ₹${newAmt.toStringAsFixed(0)}', style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 12)),
                        if (editTimeStr.isNotEmpty)
                          Text(editTimeStr, style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 11)),
                      ],
                    ),
                  );
                },
              ),
            ],
            const SizedBox(height: 16),
            if (widget.fromReports) ...[
              Row(
                children: [
                  // 2D Map Button
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => HomeScreen(
                              initialLat: widget.building.lat,
                              initialLng: widget.building.lng,
                              targetBuildingId: widget.building.id,
                            )
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.accent.withValues(alpha: 0.18),
                              AppColors.accentLight.withValues(alpha: 0.08),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.accent.withValues(alpha: 0.55),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.accent.withValues(alpha: 0.12),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(LucideIcons.map, color: AppColors.accent, size: 17),
                            const SizedBox(width: 8),
                            Text(
                              '2D Map',
                              style: GoogleFonts.plusJakartaSans(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Street View Button
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => StreetViewScreen(
                              lat: widget.building.lat,
                              lon: widget.building.lng,
                            )
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.purple.withValues(alpha: 0.18),
                              const Color(0xFF7B5EA7).withValues(alpha: 0.08),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.purple.withValues(alpha: 0.55),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.purple.withValues(alpha: 0.12),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(LucideIcons.image, color: AppColors.purple, size: 17),
                            const SizedBox(width: 8),
                            Text(
                              'Street View',
                              style: GoogleFonts.plusJakartaSans(
                                color: AppColors.purple,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            const SizedBox(height: 8),
            if (!isAdmin)
              Text('Only admins can edit collected units.', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary))
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(LucideIcons.edit2, color: AppColors.accent, size: 18),
                      label: Text('Edit', style: GoogleFonts.plusJakartaSans(color: AppColors.accent, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(color: AppColors.accent.withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => setState(() => isEditing = true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(LucideIcons.rotateCcw, color: AppColors.amber, size: 18),
                      label: Text('Reset', style: GoogleFonts.plusJakartaSans(color: AppColors.amber, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(color: AppColors.amber.withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: AppColors.bgCard,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: AppColors.borderLight)),
                          title: Text('Reset Collection?', style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                          content: Text('This will reset the amount to 0 and mark the unit as pending.', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary)),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary))),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.amber, 
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              ),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text('Reset', style: GoogleFonts.plusJakartaSans(color: Colors.black, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        final buildingService = ref.read(buildingServiceProvider);
                        await buildingService.resetUnitCollection(
                          buildingId: widget.building.id,
                          unitId: widget.unit.id,
                          previousAmount: widget.unit.amount,
                        );
                        if (context.mounted) Navigator.pop(context);
                      }
                    },
                  ),
                ),
              ],
              ),
          ],
        ),
      );
    }
    
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Text('Collect for: ${widget.building.name} - ${widget.unit.unitLabel}', style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              if (isAdmin)
                IconButton(
                  icon: const Icon(LucideIcons.edit2, size: 20, color: AppColors.textSecondary),
                  onPressed: () {
                    final unitController = TextEditingController(text: widget.unit.unitLabel);
                    final buildingController = TextEditingController(text: widget.building.name);
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: AppColors.bgCard,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: AppColors.borderLight)),
                        title: Text('Rename Details', style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              controller: buildingController,
                              style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary),
                              decoration: InputDecoration(
                                labelText: 'Building Name',
                                labelStyle: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary),
                                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.borderLight), borderRadius: BorderRadius.circular(8)),
                                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.accent), borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: unitController,
                              style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary),
                              decoration: InputDecoration(
                                labelText: 'Unit Name',
                                labelStyle: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary),
                                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.borderLight), borderRadius: BorderRadius.circular(8)),
                                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.accent), borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('CANCEL', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary))),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                            onPressed: () async {
                              final buildingService = ref.read(buildingServiceProvider);
                              if (buildingController.text.trim().isNotEmpty && buildingController.text.trim() != widget.building.name) {
                                await buildingService.updateBuildingName(widget.building.id, buildingController.text.trim());
                              }
                              if (unitController.text.trim().isNotEmpty && unitController.text.trim() != widget.unit.unitLabel) {
                                await buildingService.renameUnit(
                                  buildingId: widget.building.id,
                                  unitId: widget.unit.id,
                                  newName: unitController.text.trim(),
                                );
                              }
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (context.mounted) Navigator.pop(context);
                            },
                            child: Text('SAVE', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (!canCreate) ...[
            const Icon(LucideIcons.clock, size: 64, color: AppColors.amber),
            const SizedBox(height: 16),
            Text('Pending Collection', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Text('You do not have permission to collect funds.', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 14)),
          ] else ...[
          if (photoBase64 != null) ...[
            Stack(
              alignment: Alignment.topRight,
              children: [
                GestureDetector(
                  onTap: () => showZoomableImage(context, photoBase64!),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      base64Decode(photoBase64!),
                      height: 150,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
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
                  autofocus: photoBase64 != null,
                  enabled: photoBase64 != null,
                  style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: photoBase64 == null ? 'Capture image first' : 'Amount (₹)',
                    labelStyle: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.borderLight), borderRadius: BorderRadius.circular(8)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.accent), borderRadius: BorderRadius.circular(8)),
                    disabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.borderLight.withValues(alpha: 0.5)), borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(LucideIcons.camera, size: 32, color: AppColors.accent),
                onPressed: () async {
                  final picker = ImagePicker();
                  final image = await picker.pickImage(
                    source: ImageSource.camera,
                    imageQuality: 30,
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
          const SizedBox(height: 12),
          // Explicit Payment Method Selection
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: photoBase64 == null ? null : () => setState(() => paymentMethod = 'Cash'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: paymentMethod == 'Cash' ? Colors.green.withValues(alpha: 0.2) : Colors.transparent,
                      border: Border.all(color: paymentMethod == 'Cash' ? Colors.green : AppColors.borderLight.withValues(alpha: 0.5)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text('Cash', style: GoogleFonts.plusJakartaSans(
                        color: paymentMethod == 'Cash' ? Colors.green : AppColors.textSecondary,
                        fontWeight: FontWeight.bold,
                      )),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: photoBase64 == null ? null : () => setState(() => paymentMethod = 'UPI'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: paymentMethod == 'UPI' ? AppColors.purple.withValues(alpha: 0.2) : Colors.transparent,
                      border: Border.all(color: paymentMethod == 'UPI' ? AppColors.purple : AppColors.borderLight.withValues(alpha: 0.5)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text('UPI', style: GoogleFonts.plusJakartaSans(
                        color: paymentMethod == 'UPI' ? AppColors.purple : AppColors.textSecondary,
                        fontWeight: FontWeight.bold,
                      )),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: phoneController,
            keyboardType: TextInputType.phone,
            enabled: photoBase64 != null,
            style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary),
            decoration: InputDecoration(
              labelText: 'Optional: Phone number',
              labelStyle: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.borderLight), borderRadius: BorderRadius.circular(8)),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.accent), borderRadius: BorderRadius.circular(8)),
              disabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.borderLight.withValues(alpha: 0.5)), borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: donationItemController,
            enabled: photoBase64 != null,
            style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary),
            decoration: InputDecoration(
              labelText: 'Optional: Sponsoring items (e.g. Rice, Sarees)',
              labelStyle: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.borderLight), borderRadius: BorderRadius.circular(8)),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.accent), borderRadius: BorderRadius.circular(8)),
              disabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.borderLight.withValues(alpha: 0.5)), borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: !_isSubmitValid ? null : () async {
                final amount = double.tryParse(amountController.text) ?? 0.0;
                final donation = donationItemController.text.trim();
                final phone = phoneController.text.trim();
                
                if (amount <= 0 && donation.isEmpty && widget.unit.status != 'collected') return;

                final authUser = ref.read(authStateProvider).value;
                if (authUser == null) return;

                setState(() => isSubmitting = true);
                
                try {
                  final buildingService = ref.read(buildingServiceProvider);
                  final profile = ref.read(collectorProfileProvider).value;
                  final collectorName = profile?.name ?? 'Admin';

                  if (phone.isNotEmpty) {
                    final isDuplicate = await buildingService.isPhoneNumberInUse(
                      phone,
                      excludeBuildingId: widget.building.id,
                      excludeUnitId: widget.unit.id,
                    );
                    if (isDuplicate) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Phone number already exists.', style: GoogleFonts.plusJakartaSans(color: Colors.white)),
                            backgroundColor: AppColors.amber,
                          ),
                        );
                      }
                      setState(() => isSubmitting = false);
                      return;
                    }
                  }
                  
                  if (amount <= 0 && donation.isEmpty && widget.unit.status == 'collected') {
                    await buildingService.resetUnitCollection(
                      buildingId: widget.building.id,
                      unitId: widget.unit.id,
                      previousAmount: widget.unit.amount,
                    );
                  } else {
                    await buildingService.markUnitCollected(
                      buildingId: widget.building.id,
                      unitId: widget.unit.id,
                      amount: amount,
                      collectedBy: authUser.uid,
                      collectedByName: collectorName,
                      photoBase64: photoBase64,
                      paymentMethod: paymentMethod ?? 'Donation',
                      donationItem: donation,
                      phoneNumber: phone,
                    );
                  }
                  if (context.mounted) Navigator.of(context).pop();
                } catch (e) {
                   setState(() => isSubmitting = false);
                   if (context.mounted) {
                     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e', style: GoogleFonts.plusJakartaSans(color: Colors.white)), backgroundColor: AppColors.crimson));
                   }
                }
              },
              child: isSubmitting 
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(
                      isAlreadyCollected ? 'UPDATE AMOUNT' : 'MARK COLLECTED',
                      style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)
                    ),
            ),
          ),
          ],
        ],
      ),
    );
  }
}


void showCreateBuildingDialog(BuildContext context, WidgetRef ref, latlong.LatLng point) {
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
            backgroundColor: AppColors.bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: AppColors.borderLight)),
            title: Text('Add Building', style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Building Name / Landmark',
                    labelStyle: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.borderLight), borderRadius: BorderRadius.circular(8)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.accent), borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: Text('Multi-unit apartment', style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary)),
                  value: isApartment,
                  activeThumbColor: AppColors.accent,
                  onChanged: (val) {
                    setState(() => isApartment = val);
                  },
                ),
                if (isApartment) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: unitsController,
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Number of Units',
                      labelStyle: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.borderLight), borderRadius: BorderRadius.circular(8)),
                      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.accent), borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.of(ctx).pop(),
                child: Text('CANCEL', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
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
                        unitLabels: List.generate(units, (i) => 'Unit '),
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
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text('CREATE', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }
      );
    },
  );
}
