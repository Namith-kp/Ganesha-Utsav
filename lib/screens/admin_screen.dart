import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../providers/auth_provider.dart';
import '../providers/map_provider.dart';
import '../models/collector.dart';
import '../main.dart';

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.bgBase,
        appBar: AppBar(
          backgroundColor: AppColors.bgCard,
          elevation: 0,
          title: Text(
            'Admin Dashboard',
            style: GoogleFonts.plusJakartaSans(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          iconTheme: const IconThemeData(color: AppColors.textPrimary),
          bottom: TabBar(
            indicatorColor: AppColors.accent,
            labelColor: AppColors.accent,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
            tabs: const [
              Tab(icon: Icon(LucideIcons.users), text: 'Team'),
              Tab(icon: Icon(LucideIcons.history), text: 'Corrections'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _TeamTab(),
            _CorrectionsTab(),
          ],
        ),
      ),
    );
  }
}

class _TeamTab extends ConsumerWidget {
  const _TeamTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authService = ref.read(authServiceProvider);
    
    return StreamBuilder<List<Collector>>(
      stream: authService.streamAllCollectors(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppColors.accent));
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('Error: \${snapshot.error}', style: GoogleFonts.plusJakartaSans(color: AppColors.crimson)),
          );
        }
        
        final collectors = snapshot.data ?? [];
        if (collectors.isEmpty) {
          return Center(
            child: Text('No team members found.', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary)),
          );
        }

        return ListView.builder(
          itemCount: collectors.length,
          itemBuilder: (context, index) {
            final collector = collectors[index];
            return Card(
              color: AppColors.bgCard,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.border),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.accent.withOpacity(0.2),
                  foregroundColor: AppColors.accent,
                  child: Text(collector.name[0].toUpperCase(), style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
                ),
                title: Text(collector.name, style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                subtitle: Text(collector.email ?? collector.phone, style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 13)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: collector.isCoreTeamMember,
                      activeColor: AppColors.accent,
                      onChanged: (val) async {
                        if (val != null) {
                          await authService.updateCollectorTeamStatus(collector.id, val);
                        }
                      },
                    ),
                    Text('Core', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: collector.role,
                      dropdownColor: AppColors.bgCard,
                      style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary, fontSize: 13),
                      underline: Container(), // Remove underline
                      icon: const Icon(LucideIcons.chevronDown, size: 16, color: AppColors.textSecondary),
                      items: [
                        DropdownMenuItem(value: 'viewer', child: Text('Viewer', style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary))),
                        DropdownMenuItem(value: 'team_member', child: Text('Team Member', style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary))),
                        DropdownMenuItem(value: 'collector', child: Text('Collector', style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary))),
                        DropdownMenuItem(value: 'admin', child: Text('Admin', style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary))),
                      ],
                      onChanged: (newRole) async {
                        if (newRole != null && newRole != collector.role) {
                          await authService.updateCollectorRole(collector.id, newRole);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Updated role for ${collector.name}', style: GoogleFonts.plusJakartaSans()),
                              backgroundColor: AppColors.bgCard,
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _CorrectionsTab extends ConsumerWidget {
  const _CorrectionsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buildingService = ref.read(buildingServiceProvider);

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: buildingService.streamCorrectionsLog(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppColors.accent));
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('Error: \${snapshot.error}', style: GoogleFonts.plusJakartaSans(color: AppColors.crimson)),
          );
        }

        final logs = snapshot.data ?? [];
        if (logs.isEmpty) {
          return Center(
            child: Text('No corrections found.', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary)),
          );
        }

        return ListView.builder(
          itemCount: logs.length,
          itemBuilder: (context, index) {
            final log = logs[index];
            final buildingName = log['buildingName'] ?? 'Unknown';
            final unitLabel = log['unitLabel'] ?? 'Unknown';
            final oldAmount = log['oldAmount'];
            final newAmount = log['newAmount'];
            final correctedBy = log['correctedBy'] ?? 'Unknown User';
            final timestamp = (log['timestamp'] as Timestamp?)?.toDate();

            return Card(
              color: AppColors.bgCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.border),
              ),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                title: Text('$buildingName - $unitLabel', style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),
                    Text('Changed from ₹$oldAmount to ₹$newAmount', style: GoogleFonts.plusJakartaSans(color: AppColors.amber, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text('By: $correctedBy', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 13)),
                    if (timestamp != null)
                      Text("At: ${timestamp.toString().split('.')[0]}", style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textMuted)),
                  ],
                ),
                isThreeLine: true,
              ),
            );
          },
        );
      },
    );
  }
}
