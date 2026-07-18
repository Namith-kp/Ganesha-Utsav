import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import '../providers/map_provider.dart';
import '../models/building.dart';
import '../models/unit.dart';
import '../widgets/building_bottom_sheet.dart';
import 'street_view_screen.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  bool _isExporting = false;
  Future<List<Map<String, dynamic>>>? _collectionsFuture;

  @override
  void initState() {
    super.initState();
    _loadCollections();
  }

  void _loadCollections() {
    _collectionsFuture = ref.read(buildingServiceProvider).getDetailedCollections();
  }

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _loadCollections();
              });
            },
          ),
          IconButton(
            icon: _isExporting 
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.download),
            tooltip: 'Export CSV',
            onPressed: _isExporting ? null : _exportToCsv,
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _collectionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          
          final collections = snapshot.data ?? [];
          
          double totalCollected = 0.0;
          double todayCollected = 0.0;
          final now = DateTime.now();
          final todayStart = DateTime(now.year, now.month, now.day);
          
          final List<double> dailyTotals = List.filled(7, 0.0);
          final List<String> dailyLabels = List.filled(7, '');
          for(int i=0; i<7; i++) {
             final d = now.subtract(Duration(days: 6 - i));
             dailyLabels[i] = '${d.day}/${d.month}';
          }

          for (var item in collections) {
            final Unit unit = item['unit'];
            totalCollected += unit.amount;
            if (unit.collectedAt != null) {
               final d = DateTime(unit.collectedAt!.year, unit.collectedAt!.month, unit.collectedAt!.day);
               if (d == todayStart) {
                   todayCollected += unit.amount;
               }
               
               final diffDays = todayStart.difference(d).inDays;
               if (diffDays >= 0 && diffDays < 7) {
                  dailyTotals[6 - diffDays] += unit.amount;
               }
            }
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Card(
                      color: Colors.blue.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            const Text('Today', style: TextStyle(color: Colors.blueGrey)),
                            const SizedBox(height: 8),
                            Text('₹${todayCollected.toStringAsFixed(0)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Card(
                      color: Colors.green.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            const Text('Total', style: TextStyle(color: Colors.blueGrey)),
                            const SizedBox(height: 8),
                            Text('₹${totalCollected.toStringAsFixed(0)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text('Last 7 Days', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildChart(dailyTotals, dailyLabels),
                ),
              ),
              const SizedBox(height: 24),
              const Text('Recent Collections', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (collections.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: Text('No collections yet.')),
                ),
              ...collections.take(50).map((item) {
                final Unit unit = item['unit'];
                final Building building = item['building'];
                final date = unit.collectedAt;
                final dateStr = date != null ? '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}' : 'Unknown date';
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: unit.photoBase64 != null 
                        ? ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.memory(base64Decode(unit.photoBase64!), width: 50, height: 50, fit: BoxFit.cover))
                        : const Icon(Icons.image_not_supported, size: 50),
                    title: Text('${building.name} - ${unit.unitLabel}'),
                    subtitle: Text(dateStr),
                    trailing: Text('₹${unit.amount}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
                    onTap: () {
                      _showReportItemPreview(context, ref, building, unit, dateStr);
                    },
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  void _showReportItemPreview(BuildContext context, WidgetRef ref, Building building, Unit unit, String dateStr) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${building.name} - ${unit.unitLabel}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              if (unit.photoBase64 != null)
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(base64Decode(unit.photoBase64!), height: 200, fit: BoxFit.cover),
                  ),
                ),
              if (unit.photoBase64 != null) const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person),
                title: const Text('Collected by'),
                subtitle: Text(unit.collectedBy ?? 'Unknown'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.access_time),
                title: const Text('Date & Time'),
                subtitle: Text(dateStr),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.currency_rupee),
                title: const Text('Amount'),
                subtitle: Text('₹${unit.amount}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 18)),
              ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      showUnitAmountForm(context, ref, building, unit);
                    },
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.map),
                    label: const Text('2D Map'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      context.go('/?lat=${building.lat}&lng=${building.lng}');
                    },
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.streetview),
                    label: const Text('Street View'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      // Import is needed if we use StreetViewScreen directly, or we can use Navigator
                      import_ar(context, building.lat, building.lng);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  void import_ar(BuildContext context, double lat, double lng) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StreetViewScreen(lat: lat, lon: lng),
      ),
    );
  }

  Widget _buildChart(List<double> dailyTotals, List<String> dailyLabels) {
    double maxY = dailyTotals.reduce((a, b) => a > b ? a : b);
    if (maxY == 0) maxY = 100;
    
    return AspectRatio(
      aspectRatio: 1.5,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY * 1.2,
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  if (value >= 0 && value < 7) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(dailyLabels[value.toInt()], style: const TextStyle(fontSize: 10)),
                    );
                  }
                  return const Text('');
                },
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(7, (i) => BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: dailyTotals[i],
                color: Colors.blue,
                width: 16,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          )),
        ),
      ),
    );
  }
}

