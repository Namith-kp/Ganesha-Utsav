import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import '../models/building.dart';
import '../models/unit.dart';
import '../providers/auth_provider.dart';
import '../providers/map_provider.dart';
import '../services/building_service.dart';
import '../screens/street_view_screen.dart';
import 'package:go_router/go_router.dart';

void showBuildingDetailsBottomSheet(BuildContext context, WidgetRef ref, Building building) {
  final buildingService = ref.read(buildingServiceProvider);
  final currentUserRole = ref.read(collectorProfileProvider).value?.role;
  final isAdmin = currentUserRole == 'admin';

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return StreamBuilder<Building>(
        stream: buildingService.streamBuilding(building.id),
        builder: (context, buildingSnapshot) {
          if (buildingSnapshot.hasError || !buildingSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final currentBuilding = buildingSnapshot.data!;

          return StreamBuilder<List<Unit>>(
            stream: buildingService.streamUnits(currentBuilding.id),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              
              final units = snapshot.data!;
              if (units.isEmpty) return const Center(child: Text('No units found.'));
              
              if (currentBuilding.totalUnits > 1) {
                return DraggableScrollableSheet(
                  expand: false,
                  initialChildSize: 0.6,
                  builder: (context, scrollController) {
                    return Column(
                      children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text('${currentBuilding.name} - Units', style: Theme.of(context).textTheme.titleLarge),
                          ),
                          if (isAdmin)
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _showEditBuildingNameDialog(context, ref, currentBuilding),
                            ),
                        ],
                      ),
                    ),
                    _buildBuildingMetaInfo(currentBuilding),
                    const Divider(),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: units.length,
                        itemBuilder: (context, index) {
                          final unit = units[index];
                          final isCollected = unit.status == 'collected';
                          return ListTile(
                            title: Text(unit.unitLabel),
                            subtitle: unit.updatedAt != null 
                                ? Text('Updated: ${unit.updatedAt!.day}/${unit.updatedAt!.month}/${unit.updatedAt!.year} ${unit.updatedAt!.hour}:${unit.updatedAt!.minute.toString().padLeft(2, '0')}')
                                : null,
                            trailing: Chip(
                              label: Text(isCollected ? 'Collected' : 'Pending', 
                                style: TextStyle(color: isCollected ? Colors.white : Colors.black)
                              ),
                              backgroundColor: isCollected ? Colors.green : Colors.grey[300],
                            ),
                            onTap: () {
                              showUnitAmountForm(context, ref, currentBuilding, unit);
                            },
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          TextButton(
                            onPressed: () => _showAddUnitDialog(context, ref, currentBuilding),
                            child: const Text('ADD UNIT'),
                          ),
                          if (isAdmin) ...[
                            TextButton(
                              onPressed: () {
                                ref.read(moveBuildingProvider.notifier).setState(currentBuilding);
                                Navigator.pop(context); // Close the bottom sheet
                              },
                              child: const Text('UPDATE LOC', style: TextStyle(color: Colors.blue)),
                            ),
                            TextButton(
                              onPressed: () => _confirmDeleteBuilding(context, currentBuilding),
                              child: const Text('DELETE TAG', style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ],
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
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(currentBuilding.name, style: Theme.of(context).textTheme.titleLarge),
                          ),
                          if (isAdmin)
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _showEditBuildingNameDialog(context, ref, currentBuilding),
                            ),
                        ],
                      ),
                    ),
                    _buildBuildingMetaInfo(currentBuilding),
                    const Divider(),
                    _AmountFormWidget(building: currentBuilding, unit: unit),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          TextButton(
                            onPressed: () => _showAddUnitDialog(context, ref, currentBuilding),
                            child: const Text('ADD UNIT'),
                          ),
                          if (isAdmin) ...[
                            TextButton(
                              onPressed: () {
                                ref.read(moveBuildingProvider.notifier).setState(currentBuilding);
                                Navigator.pop(context);
                              },
                              child: const Text('UPDATE LOC', style: TextStyle(color: Colors.blue)),
                            ),
                            TextButton(
                              onPressed: () => _confirmDeleteBuilding(context, currentBuilding),
                              child: const Text('DELETE TAG', style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        },
      );
      },
      );
    },
  );
}

Widget _buildBuildingMetaInfo(Building building) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16.0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Total Collected: ₹${building.totalCollected.toStringAsFixed(0)}'),
        const SizedBox(height: 8),
        FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('collectors').doc(building.createdBy).get(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return const Text('Added By: Unknown Collector');
            }
            final collectorData = snapshot.data!.data() as Map<String, dynamic>;
            final collectorName = collectorData['name'] ?? 'Unknown';
            return Text('Added By: $collectorName');
          },
        ),
        const SizedBox(height: 8),
        Text('Created: ${building.createdAt.day}/${building.createdAt.month}/${building.createdAt.year} ${building.createdAt.hour}:${building.createdAt.minute.toString().padLeft(2, '0')}'),
        if (building.updatedAt != null)
          Text('Last Updated: ${building.updatedAt!.day}/${building.updatedAt!.month}/${building.updatedAt!.year} ${building.updatedAt!.hour}:${building.updatedAt!.minute.toString().padLeft(2, '0')}'),
      ],
    ),
  );
}

void _showEditBuildingNameDialog(BuildContext context, WidgetRef ref, Building building) {
  final nameController = TextEditingController(text: building.name);
  showDialog(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Edit Building Name'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Building Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
              final newName = nameController.text.trim();
              if (newName.isNotEmpty && newName != building.name) {
                await ref.read(buildingServiceProvider).updateBuildingName(building.id, newName);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('SAVE'),
          ),
        ],
      );
    },
  );
}

