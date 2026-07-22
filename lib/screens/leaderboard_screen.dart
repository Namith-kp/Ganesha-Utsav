import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../providers/auth_provider.dart';
import '../providers/map_provider.dart';
import '../models/collector.dart';
import '../models/unit.dart';
import '../main.dart';
import 'collector_report_screen.dart';

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  Future<List<Map<String, dynamic>>>? _allCollectionsFuture;
  Future<List<Collector>>? _collectorsFuture;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    _allCollectionsFuture = ref
        .read(buildingServiceProvider)
        .getDetailedCollections(filterCollectorId: null);
    _collectorsFuture = ref.read(authServiceProvider).getAllCollectors();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(collectorProfileProvider).value;
    final isAdmin = profile?.isAdmin ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Leaderboard'),
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
      body: FutureBuilder(
        future: Future.wait([_allCollectionsFuture!, _collectorsFuture!]),
        builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting)
            return const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            );
          if (snapshot.hasError)
            return Center(
              child: Text(
                'Error: \${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );

          final collections = snapshot.data![0] as List<Map<String, dynamic>>;
          final collectors = snapshot.data![1] as List<Collector>;

          Map<String, double> collectorTotals = {};
          Map<String, List<Map<String, dynamic>>> collectorItems = {};

          for (var item in collections) {
            final Unit unit = item['unit'];
            if (unit.collectedBy != null) {
              collectorTotals[unit.collectedBy!] =
                  (collectorTotals[unit.collectedBy!] ?? 0) + unit.amount;
              collectorItems.putIfAbsent(unit.collectedBy!, () => []).add(item);
            }
          }

          collectors.sort(
            (a, b) => (collectorTotals[b.id] ?? 0).compareTo(
              collectorTotals[a.id] ?? 0,
            ),
          );

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: collectors.length,
                itemBuilder: (context, index) {
                  final collector = collectors[index];
                  final total = collectorTotals[collector.id] ?? 0.0;
                  if (total == 0) return const SizedBox.shrink();

                  return Card(
                    color: AppColors.bgCard,
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: AppColors.border),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.accent.withValues(
                          alpha: 0.2,
                        ),
                        foregroundColor: AppColors.accent,
                        backgroundImage: collector.photoUrl != null
                            ? NetworkImage(collector.photoUrl!)
                            : null,
                        child: collector.photoUrl == null
                            ? const Icon(LucideIcons.user)
                            : null,
                      ),
                      title: Text(
                        collector.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        'Rank #${index + 1}',
                        style: GoogleFonts.plusJakartaSans(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      trailing: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 120),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            '₹${total.toStringAsFixed(0)}',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: AppColors.green,
                            ),
                          ),
                        ),
                      ),
                      onTap: isAdmin
                          ? () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CollectorReportScreen(
                                    collectorName: collector.name,
                                    collections:
                                        collectorItems[collector.id] ?? [],
                                  ),
                                ),
                              );
                            }
                          : null,
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
