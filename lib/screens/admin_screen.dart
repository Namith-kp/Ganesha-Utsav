import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/auth_provider.dart';
import '../providers/map_provider.dart';
import '../models/collector.dart';

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
        appBar: AppBar(
          title: const Text('Admin Dashboard'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.people), text: 'Team'),
              Tab(icon: Icon(Icons.history), text: 'Corrections'),
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
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: \${snapshot.error}'));
        }
        
        final collectors = snapshot.data ?? [];
        if (collectors.isEmpty) {
          return const Center(child: Text('No team members found.'));
        }

        return ListView.builder(
          itemCount: collectors.length,
          itemBuilder: (context, index) {
            final collector = collectors[index];
            return ListTile(
              leading: CircleAvatar(child: Text(collector.name[0].toUpperCase())),
              title: Text(collector.name),
              subtitle: Text(collector.email ?? collector.phone),
              trailing: DropdownButton<String>(
                value: collector.role,
                items: const [
                  DropdownMenuItem(value: 'collector', child: Text('Collector')),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                ],
                onChanged: (newRole) async {
                  if (newRole != null && newRole != collector.role) {
                    await authService.updateCollectorRole(collector.id, newRole);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Updated role for ${collector.name}')),
                    );
                  }
                },
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
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: \${snapshot.error}'));
        }

        final logs = snapshot.data ?? [];
        if (logs.isEmpty) {
          return const Center(child: Text('No corrections found.'));
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
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                title: Text('$buildingName - $unitLabel'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text('Changed from ₹$oldAmount to ₹$newAmount'),
                    const SizedBox(height: 4),
                    Text('By: $correctedBy'),
                    if (timestamp != null)
                      Text("At: ${timestamp.toString().split('.')[0]}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
