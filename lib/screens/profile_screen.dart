import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../providers/auth_provider.dart';
import '../providers/map_provider.dart';
import '../models/unit.dart';
import '../models/building.dart';
import '../main.dart';
import 'package:intl/intl.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  Future<List<Map<String, dynamic>>>? _myCollectionsFuture;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    final profile = ref.read(collectorProfileProvider).value;
    if (profile != null && profile.isCollector) {
      _myCollectionsFuture = ref.read(buildingServiceProvider).getDetailedCollections(filterCollectorId: profile.id);
    }
  }

  Future<void> _handleLogout() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text('Logout', style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary)),
        content: Text('Are you sure you want to log out?', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Logout', style: GoogleFonts.plusJakartaSans(color: AppColors.crimson, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await ref.read(authServiceProvider).signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(collectorProfileProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: AppColors.bgCard,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.logOut, color: AppColors.crimson),
            onPressed: _handleLogout,
            tooltip: 'Logout',
          ),
        ],
      ),
      body: profile == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                setState(() {
                  _loadData();
                });
              },
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  _buildProfileHeader(profile.name, profile.role, profile.photoUrl),
                  const SizedBox(height: 24),
                  if (profile.isCollector) _buildCollectedByYouSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildProfileHeader(String name, String role, String? photoUrl) {
    return Card(
      color: AppColors.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: AppColors.accent.withValues(alpha: 0.2),
              foregroundColor: AppColors.accent,
              backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
              child: photoUrl == null ? const Icon(LucideIcons.user, size: 32) : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      role.toUpperCase().replaceAll('_', ' '),
                      style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.accent),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollectedByYouSection() {
    if (_myCollectionsFuture == null) return const SizedBox.shrink();

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _myCollectionsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppColors.accent));
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: AppColors.crimson)));
        }

        final collections = snapshot.data ?? [];
        double totalAmount = 0;
        for (var item in collections) {
          final Unit unit = item['unit'];
          totalAmount += unit.amount;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Collected By You', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            Card(
              color: AppColors.green.withValues(alpha: 0.2),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: AppColors.green.withValues(alpha: 0.5))),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Total Collected',
                        style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text('₹${totalAmount.toStringAsFixed(0)}', style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.green)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (collections.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text('No collections yet.', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary)),
              )
            else
              ...collections.map((item) => _buildCollectionItem(item)).toList(),
          ],
        );
      },
    );
  }

  Widget _buildCollectionItem(Map<String, dynamic> item) {
    final Building building = item['building'];
    final Unit unit = item['unit'];
    final String dateStr = unit.collectedAt != null 
        ? DateFormat('MMM d, hh:mm a').format(unit.collectedAt!)
        : 'Unknown date';

    IconData methodIcon = LucideIcons.banknote;
    if (unit.paymentMethod == 'upi') methodIcon = LucideIcons.smartphone;
    if (unit.paymentMethod == 'bank') methodIcon = LucideIcons.landmark;

    return Card(
      color: AppColors.bgCard,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.green.withValues(alpha: 0.1),
          foregroundColor: AppColors.green,
          child: Icon(methodIcon, size: 20),
        ),
        title: Text(
          '${building.name} - ${unit.unitLabel}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(dateStr, style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 13)),
        trailing: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('₹${unit.amount.toStringAsFixed(0)}', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.green)),
        ),
      ),
    );
  }
}
