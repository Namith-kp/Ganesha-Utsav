import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import '../main.dart';
import '../providers/map_provider.dart';
import '../models/building.dart';
import '../models/unit.dart';
import '../models/collector.dart';
import '../utils/building_dialogs.dart';
import '../providers/auth_provider.dart';
import '../services/auth_service.dart';
import 'collector_report_screen.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> with SingleTickerProviderStateMixin {
  bool _isExporting = false;
  Future<List<Map<String, dynamic>>>? _collectionsFuture;
  Future<List<Collector>>? _collectorsFuture;
  TabController? _tabController;
  int _touchedBarIndex = -1;
  String _filterType = 'All Time';
  DateTime? _customDate;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }
  
  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  void _loadData() {
    final profile = ref.read(collectorProfileProvider).value;
    final filterId = (profile != null && profile.isCollector && !profile.isCoreTeamMember) 
      ? profile.id 
      : null;
    
    _collectionsFuture = ref.read(buildingServiceProvider).getDetailedCollections(filterCollectorId: filterId);
    _collectorsFuture = AuthService().getAllCollectors();
  }

  Future<void> _exportToCsv() async {
    setState(() => _isExporting = true);
    try {
      final buildingService = ref.read(buildingServiceProvider);
      
      final profile = ref.read(collectorProfileProvider).value;
      final filterId = (profile != null && profile.isCollector && !profile.isCoreTeamMember) 
        ? profile.id 
        : null;

      final data = await buildingService.getFlattenedCollectionData(filterCollectorId: filterId);

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
    final profile = ref.watch(collectorProfileProvider).value;
    final isAdmin = profile?.isAdmin ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Collections'),
            Tab(text: 'Leaderboard'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _loadData();
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
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCollectionsTab(),
          _buildLeaderboardTab(isAdmin),
        ],
      ),
    );
  }

  Widget _buildCollectionsTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _collectionsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        
        final collections = snapshot.data ?? [];
        
        final now = DateTime.now();
        final todayStart = DateTime(now.year, now.month, now.day);
        final yesterdayStart = todayStart.subtract(const Duration(days: 1));
        
        final Map<DateTime, double> dailyTotalsMap = {};
        for (var item in collections) {
          final Unit unit = item['unit'];
          if (unit.collectedAt != null) {
            final d = DateTime(unit.collectedAt!.year, unit.collectedAt!.month, unit.collectedAt!.day);
            dailyTotalsMap[d] = (dailyTotalsMap[d] ?? 0) + unit.amount;
          }
        }

        List<Map<String, dynamic>> filteredCollections = collections.where((item) {
           final Unit unit = item['unit'];
           if (_filterType == 'All Time') return true;
           if (unit.collectedAt == null) return false;
           
           DateTime d = DateTime(unit.collectedAt!.year, unit.collectedAt!.month, unit.collectedAt!.day);
           if (_filterType == 'Today' && d == todayStart) return true;
           if (_filterType == 'Yesterday' && d == yesterdayStart) return true;
           if (_filterType == 'Custom Date' && _customDate != null && d == _customDate) return true;
           
           return false;
        }).toList();

        double totalCollected = 0.0;
        double todayCollected = 0.0;
        double totalUpi = 0.0;
        double totalCash = 0.0;
        
        Map<DateTime, List<Map<String, dynamic>>> collectionsByDate = {};
        Map<DateTime, Map<String, double>> dateSummaries = {};

        for (var item in filteredCollections) {
          final Unit unit = item['unit'];
          totalCollected += unit.amount;
          if (unit.paymentMethod == 'UPI') {
            totalUpi += unit.amount;
          } else {
            totalCash += unit.amount;
          }
          if (unit.collectedAt != null) {
            final d = DateTime(unit.collectedAt!.year, unit.collectedAt!.month, unit.collectedAt!.day);
            if (d == todayStart) {
                todayCollected += unit.amount;
            }
            
            collectionsByDate.putIfAbsent(d, () => []).add(item);
            dateSummaries.putIfAbsent(d, () => {'UPI': 0.0, 'Cash': 0.0});
            if (unit.paymentMethod == 'UPI') {
                dateSummaries[d]!['UPI'] = dateSummaries[d]!['UPI']! + unit.amount;
            } else {
                dateSummaries[d]!['Cash'] = dateSummaries[d]!['Cash']! + unit.amount;
            }
          }
        }
        
        final sortedDates = collectionsByDate.keys.toList()..sort((a, b) => b.compareTo(a));

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Stats', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 1.5,
                      children: [
                        if (_filterType == 'All Time')
                           _buildGradientCard('Today', todayCollected, AppColors.accent),
                        if (_filterType != 'All Time')
                           _buildGradientCard('Total', totalCollected, AppColors.green),
                        if (_filterType == 'All Time')
                           _buildGradientCard('Total', totalCollected, AppColors.green),
                        if (_filterType != 'All Time')
                           _buildGradientCard('Transactions', filteredCollections.length.toDouble(), AppColors.accent, isCount: true),
                        _buildGradientCard('Total UPI', totalUpi, Colors.purple.shade400),
                        _buildGradientCard('Total Cash', totalCash, AppColors.amber),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Text('Last 7 Days', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: _buildChart(dailyTotalsMap),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Recent Collections', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: DropdownButton<String>(
                            value: _filterType,
                            icon: Icon(LucideIcons.filter, size: 16, color: Colors.blue.shade700),
                            style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.bold, fontSize: 14),
                            underline: const SizedBox(),
                            items: ['All Time', 'Today', 'Yesterday', 'Custom Date'].map((String value) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              );
                            }).toList(),
                            onChanged: (String? newValue) async {
                              if (newValue == 'Custom Date') {
                                 final picked = await showDatePicker(
                                   context: context,
                                   initialDate: _customDate ?? DateTime.now(),
                                   firstDate: DateTime(2020),
                                   lastDate: DateTime.now(),
                                 );
                                 if (picked != null) {
                                    setState(() {
                                      _filterType = newValue!;
                                      _customDate = DateTime(picked.year, picked.month, picked.day);
                                    });
                                 }
                              } else if (newValue != null) {
                                 setState(() {
                                   _filterType = newValue;
                                 });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    if (_filterType == 'Custom Date' && _customDate != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text('Showing data for ${_customDate!.day}/${_customDate!.month}/${_customDate!.year}', style: const TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.w500)),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            if (collections.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: Text('No collections yet.')),
                ),
              ),
            ...sortedDates.map((date) {
              final items = collectionsByDate[date]!;
              final summary = dateSummaries[date]!;
              final dateStr = (date == todayStart) ? 'Today' : (date == todayStart.subtract(const Duration(days: 1)) ? 'Yesterday' : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}');
              
              // Sort items in this date by collectedAt descending
              items.sort((a, b) {
                final Unit uA = a['unit'];
                final Unit uB = b['unit'];
                if (uA.collectedAt == null || uB.collectedAt == null) return 0;
                return uB.collectedAt!.compareTo(uA.collectedAt!);
              });

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index == 0) {
                      // Header
                      return Padding(
                        padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(dateStr, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                            Row(
                              children: [
                                if (summary['UPI']! > 0)
                                  Text('UPI: ₹${summary['UPI']!.toStringAsFixed(0)}  ', style: TextStyle(fontSize: 12, color: Colors.purple.shade700, fontWeight: FontWeight.w600)),
                                if (summary['Cash']! > 0)
                                  Text('Cash: ₹${summary['Cash']!.toStringAsFixed(0)}', style: TextStyle(fontSize: 12, color: Colors.orange.shade700, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ],
                        ),
                      );
                    }
                    
                    final itemIndex = index - 1;
                    final item = items[itemIndex];
                    final Unit unit = item['unit'];
                    final Building building = item['building'];
                    final date = unit.collectedAt;
                    final timeStr = date != null ? '${date.hour}:${date.minute.toString().padLeft(2, '0')}' : 'No time';

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: unit.photoBase64 != null 
                              ? ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.memory(base64Decode(unit.photoBase64!), width: 50, height: 50, fit: BoxFit.cover))
                              : Icon(LucideIcons.imageOff, size: 50),
                          title: Text('${building.name} - ${unit.unitLabel}'),
                          subtitle: Row(
                            children: [
                              Text(timeStr),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: unit.paymentMethod == 'UPI' ? Colors.purple.shade100 : Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(unit.paymentMethod ?? 'Unknown', style: TextStyle(
                                  fontSize: 10,
                                  color: unit.paymentMethod == 'UPI' ? Colors.purple.shade700 : Colors.orange.shade700,
                                  fontWeight: FontWeight.bold,
                                )),
                              )
                            ],
                          ),
                          trailing: Text('₹${unit.amount}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
                          onTap: () {
                            showUnitAmountForm(context, ref, building, unit, fromReports: true);
                          },
                        ),
                      ),
                    );
                  },
                  childCount: items.length + 1, // +1 for the header
                ),
              );
            }).toList(),
            const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
          ],
        );
      }
    );
  }

  Widget _buildLeaderboardTab(bool isAdmin) {
    return FutureBuilder(
      future: Future.wait([_collectionsFuture!, _collectorsFuture!]),
      builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));

        final collections = snapshot.data![0] as List<Map<String, dynamic>>;
        final collectors = snapshot.data![1] as List<Collector>;

        Map<String, double> collectorTotals = {};
        Map<String, List<Map<String, dynamic>>> collectorItems = {};
        
        for (var item in collections) {
           final Unit unit = item['unit'];
           if (unit.collectedBy != null) {
              collectorTotals[unit.collectedBy!] = (collectorTotals[unit.collectedBy!] ?? 0) + unit.amount;
              collectorItems.putIfAbsent(unit.collectedBy!, () => []).add(item);
           }
        }

        collectors.sort((a, b) => (collectorTotals[b.id] ?? 0).compareTo(collectorTotals[a.id] ?? 0));

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: collectors.length,
          itemBuilder: (context, index) {
             final collector = collectors[index];
             final total = collectorTotals[collector.id] ?? 0.0;
             if (total == 0) return const SizedBox.shrink();

             return Card(
               margin: const EdgeInsets.only(bottom: 8),
               child: ListTile(
                 leading: CircleAvatar(
                   backgroundImage: collector.photoUrl != null ? NetworkImage(collector.photoUrl!) : null,
                   child: collector.photoUrl == null ? const Icon(Icons.person) : null,
                 ),
                 title: Text(collector.name),
                 subtitle: Text('Rank #${index + 1}'),
                 trailing: Text('₹${total.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
                 onTap: isAdmin ? () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => CollectorReportScreen(
                      collectorName: collector.name,
                      collections: collectorItems[collector.id] ?? [],
                    )));
                 } : null,
               ),
             );
          },
        );
      }
    );
  }

  Widget _buildGradientCard(String title, double amount, Color color, {bool isCount = false}) {
    return Card(
      color: color.withOpacity(0.15),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title, style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(isCount ? amount.toInt().toString() : '₹${amount.toStringAsFixed(0)}', style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(Map<DateTime, double> dailyTotalsMap) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    
    List<BarChartGroupData> barGroups = [];
    List<String> labels = [];
    double maxY = 0;
    
    for(int i=6; i>=0; i--) {
       final d = todayStart.subtract(Duration(days: i));
       final val = dailyTotalsMap[d] ?? 0.0;
       if (val > maxY) maxY = val;
       
       barGroups.add(BarChartGroupData(
         x: 6 - i,
         barRods: [
           BarChartRodData(
             toY: val,
             gradient: LinearGradient(
               colors: [Colors.blue.shade300, Colors.blue.shade700],
               begin: Alignment.bottomCenter,
               end: Alignment.topCenter,
             ),
             width: 16,
             borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
           ),
         ],
         showingTooltipIndicators: (6 - i) == _touchedBarIndex ? [0] : [],
       ));
       labels.add('${d.day}/${d.month}');
    }
    if (maxY == 0) maxY = 100;

    return AspectRatio(
      aspectRatio: 1.5,
      child: BarChart(
        BarChartData(
          gridData: const FlGridData(show: false),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  if (value >= 0 && value < 7) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(labels[value.toInt()], style: const TextStyle(fontSize: 10, color: Colors.blueGrey)),
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
          borderData: FlBorderData(show: false),
          maxY: maxY * 1.2,
          barGroups: barGroups,
          barTouchData: BarTouchData(
            enabled: true,
            handleBuiltInTouches: false,
            touchCallback: (FlTouchEvent event, barTouchResponse) {
              if (event.isInterestedForInteractions && barTouchResponse != null && barTouchResponse.spot != null) {
                setState(() {
                  _touchedBarIndex = barTouchResponse.spot!.touchedBarGroupIndex;
                });
              }
            },
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (group) => Colors.blueGrey.shade800,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem(
                  '₹${rod.toY.toStringAsFixed(0)}',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