void _showAddUnitDialog(BuildContext context, WidgetRef ref, Building building) {
  final unitNameController = TextEditingController();
  showDialog(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Add New Unit'),
        content: TextField(
          controller: unitNameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Unit Name / Label'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
              final unitLabel = unitNameController.text.trim();
              if (unitLabel.isNotEmpty) {
                await ref.read(buildingServiceProvider).addUnitToBuilding(building.id, unitLabel);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('ADD'),
          ),
        ],
      );
    },
  );
}

void _confirmDeleteBuilding(BuildContext context, Building building) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Delete Tag?'),
      content: const Text('Are you sure you want to delete this tag? This action cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('CANCEL')),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: const Text('DELETE', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );

  if (confirm == true) {
    // Capture the navigator before the async operation
    // Local Firestore writes immediately trigger a snapshot update, which can unmount the 
    // current context before the await finishes.
    final navigator = Navigator.of(context);
    try {
      await BuildingService().deleteBuilding(building.id);
      navigator.pop(); // Close sheet
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}

void showUnitAmountForm(BuildContext context, WidgetRef ref, Building building, Unit unit) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(child: _AmountFormWidget(building: building, unit: unit)),
      );
    },
  );
}

class _AmountFormWidget extends StatefulWidget {
  final Building building;
  final Unit unit;

  const _AmountFormWidget({Key? key, required this.building, required this.unit}) : super(key: key);

  @override
  State<_AmountFormWidget> createState() => _AmountFormWidgetState();
}

class _AmountFormWidgetState extends State<_AmountFormWidget> {
  late TextEditingController amountController;
  bool isSubmitting = false;
  String? photoBase64;
  bool isEditing = false;

  @override
  void initState() {
    super.initState();
    final isAlreadyCollected = widget.unit.status == 'collected';
    isEditing = !isAlreadyCollected;
    amountController = TextEditingController(text: isAlreadyCollected ? widget.unit.amount.toString() : '');
    photoBase64 = widget.unit.photoBase64;
  }

  @override
  void dispose() {
    amountController.dispose();
    super.dispose();
  }

  void _showZoomableImage(BuildContext context, String base64String) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
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
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ProviderScope.containerOf(context).read(collectorProfileProvider).value?.role == 'admin';
    final isAlreadyCollected = widget.unit.status == 'collected';

    if (isAlreadyCollected && (!isAdmin || !isEditing)) {
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${widget.building.name} - ${widget.unit.unitLabel}', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            if (widget.unit.photoBase64 != null) ...[
              GestureDetector(
                onTap: () => _showZoomableImage(context, widget.unit.photoBase64!),
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
            const Icon(Icons.check_circle, color: Colors.green, size: 64),
            const SizedBox(height: 16),
            Text('Amount Collected: ₹${widget.unit.amount}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (widget.unit.collectedBy != null) ...[
              FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('collectors').doc(widget.unit.collectedBy).get(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || !snapshot.data!.exists) {
                    return const Text('Collected By: Unknown');
                  }
                  final collectorData = snapshot.data!.data() as Map<String, dynamic>;
                  final collectorName = collectorData['name'] ?? 'Unknown';
                  return Text('Collected By: $collectorName');
                }
              ),
              const SizedBox(height: 8),
            ],
            if (widget.unit.collectedAt != null)
              Text('Collected At: ${widget.unit.collectedAt!.day}/${widget.unit.collectedAt!.month}/${widget.unit.collectedAt!.year} ${widget.unit.collectedAt!.hour}:${widget.unit.collectedAt!.minute.toString().padLeft(2, '0')}'),
            const SizedBox(height: 24),
            if (!isAdmin)
              const Text('Only admins can edit collected units.', style: TextStyle(color: Colors.grey))
            else
              ElevatedButton.icon(
                icon: const Icon(Icons.edit),
                label: const Text('EDIT AMOUNT'),
                onPressed: () => setState(() => isEditing = true),
              ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.map),
                  label: const Text('2D MAP'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.go('/?lat=${widget.building.lat}&lng=${widget.building.lng}');
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.streetview),
                  label: const Text('STREET VIEW'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => StreetViewScreen(
                        lat: widget.building.lat,
                        lon: widget.building.lng,
                      ),
                    ));
                  },
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
          Text('Collect for: ${widget.building.name} - ${widget.unit.unitLabel}', style: Theme.of(context).textTheme.titleLarge),
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
                  autofocus: photoBase64 != null,
                  enabled: photoBase64 != null,
                  decoration: InputDecoration(
                    labelText: photoBase64 == null ? 'Capture image first' : 'Amount (₹)',
                    border: const OutlineInputBorder(),
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
                    if (mounted) {
                      setState(() {
                        photoBase64 = base64Encode(bytes);
                      });
                    }
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (isSubmitting || photoBase64 == null) ? null : () async {
                final amount = double.tryParse(amountController.text) ?? 0.0;
                if (amount <= 0) return;

                final container = ProviderScope.containerOf(context);
                final authUser = container.read(authStateProvider).value;
                if (authUser == null) return;

                setState(() => isSubmitting = true);
                
                try {
                  final buildingService = container.read(buildingServiceProvider);
                  await buildingService.markUnitCollected(
                    buildingId: widget.building.id,
                    unitId: widget.unit.id,
                    amount: amount,
                    collectedBy: authUser.uid,
                    photoBase64: photoBase64,
                  );
                  if (mounted) Navigator.of(context).pop();
                } catch (e) {
                   if (mounted) {
                     setState(() => isSubmitting = false);
                     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
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
}
