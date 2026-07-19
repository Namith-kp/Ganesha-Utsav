import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/spending.dart';
import '../services/spending_service.dart';

Future<bool?> showAddSpendingBottomSheet(BuildContext context, SpendingService spendingService, String createdBy, String createdByName) async {
  return await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _SpendingForm(
      spendingService: spendingService,
      createdBy: createdBy,
      createdByName: createdByName,
    ),
  );
}

Future<bool?> showEditSpendingBottomSheet(BuildContext context, SpendingService spendingService, Spending spending) async {
  return await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _SpendingForm(
      spendingService: spendingService,
      existingSpending: spending,
      createdBy: spending.createdBy,
      createdByName: spending.createdByName,
    ),
  );
}

class _SpendingForm extends StatefulWidget {
  final SpendingService spendingService;
  final Spending? existingSpending;
  final String createdBy;
  final String createdByName;

  const _SpendingForm({
    required this.spendingService,
    this.existingSpending,
    required this.createdBy,
    required this.createdByName,
  });

  @override
  State<_SpendingForm> createState() => _SpendingFormState();
}

class _SpendingFormState extends State<_SpendingForm> {
  late TextEditingController _amountController;
  late TextEditingController _reasonController;
  String? _photoBase64;
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(text: widget.existingSpending?.amount.toStringAsFixed(0) ?? '');
    _reasonController = TextEditingController(text: widget.existingSpending?.reason ?? '');
  }

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(source: source, imageQuality: 70, maxWidth: 800, maxHeight: 800);
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() {
        _photoBase64 = base64Encode(bytes);
      });
    }
  }

  Future<void> _saveSpending() async {
    final amount = double.tryParse(_amountController.text) ?? 0.0;
    final reason = _reasonController.text.trim();

    if (amount <= 0 || reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount and reason.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      if (widget.existingSpending == null) {
        // Add
        await widget.spendingService.addSpending(
          amount: amount,
          reason: reason,
          createdBy: widget.createdBy,
          createdByName: widget.createdByName,
          photoBase64: _photoBase64,
        );
      } else {
        // Edit
        await widget.spendingService.updateSpending(
          spendingId: widget.existingSpending!.id,
          amount: amount,
          reason: reason,
          photoBase64: _photoBase64,
        );
      }
      if (mounted) {
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save spending: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    
    return Container(
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.existingSpending == null ? 'Add Spending' : 'Edit Spending',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          
          // Amount
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Amount (₹)',
              labelStyle: const TextStyle(color: Colors.white54),
              prefixIcon: const Icon(LucideIcons.indianRupee, color: Colors.white54),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // Reason
          TextField(
            controller: _reasonController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Reason / Item Details',
              labelStyle: const TextStyle(color: Colors.white54),
              prefixIcon: const Icon(LucideIcons.fileText, color: Colors.white54),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Image Proof Section
          Text('Proof of Spending (Optional)', style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 12),
          
          if (_photoBase64 != null)
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(base64Decode(_photoBase64!), height: 120, width: double.infinity, fit: BoxFit.cover),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: () => setState(() => _photoBase64 = null),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(Icons.close, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ],
            )
          else if (widget.existingSpending?.photoBase64 != null)
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(base64Decode(widget.existingSpending!.photoBase64!), height: 120, width: double.infinity, fit: BoxFit.cover),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _pickImage(ImageSource.gallery);
                    }),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(LucideIcons.edit2, color: Colors.white, size: 16),
                    ),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(LucideIcons.camera, size: 18),
                    label: const Text('Camera'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(LucideIcons.image, size: 18),
                    label: const Text('Gallery'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),

          const SizedBox(height: 32),
          
          ElevatedButton(
            onPressed: _isLoading ? null : _saveSpending,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5E5CE6),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: _isLoading
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(
                    widget.existingSpending == null ? 'Save Spending' : 'Update Spending',
                    style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
        ],
      ),
    );
  }
}
