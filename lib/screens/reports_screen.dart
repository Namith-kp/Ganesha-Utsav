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
import '../models/spending.dart';
import '../services/spending_service.dart';
import '../utils/spending_dialogs.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> with SingleTickerProviderStateMixin {
  bool _isExporting = false;
  Future<List<Map<String, dynamic>>>? _collectionsFuture;
  Future<List<Map<String, dynamic>>>? _allCollectionsFuture;
  Future<List<Collector>>? _collectorsFuture;
  Future<List<dynamic>>? _combinedCollectionsFuture;
  Future<List<dynamic>>? _combinedSpendingsFuture;
  Future<List<Spending>>? _spendingsFuture;

  TabController? _tabController;
  final ScrollController _collectionsScrollController = ScrollController();
  int _touchedBarIndex = -1;
  String _filterType = 'All Time';
  DateTime? _customDate;
  bool _showCollectorsView = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final FocusNode _searchFocusNode = FocusNode();
  bool _showOnlyDonations = false;

  @override
  void initState() {
    super.initState();
    // Tab controller initialization will be handled in didChangeDependencies
    _loadData();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final profile = ref.read(collectorProfileProvider).value;
    final canSeeTeamData = profile?.canSeeTeamData ?? false;
    final isViewer = profile?.role == 'viewer';
    final hasExtraTabs = canSeeTeamData || isViewer;
    
    int length = 1; // Collections
    if (hasExtraTabs) length += 2; // Team Funds, Spendings

    if (_tabController?.length != length) {
      _tabController?.dispose();
      _tabController = TabController(length: length, vsync: this);
      _tabController?.addListener(() {
        setState(() {}); // Rebuild to update FAB visibility
      });
    }
  }
  
  @override
  void dispose() {
    _tabController?.dispose();
    _collectionsScrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _loadData() {
    final profile = ref.read(collectorProfileProvider).value;
    final filterId = (profile != null && profile.isCollector && !profile.isCoreTeamMember) 
      ? profile.id 
      : null;
    
    _collectionsFuture = ref.read(buildingServiceProvider).getDetailedCollections(filterCollectorId: filterId);
    _allCollectionsFuture = ref.read(buildingServiceProvider).getDetailedCollections(filterCollectorId: null);
    _collectorsFuture = AuthService().getAllCollectors();
    _combinedCollectionsFuture = Future.wait([_collectionsFuture!, _collectorsFuture!]);
    _spendingsFuture = ref.read(spendingServiceProvider).getSpendings();
    _combinedSpendingsFuture = Future.wait([
      _spendingsFuture!,
      _allCollectionsFuture!,
      _collectorsFuture!
    ]);
  }

  Future<void> _confirmDeleteSpending(Spending spending) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Delete Spending', style: GoogleFonts.plusJakartaSans(color: Colors.white)),
        content: Text('Are you sure you want to delete this spending of ₹${spending.amount.toStringAsFixed(0)}?', style: GoogleFonts.plusJakartaSans(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: GoogleFonts.plusJakartaSans(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ref.read(spendingServiceProvider).deleteSpending(spending.id);
        setState(() {
          _loadData();
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Spending deleted successfully.')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
        }
      }
    }
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
          tabs: [
            const Tab(text: 'Collections'),
            if (profile?.canSeeTeamData == true || profile?.role == 'viewer') const Tab(text: 'Team Funds'),
            if (profile?.canSeeTeamData == true || profile?.role == 'viewer') const Tab(text: 'Spendings'),
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
          _buildCollectionsTab(isAdmin, _collectionsScrollController, profile?.role == 'viewer'),
          if (profile?.canSeeTeamData == true || profile?.role == 'viewer') _buildTeamFundsTab(isAdmin, profile?.id, profile?.role == 'viewer'),
          if (profile?.canSeeTeamData == true || profile?.role == 'viewer') _buildSpendingsTab(isAdmin, profile?.id, profile?.name, profile?.role == 'viewer'),
        ],
      ),
      floatingActionButton: _buildFloatingActionButton(isAdmin, profile),
    );
  }

  Widget? _buildFloatingActionButton(bool isAdmin, dynamic profile) {
    if (profile == null) return null;
    final int index = _tabController?.index ?? 0;
    final bool canSeeTeamData = profile.canSeeTeamData ?? false;
    
    if (canSeeTeamData && index == 1 && isAdmin) {
      // Team Funds Tab (Index 1 when canSeeTeamData is true)
      return FloatingActionButton.extended(
        onPressed: _showAddManualMemberDialog,
        icon: const Icon(LucideIcons.userPlus),
        label: const Text('Add Member'),
        backgroundColor: const Color(0xFF3F3D96),
        foregroundColor: Colors.white,
      );
    } else if (canSeeTeamData && index == 2) {
      // Spendings Tab (Index 2 when canSeeTeamData is true)
      return FloatingActionButton.extended(
        onPressed: () async {
          final didSave = await showAddSpendingBottomSheet(
            context,
            ref.read(spendingServiceProvider),
            profile.id,
            profile.name,
          );
          if (didSave == true) {
            setState(() => _loadData());
          }
        },
        icon: const Icon(LucideIcons.plus),
        label: const Text('Add Spending'),
        backgroundColor: const Color(0xFF5E5CE6),
        foregroundColor: Colors.white,
      );
    }
    return null;
  }

  Future<void> _showAddManualMemberDialog() async {
    final TextEditingController nameController = TextEditingController();
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text('Add Team Member', style: GoogleFonts.plusJakartaSans(color: Colors.white)),
          content: TextField(
            controller: nameController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Name',
              labelStyle: const TextStyle(color: Colors.white54),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2))),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.5))),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () {
                if (nameController.text.trim().isNotEmpty) {
                  Navigator.pop(context, true);
                }
              },
              child: Text('Add', style: GoogleFonts.plusJakartaSans(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      try {
        await AuthService().addManualTeamMember(nameController.text.trim());
        setState(() => _loadData());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Member added successfully')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add member: $e')));
        }
      }
    }
  }

  Widget _buildTeamFundsTab(bool isAdmin, String? currentUserId, [bool isViewer = false]) {
    return FutureBuilder<List<Collector>>(
      future: _collectorsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        
        final collectors = snapshot.data ?? [];
        final teamMembers = collectors.where((c) => c.role == 'team_member' || c.isCoreTeamMember).toList();
        
        if (teamMembers.isEmpty) {
          return const Center(child: Text('No team members found.', style: TextStyle(color: Colors.white54)));
        }

        double totalFunds = 0;
        for (var member in teamMembers) {
          if (member.fundStatus == 'paid' && member.fundAmount != null) {
            totalFunds += member.fundAmount!;
          }
        }

        return Column(
          children: [
            if (!isViewer)
              Container(
                padding: const EdgeInsets.all(20),
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF5E5CE6), Color(0xFF3F3D96)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF5E5CE6).withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 6)),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total Team Funds', style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text('₹${totalFunds.toStringAsFixed(0)}', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(LucideIcons.users, color: Colors.white, size: 28),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: teamMembers.length,
                itemBuilder: (context, index) {
                  final member = teamMembers[index];
                  final isPaid = member.fundStatus == 'paid';
                  final amount = member.fundAmount ?? 0.0;
                  
                  return Card(
                    color: const Color(0xFF1E1E1E),
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 1),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      title: Text(member.name, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        isPaid ? 'Paid ₹${amount.toStringAsFixed(0)} via ${member.fundPaymentMethod}' : 'Pending',
                        style: GoogleFonts.plusJakartaSans(
                          color: isPaid ? Colors.green[400] : Colors.orange[400],
                          fontSize: 13,
                        ),
                      ),
                      trailing: isAdmin ? Icon(LucideIcons.edit2, color: Colors.white.withValues(alpha: 0.5), size: 18) : null,
                      onTap: isAdmin ? () => _showTeamFundBottomSheet(context, member, currentUserId) : null,
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSpendingsTab(bool isAdmin, String? currentUserId, String? currentUserName, [bool isViewer = false]) {
    return FutureBuilder(
      future: _combinedSpendingsFuture,
      builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final spendings = (snapshot.data?[0] as List<Spending>?) ?? [];
        final allCollections = (snapshot.data?[1] as List<Map<String, dynamic>>?) ?? [];
        final allCollectors = (snapshot.data?[2] as List<Collector>?) ?? [];

        double totalCollections = 0;
        for (var data in allCollections) {
          if (data['isTeamFund'] == true || data['isCorrection'] == true) continue;
          final Unit unit = data['unit'];
          totalCollections += unit.amount;
        }

        double totalTeamFunds = 0;
        for (var member in allCollectors) {
          if (member.fundStatus == 'paid' && member.fundAmount != null) {
            totalTeamFunds += member.fundAmount!;
          }
        }

        double totalSpendings = 0;
        Map<String, double> spendingsByReason = {};
        for (var spending in spendings) {
          totalSpendings += spending.amount;
          spendingsByReason[spending.reason] = (spendingsByReason[spending.reason] ?? 0) + spending.amount;
        }

        double remainingFunds = (totalCollections + totalTeamFunds) - totalSpendings;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!isViewer) ...[
              Row(
                children: [
                  Expanded(child: _buildMetricCard('Total Collections', '₹${totalCollections.toStringAsFixed(0)}', LucideIcons.trendingUp, Colors.greenAccent)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildMetricCard('Total Funds', '₹${totalTeamFunds.toStringAsFixed(0)}', LucideIcons.users, Colors.blueAccent)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildMetricCard('Total Spendings', '₹${totalSpendings.toStringAsFixed(0)}', LucideIcons.trendingDown, Colors.redAccent)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildMetricCard('Remaining', '₹${remainingFunds.toStringAsFixed(0)}', LucideIcons.wallet, remainingFunds >= 0 ? Colors.greenAccent : Colors.redAccent)),
                ],
              ),
              const SizedBox(height: 24),
            ],
            if (!isViewer && spendings.isNotEmpty && spendingsByReason.isNotEmpty)
              Container(
                height: 200,
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 40,
                          sections: spendingsByReason.entries.map((entry) {
                            final color = Colors.primaries[spendingsByReason.keys.toList().indexOf(entry.key) % Colors.primaries.length];
                            return PieChartSectionData(
                              color: color,
                              value: entry.value,
                              title: '',
                              radius: 25,
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: ListView(
                        children: spendingsByReason.entries.map((entry) {
                          final color = Colors.primaries[spendingsByReason.keys.toList().indexOf(entry.key) % Colors.primaries.length];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    entry.key, 
                                    style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 12),
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text('₹${entry.value.toStringAsFixed(0)}', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            if (spendings.isEmpty)
              const Center(child: Text('No spendings recorded yet.', style: TextStyle(color: Colors.white54)))
            else
              ...spendings.map((spending) => _SpendingCard(
                spending: spending,
                isAdmin: isAdmin,
                onEdit: () async {
                  final didUpdate = await showEditSpendingBottomSheet(context, ref.read(spendingServiceProvider), spending);
                  if (didUpdate == true) {
                    setState(() {
                      _loadData();
                    });
                  }
                },
                onDelete: () => _confirmDeleteSpending(spending),
              )).toList(),
            const SizedBox(height: 80), // Space for FAB
          ],
        );
      },
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(title, style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          Text(value, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _showTeamFundBottomSheet(BuildContext context, Collector member, String? currentUserId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: _TeamFundForm(member: member, currentUserId: currentUserId, onSave: _loadData),
        );
      },
    );
  }

  Widget _buildCollectionsTab(bool isAdmin, ScrollController scrollController, [bool isViewer = false]) {
    return FutureBuilder(
      future: _combinedCollectionsFuture,
      builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        
        final collections = (snapshot.data?[0] as List<Map<String, dynamic>>?) ?? [];
        final collectors = (snapshot.data?[1] as List<Collector>?) ?? [];
        
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

        List<Map<String, dynamic>> baseFilteredCollections = collections.where((item) {
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

        for (var item in baseFilteredCollections) {
          final Unit unit = item['unit'];
          final bool isCorrection = item['isCorrection'] == true;
          totalCollected += unit.amount;
          if (!isCorrection) {
            if (unit.paymentMethod == 'UPI') {
              totalUpi += unit.amount;
            } else {
              totalCash += unit.amount;
            }
          }
          if (unit.collectedAt != null) {
            final d = DateTime(unit.collectedAt!.year, unit.collectedAt!.month, unit.collectedAt!.day);
            if (d == todayStart) {
                todayCollected += unit.amount;
            }
          }
        }

        List<Map<String, dynamic>> displayCollections = List.from(baseFilteredCollections);

        // Apply search filter
        if (_searchQuery.isNotEmpty) {
          displayCollections = displayCollections.where((item) {
            final Unit unit = item['unit'];
            final Building building = item['building'];
            final buildingName = building.name.toLowerCase();
            final unitLabel = unit.unitLabel.toLowerCase();
            return buildingName.contains(_searchQuery) || unitLabel.contains(_searchQuery);
          }).toList();
        }

        // Apply donations filter
        if (_showOnlyDonations) {
          displayCollections = displayCollections.where((item) {
            final Unit unit = item['unit'];
            return unit.donationItem != null && unit.donationItem!.isNotEmpty;
          }).toList();
        }

        Map<DateTime, List<Map<String, dynamic>>> collectionsByDate = {};
        Map<DateTime, Map<String, double>> dateSummaries = {};

        for (var item in displayCollections) {
          final Unit unit = item['unit'];
          final bool isCorrection = item['isCorrection'] == true;
          
          if (unit.collectedAt != null) {
            final d = DateTime(unit.collectedAt!.year, unit.collectedAt!.month, unit.collectedAt!.day);
            collectionsByDate.putIfAbsent(d, () => []).add(item);
            dateSummaries.putIfAbsent(d, () => {'UPI': 0.0, 'Cash': 0.0});
            if (!isCorrection) {
              if (unit.paymentMethod == 'UPI') {
                  dateSummaries[d]!['UPI'] = dateSummaries[d]!['UPI']! + unit.amount;
              } else {
                  dateSummaries[d]!['Cash'] = dateSummaries[d]!['Cash']! + unit.amount;
              }
            }
          }
        }

        
        final sortedDates = collectionsByDate.keys.toList()..sort((a, b) => b.compareTo(a));

        return CustomScrollView(
          controller: scrollController,
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
                           _buildGradientCard('Transactions', baseFilteredCollections.length.toDouble(), AppColors.accent, isCount: true),
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
                        const Text('Collections', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                        Row(
                          children: [
                            if (isAdmin)
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: _showCollectorsView ? const Color(0xFF5E5CE6).withValues(alpha: 0.2) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: _showCollectorsView ? const Color(0xFF5E5CE6) : Colors.white24),
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () => setState(() => _showCollectorsView = !_showCollectorsView),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    child: Row(
                                      children: [
                                        Icon(LucideIcons.users, size: 14, color: _showCollectorsView ? const Color(0xFF5E5CE6) : Colors.white70),
                                        const SizedBox(width: 6),
                                        Text('By Collector', style: TextStyle(color: _showCollectorsView ? const Color(0xFF5E5CE6) : Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            if (!_showCollectorsView)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                                ),
                                child: DropdownButton<String>(
                                  value: _filterType,
                                  dropdownColor: const Color(0xFF1E1E1E),
                                  icon: Icon(LucideIcons.filter, size: 16, color: Colors.blue.shade400),
                                  style: TextStyle(color: Colors.blue.shade300, fontWeight: FontWeight.bold, fontSize: 14),
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
                                         builder: (context, child) {
                                           return Theme(
                                             data: ThemeData.dark().copyWith(
                                               colorScheme: const ColorScheme.dark(
                                                 primary: Color(0xFF5E5CE6),
                                                 onPrimary: Colors.white,
                                                 surface: Color(0xFF1E1E1E),
                                                 onSurface: Colors.white,
                                               ),
                                             ),
                                             child: child!,
                                           );
                                         },
                                       );
                                       if (picked != null) {
                                          setState(() {
                                            _filterType = newValue!;
                                            _customDate = DateTime(picked.year, picked.month, picked.day);
                                          });
                                       }
                                    } else if (newValue != null) {
                                       setState(() {
                                         _filterType = newValue!;
                                       });
                                    }
                                  },
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    if (!_showCollectorsView && _filterType == 'Custom Date' && _customDate != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text('Showing data for ${_customDate!.day}/${_customDate!.month}/${_customDate!.year}', style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w500)),
                      ),
                    // Search bar placed right below the Collections header
                    if (!_showCollectorsView) ...[  
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A2A2A),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 14),
                          onChanged: (value) {
                            setState(() => _searchQuery = value.trim().toLowerCase());
                          },
                          decoration: InputDecoration(
                            hintText: 'Search building or unit name...',
                            hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 14),
                            prefixIcon: const Icon(LucideIcons.search, color: Colors.white38, size: 18),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(LucideIcons.x, color: Colors.white38, size: 18),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    // Donations Toggle
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _showOnlyDonations = false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: !_showOnlyDonations ? AppColors.accent : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Text('All Funds', style: TextStyle(
                                    color: !_showOnlyDonations ? Colors.white : Colors.white54,
                                    fontWeight: FontWeight.bold,
                                  )),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _showOnlyDonations = true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: _showOnlyDonations ? AppColors.accent : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Text('Sponsorships', style: TextStyle(
                                    color: _showOnlyDonations ? Colors.white : Colors.white54,
                                    fontWeight: FontWeight.bold,
                                  )),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            if (displayCollections.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: Text('No collections found.', style: TextStyle(color: Colors.white54))),
                ),
              ),
            if (!_showCollectorsView)
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
                              Text(dateStr, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70)),
                              Row(
                                children: [
                                  if (summary['UPI']! > 0)
                                    Text('UPI: ₹${summary['UPI']!.toStringAsFixed(0)}  ', style: TextStyle(fontSize: 12, color: Colors.purple.shade300, fontWeight: FontWeight.w600)),
                                  if (summary['Cash']! > 0)
                                    Text('Cash: ₹${summary['Cash']!.toStringAsFixed(0)}', style: TextStyle(fontSize: 12, color: Colors.orange.shade300, fontWeight: FontWeight.w600)),
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
                      final bool isCorrection = item['isCorrection'] == true;
                      final date = unit.collectedAt;
                      final timeStr = date != null ? '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}' : 'No time';

                      if (isCorrection) {
                        // ── Delta / correction card — same layout as regular card ──
                        final double delta = (item['delta'] as num?)?.toDouble() ?? unit.amount;
                        final double oldAmt = (item['oldAmount'] as num?)?.toDouble() ?? 0.0;
                        final double newAmt = (item['newAmount'] as num?)?.toDouble() ?? 0.0;
                        final String editorName = item['correctedByName'] as String? ?? 'Admin';
                        final bool isIncrease = delta >= 0;
                        final Color deltaColor = isIncrease ? Colors.greenAccent : Colors.redAccent;
                        final String deltaSign = isIncrease ? '+' : '';
                        // Use the real original unit & building for photo thumbnail and tap dialog
                        final Unit? realUnit = item['realUnit'] as Unit?;
                        final Building realBuilding = (item['realBuilding'] as Building?) ?? building;

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: Card(
                            margin: EdgeInsets.zero,
                            color: const Color(0xFF1E1E1E),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                            ),
                            child: ListTile(
                              leading: (realUnit?.photoBase64 != null)
                                  ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(base64Decode(realUnit!.photoBase64!), width: 50, height: 50, fit: BoxFit.cover))
                                  : const Icon(LucideIcons.imageOff, size: 50, color: Colors.white24),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text('${building.name} - ${unit.unitLabel}',
                                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600)),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(LucideIcons.edit2, size: 10, color: Colors.amber),
                                        const SizedBox(width: 4),
                                        Text('Edited', style: GoogleFonts.plusJakartaSans(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('₹${oldAmt.toStringAsFixed(0)} → ₹${newAmt.toStringAsFixed(0)}',
                                        style: GoogleFonts.plusJakartaSans(color: Colors.white54, fontSize: 12)),
                                    Text('by $editorName · $timeStr',
                                        style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 11)),
                                    if (realUnit?.donationItem != null && realUnit!.donationItem!.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.accent.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text('🎁 ${realUnit.donationItem}', style: GoogleFonts.plusJakartaSans(color: AppColors.accent, fontSize: 10, fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              trailing: Text('$deltaSign₹${delta.abs().toStringAsFixed(0)}',
                                  style: GoogleFonts.plusJakartaSans(color: deltaColor, fontWeight: FontWeight.bold, fontSize: 16)),
                              onTap: () async {
                                // Open the real unit's info dialog (same as clicking a regular card)
                                if (realUnit != null) {
                                  await showUnitAmountForm(context, ref, realBuilding, realUnit, fromReports: true);
                                  setState(() => _loadData());
                                }
                              },
                            ),
                          ),
                        );
                      }


                      // ── Normal collection card ────────────────────────────
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Card(
                          margin: EdgeInsets.zero,
                          color: const Color(0xFF1E1E1E),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          child: ListTile(
                            leading: unit.photoBase64 != null 
                                ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(base64Decode(unit.photoBase64!), width: 50, height: 50, fit: BoxFit.cover))
                                : const Icon(LucideIcons.imageOff, size: 50, color: Colors.white24),
                            title: Text('${building.name} - ${unit.unitLabel}', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600)),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                children: [
                                  Text(timeStr, style: const TextStyle(color: Colors.white54, fontSize: 13)),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: unit.paymentMethod == 'UPI' ? Colors.purple.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(unit.paymentMethod ?? 'Unknown', style: TextStyle(
                                      fontSize: 10,
                                      color: unit.paymentMethod == 'UPI' ? Colors.purple.shade300 : Colors.orange.shade300,
                                      fontWeight: FontWeight.bold,
                                    )),
                                  ),
                                  // Show "edited" indicator on the normal card too if it was corrected
                                  if (unit.originalAmount != null) ...[ 
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text('edited', style: GoogleFonts.plusJakartaSans(color: Colors.amber, fontSize: 9, fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                  if (unit.donationItem != null && unit.donationItem!.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: AppColors.accent.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text('🎁 ${unit.donationItem}', style: GoogleFonts.plusJakartaSans(color: AppColors.accent, fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            trailing: Text('₹${unit.amount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.greenAccent)),
                            onTap: () async {
                              await showUnitAmountForm(context, ref, building, unit, fromReports: true);
                              setState(() => _loadData());
                            },
                          ),
                        ),
                      );

                    },
                    childCount: items.length + 1, // +1 for the header
                  ),
                );
              }),
            if (isAdmin && _showCollectorsView)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    Map<String, double> collectorTotals = {};
                    Map<String, List<Map<String, dynamic>>> collectorItems = {};
                    for (var item in collections) {
                       final Unit unit = item['unit'];
                       if (unit.collectedBy != null) {
                          collectorTotals[unit.collectedBy!] = (collectorTotals[unit.collectedBy!] ?? 0) + unit.amount;
                          collectorItems.putIfAbsent(unit.collectedBy!, () => []).add(item);
                       }
                    }
                    
                    final sortedCollectors = List<Collector>.from(collectors);
                    sortedCollectors.sort((a, b) => (collectorTotals[b.id] ?? 0).compareTo(collectorTotals[a.id] ?? 0));
                    
                    final collector = sortedCollectors[index];
                    final total = collectorTotals[collector.id] ?? 0.0;
                    if (total == 0) return const SizedBox.shrink();

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      color: const Color(0xFF1E1E1E),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundImage: collector.photoUrl != null ? NetworkImage(collector.photoUrl!) : null,
                          child: collector.photoUrl == null ? const Icon(Icons.person) : null,
                        ),
                        title: Text(collector.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        subtitle: Text('Rank #${index + 1}', style: const TextStyle(color: Colors.white54)),
                        trailing: Text('₹${total.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
                        onTap: () {
                           Navigator.push(context, MaterialPageRoute(builder: (_) => CollectorReportScreen(
                             collectorName: collector.name,
                             collections: collectorItems[collector.id] ?? [],
                             isViewer: isViewer,
                           )));
                        },
                      ),
                    );
                  },
                  childCount: collectors.length,
                ),
              ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
          ],
        );
      }
    );
  }

  Widget _buildGradientCard(String title, double amount, Color color, {bool isCount = false}) {
    return Card(
      color: color.withValues(alpha: 0.25),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.5)),
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
              if (event is FlTapDownEvent) {
                 if (barTouchResponse != null && barTouchResponse.spot != null) {
                    setState(() {
                      _touchedBarIndex = barTouchResponse.spot!.touchedBarGroupIndex;
                    });
                 }
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

class _TeamFundForm extends StatefulWidget {
  final Collector member;
  final String? currentUserId;
  final VoidCallback onSave;

  const _TeamFundForm({
    required this.member,
    required this.currentUserId,
    required this.onSave,
  });

  @override
  State<_TeamFundForm> createState() => _TeamFundFormState();
}

class _TeamFundFormState extends State<_TeamFundForm> {
  late TextEditingController _amountController;
  late String _paymentMethod;
  bool _isSaving = false;
  late bool _isPaid;

  @override
  void initState() {
    super.initState();
    _isPaid = widget.member.fundStatus == 'paid';
    _amountController = TextEditingController(text: widget.member.fundAmount?.toStringAsFixed(0) ?? '');
    _paymentMethod = widget.member.fundPaymentMethod ?? 'UPI';
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isPaid && _amountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter an amount')));
      return;
    }

    setState(() => _isSaving = true);
    try {
      await AuthService().updateTeamFundStatus(
        uid: widget.member.id,
        fundStatus: _isPaid ? 'paid' : 'pending',
        fundAmount: _isPaid ? double.tryParse(_amountController.text) : null,
        fundPaymentMethod: _isPaid ? _paymentMethod : null,
        fundCollectedBy: _isPaid ? widget.currentUserId : null,
      );
      if (mounted) {
        widget.onSave();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Updated successfully', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Update ${widget.member.name}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          Row(
            children: [
              Text('Status: ', style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 16)),
              const SizedBox(width: 16),
              ChoiceChip(
                label: const Text('Pending'),
                selected: !_isPaid,
                onSelected: (val) {
                  if (val) setState(() => _isPaid = false);
                },
                selectedColor: Colors.orange.withValues(alpha: 0.2),
                labelStyle: TextStyle(color: !_isPaid ? Colors.orange[400] : Colors.white70),
                backgroundColor: const Color(0xFF2C2C2C),
              ),
              const SizedBox(width: 12),
              ChoiceChip(
                label: const Text('Paid'),
                selected: _isPaid,
                onSelected: (val) {
                  if (val) setState(() => _isPaid = true);
                },
                selectedColor: Colors.green.withValues(alpha: 0.2),
                labelStyle: TextStyle(color: _isPaid ? Colors.green[400] : Colors.white70),
                backgroundColor: const Color(0xFF2C2C2C),
              ),
            ],
          ),
          
          if (_isPaid) ...[
            const SizedBox(height: 24),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              decoration: InputDecoration(
                labelText: 'Amount (₹)',
                labelStyle: const TextStyle(color: Colors.white54),
                prefixIcon: const Icon(Icons.currency_rupee, color: Colors.white54),
                filled: true,
                fillColor: const Color(0xFF2C2C2C),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            
            Text('Payment Method', style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _paymentMethod = 'UPI'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _paymentMethod == 'UPI' ? const Color(0xFF5E5CE6).withValues(alpha: 0.2) : const Color(0xFF2C2C2C),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _paymentMethod == 'UPI' ? const Color(0xFF5E5CE6) : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'UPI',
                        style: GoogleFonts.plusJakartaSans(
                          color: _paymentMethod == 'UPI' ? const Color(0xFF5E5CE6) : Colors.white54,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _paymentMethod = 'Cash'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _paymentMethod == 'Cash' ? Colors.green.withValues(alpha: 0.2) : const Color(0xFF2C2C2C),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _paymentMethod == 'Cash' ? Colors.green : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Cash',
                        style: GoogleFonts.plusJakartaSans(
                          color: _paymentMethod == 'Cash' ? Colors.green : Colors.white54,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _isSaving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5E5CE6),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: _isSaving
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text('Save Update', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _SpendingCard extends StatefulWidget {
  final Spending spending;
  final bool isAdmin;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SpendingCard({
    required this.spending,
    required this.isAdmin,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_SpendingCard> createState() => _SpendingCardState();
}

class _SpendingCardState extends State<_SpendingCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1E1E1E),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            _isExpanded = !_isExpanded;
          });
        },
        onLongPress: widget.isAdmin ? () {
          // If you really want long press to do something specific, you can add it here.
          // Currently, tapping expands the card which shows the delete/edit options.
        } : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(widget.spending.reason, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
                  ),
                  Text('₹${widget.spending.amount.toStringAsFixed(0)}', style: GoogleFonts.plusJakartaSans(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              if (_isExpanded) ...[
                const SizedBox(height: 12),
                const Divider(color: Colors.white12),
                const SizedBox(height: 12),
                Text('By: ${widget.spending.createdByName}', style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 14)),
                if (widget.spending.createdAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Date: ${widget.spending.createdAt!.day.toString().padLeft(2, '0')}/${widget.spending.createdAt!.month.toString().padLeft(2, '0')}/${widget.spending.createdAt!.year} at ${widget.spending.createdAt!.hour.toString().padLeft(2, '0')}:${widget.spending.createdAt!.minute.toString().padLeft(2, '0')}', 
                      style: GoogleFonts.plusJakartaSans(color: Colors.white54, fontSize: 13),
                    ),
                  ),
                if (widget.spending.photoBase64 != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(base64Decode(widget.spending.photoBase64!), width: double.infinity, fit: BoxFit.contain),
                    ),
                  ),
                if (widget.isAdmin) ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        icon: Icon(LucideIcons.edit2, color: Colors.white.withValues(alpha: 0.7), size: 16),
                        label: Text('Edit', style: GoogleFonts.plusJakartaSans(color: Colors.white70)),
                        onPressed: widget.onEdit,
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        icon: Icon(LucideIcons.trash2, color: Colors.redAccent.withValues(alpha: 0.8), size: 16),
                        label: Text('Delete', style: GoogleFonts.plusJakartaSans(color: Colors.redAccent)),
                        onPressed: widget.onDelete,
                      ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
