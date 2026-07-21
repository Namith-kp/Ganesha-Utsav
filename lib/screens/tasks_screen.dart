import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../providers/map_provider.dart';
import '../models/building.dart';
import '../models/unit.dart';
import '../main.dart';
import '../utils/building_dialogs.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  Future<List<Map<String, dynamic>>>? _tasksFuture;
  List<Map<String, dynamic>>? _cachedTasks;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    _tasksFuture = ref.read(buildingServiceProvider).getPendingCollections().then((data) {
      if (mounted) setState(() => _cachedTasks = data);
      return data;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
        backgroundColor: AppColors.bgCard,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: () {
              setState(() {
                _loadData();
              });
            },
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _tasksFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.accent));
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
          }
          
          final tasks = snapshot.data ?? [];
          
          if (tasks.isEmpty) {
            return const Center(child: Text('No pending tasks.', style: TextStyle(color: Colors.white54)));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              final Unit unit = task['unit'];
              final Building building = task['building'];
              
              return Card(
                color: const Color(0xFF1E1E1E),
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      building.totalUnits > 1 ? LucideIcons.building2 : LucideIcons.home,
                      color: Colors.orange,
                    ),
                  ),
                  title: Text(
                    '${building.name} - ${unit.unitLabel}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.clock, size: 14, color: Colors.white54),
                        const SizedBox(width: 4),
                        Text('Pending Collection', style: GoogleFonts.plusJakartaSans(color: Colors.white54, fontSize: 13)),
                      ],
                    ),
                  ),
                  trailing: const Icon(LucideIcons.chevronRight, color: Colors.white38),
                  onTap: () async {
                    await showCollectionBottomSheet(context, ref, building);
                    if (mounted) {
                      setState(() {
                        _loadData();
                      });
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
