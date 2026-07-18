import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart' as latlong;

import '../models/building.dart';
import '../models/unit.dart';
import '../providers/auth_provider.dart';
import '../providers/map_provider.dart';
import '../main.dart'; // For AppColors if needed

void _showAddUnitDialog(BuildContext context, WidgetRef ref, Building building) {
  final controller = TextEditingController();
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Add New Unit'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(labelText: 'Unit Name (e.g. Unit 3)'),
        autofocus: true,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
        ElevatedButton(
          onPressed: () async {
            if (controller.text.trim().isNotEmpty) {
              final buildingService = ref.read(buildingServiceProvider);
              await buildingService.addUnit(
                buildingId: building.id,
                unitLabel: controller.text.trim(),
              );
              if (ctx.mounted) Navigator.pop(ctx);
            }
          },
          child: const Text('ADD'),
        ),
      ],
    ),
  );
}

void showCollectionBottomSheet(BuildContext context, WidgetRef ref, Building building) {
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
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('${building.name} - Units', style: Theme.of(context).textTheme.titleLarge),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_business, color: Colors.blue),
                            tooltip: 'Add Unit',
                            onPressed: () => _showAddUnitDialog(context, ref, building),
                          ),
                          if (ref.read(collectorProfileProvider).value?.role == 'admin')
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              tooltip: 'Delete Building',
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Delete Building?'),
                                    content: const Text('This will delete the building and all its units forever.'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text('DELETE', style: TextStyle(color: Colors.white)),
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
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 16, color: Colors.grey),
                                  onPressed: () {
                                    final controller = TextEditingController(text: unit.unitLabel);
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Rename Unit'),
                                        content: TextField(
                                          controller: controller,
                                          decoration: const InputDecoration(labelText: 'Unit Name'),
                                          autofocus: true,
                                        ),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
                                          ElevatedButton(
                                            onPressed: () async {
                                              if (controller.text.trim().isNotEmpty) {
                                                await buildingService.renameUnit(
                                                  buildingId: building.id,
                                                  unitId: unit.id,
                                                  newName: controller.text.trim(),
                                                );
                                                if (ctx.mounted) Navigator.pop(ctx);
                                              }
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
                                  ? AppColors.greenPin.withOpacity(0.2)
                                  : AppColors.bgGlass,
                              side: BorderSide(
                                color: isCollected ? AppColors.greenPin : AppColors.borderLight,
                              ),
                            ),
                            onTap: () {
                              showUnitAmountForm(context, ref, building, unit);
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
                      IconButton(
                        icon: const Icon(Icons.add_business, color: Colors.blue),
                        tooltip: 'Add Unit',
                        onPressed: () => _showAddUnitDialog(context, ref, building),
                      ),
                      if (ref.read(collectorProfileProvider).value?.role == 'admin')
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          tooltip: 'Delete Building',
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Delete Building?'),
                              content: const Text('This will delete the building and all its units forever.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('DELETE', style: TextStyle(color: Colors.white)),
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
                    ], // Closes children
                  ), // Closes Row
                  _buildAmountForm(context, ref, building, unit),
                ],
              ),
            );
          }
        },
      );
    },
  );
}

void showUnitAmountForm(BuildContext context, WidgetRef ref, Building building, Unit unit) {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${building.name} - ${unit.unitLabel}', style: Theme.of(context).textTheme.headlineSmall),
              IconButton(
                icon: const Icon(Icons.edit, size: 20, color: Colors.grey),
                onPressed: () {
                  final controller = TextEditingController(text: unit.unitLabel);
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Rename Unit'),
                      content: TextField(
                        controller: controller,
                        decoration: const InputDecoration(labelText: 'Unit Name'),
                        autofocus: true,
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
                        ElevatedButton(
                          onPressed: () async {
                            if (controller.text.trim().isNotEmpty) {
                              final buildingService = ref.read(buildingServiceProvider);
                              await buildingService.renameUnit(
                                buildingId: building.id,
                                unitId: unit.id,
                                newName: controller.text.trim(),
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (context.mounted) Navigator.pop(context); // Close the sheet to refresh
                            }
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
          const SizedBox(height: 16),
          if (unit.photoBase64 != null) ...[
            GestureDetector(
              onTap: () {
                showDialog(
                  context: context,
                  builder: (ctx) => Dialog(
                    backgroundColor: Colors.transparent,
                    child: Stack(
                      alignment: Alignment.topRight,
                      children: [
                        InteractiveViewer(
                          child: Image.memory(
                            base64Decode(unit.photoBase64!),
                            fit: BoxFit.contain,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white, size: 30),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                  ),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  base64Decode(unit.photoBase64!),
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          const Icon(Icons.check_circle, color: Colors.green, size: 64),
          const SizedBox(height: 16),
          Text('Amount Collected: ₹${unit.amount}'),
          const SizedBox(height: 24),
          const SizedBox(height: 24),
          if (!isAdmin)
            const Text('Only admins can edit collected units.', style: TextStyle(color: Colors.grey))
          else
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: const Text('RESET COLLECTION', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Reset Collection?'),
                    content: const Text('This will reset the amount to 0 and mark the unit as pending.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('RESET'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  final buildingService = ref.read(buildingServiceProvider);
                  await buildingService.resetUnitCollection(
                    buildingId: building.id,
                    unitId: unit.id,
                    previousAmount: unit.amount,
                  );
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Text('Collect for: ${building.name} - ${unit.unitLabel}', style: Theme.of(context).textTheme.titleLarge),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20, color: Colors.grey),
                  onPressed: () {
                    final controller = TextEditingController(text: unit.unitLabel);
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Rename Unit'),
                        content: TextField(
                          controller: controller,
                          decoration: const InputDecoration(labelText: 'Unit Name'),
                          autofocus: true,
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
                          ElevatedButton(
                            onPressed: () async {
                              if (controller.text.trim().isNotEmpty) {
                                final buildingService = ref.read(buildingServiceProvider);
                                await buildingService.renameUnit(
                                  buildingId: building.id,
                                  unitId: unit.id,
                                  newName: controller.text.trim(),
                                );
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (context.mounted) Navigator.pop(context); // Close the sheet to refresh
                              }
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
            const SizedBox(height: 16),
            if (photoBase64 != null) ...[
              Stack(
                alignment: Alignment.topRight,
                children: [
                  GestureDetector(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => Dialog(
                          backgroundColor: Colors.transparent,
                          child: Stack(
                            alignment: Alignment.topRight,
                            children: [
                              InteractiveViewer(
                                child: Image.memory(
                                  base64Decode(photoBase64!),
                                  fit: BoxFit.contain,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                                onPressed: () => Navigator.of(ctx).pop(),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
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
                  if (amount < 0) return;

                  final authUser = ref.read(authStateProvider).value;
                  if (authUser == null) return;

                  setState(() => isSubmitting = true);
                  
                  try {
                    final buildingService = ref.read(buildingServiceProvider);
                    
                    if (amount == 0) {
                      // If user enters 0, reset the collection entirely (only if it was collected)
                      if (unit.status == 'collected') {
                        await buildingService.resetUnitCollection(
                          buildingId: building.id,
                          unitId: unit.id,
                          previousAmount: unit.amount,
                        );
                      }
                    } else {
                      await buildingService.markUnitCollected(
                        buildingId: building.id,
                        unitId: unit.id,
                        amount: amount,
                        collectedBy: authUser.uid,
                        photoBase64: photoBase64,
                      );
                    }
                    
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
