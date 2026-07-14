import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/map_provider.dart';
import '../models/building.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  bool _isExporting = false;

  Future<void> _exportToCsv() async {
    setState(() => _isExporting = true);
    try {
      final buildingService = ref.read(buildingServiceProvider);
      final data = await buildingService.getFlattenedCollectionData();

      if (data.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No data to export.')),
          );
        }
        setState(() => _isExporting = false);
        return;
      }

      // Extract headers
      final headers = data.first.keys.toList();
      
      // Extract rows
      final rows = data.map((map) => headers.map((h) => map[h]).toList()).toList();
      
      // Combine
      final csvData = [headers, ...rows];
      
      // Convert to CSV string
      String csv = const CsvEncoder().convert(csvData);
      
      // Get temporary directory
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/collections_report.csv';
      
      // Write to file
      final file = File(path);
      await file.writeAsString(csv);
      
      // Share file
      await SharePlus.instance.share(ShareParams(
        files: [XFile(path)], 
        text: 'Ganesha Funds Collection Report',
      ));

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exporting CSV: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final buildingsAsync = ref.watch(buildingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          IconButton(
            icon: _isExporting 
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.download),
            tooltip: 'Export CSV',
            onPressed: _isExporting ? null : _exportToCsv,
          ),
        ],
      ),
      body: buildingsAsync.when(
        data: (buildings) {
          double totalCollected = 0.0;
          int totalUnits = 0;
          int collectedUnits = 0;
          
          for (var b in buildings) {
            totalCollected += b.totalCollected;
            totalUnits += b.totalUnits;
            collectedUnits += b.collectedCount;
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                elevation: 4,
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      const Text('Total Collected', style: TextStyle(fontSize: 18, color: Colors.blueGrey)),
                      const SizedBox(height: 8),
                      Text('₹${totalCollected.toStringAsFixed(2)}', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.blue)),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              Text('$collectedUnits / $totalUnits', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                              const Text('Units Collected', style: TextStyle(color: Colors.blueGrey)),
                            ],
                          ),
                          Column(
                            children: [
                              Text('${buildings.length}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                              const Text('Buildings', style: TextStyle(color: Colors.blueGrey)),
                            ],
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text('Recent Buildings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...buildings.take(10).map((b) => ListTile(
                title: Text(b.name),
                subtitle: Text('${b.collectedCount} / ${b.totalUnits} units'),
                trailing: Text('₹${b.totalCollected.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              )),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
