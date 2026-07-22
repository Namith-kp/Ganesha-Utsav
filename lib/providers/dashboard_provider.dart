import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/unit.dart';
import '../models/building.dart';
import 'map_provider.dart';

class DashboardData {
  final List<Map<String, dynamic>> topDonations;
  final List<Map<String, dynamic>> sponsors;
  final double totalFunds;

  DashboardData({
    required this.topDonations,
    required this.sponsors,
    required this.totalFunds,
  });
}

final dashboardDataProvider = FutureProvider.autoDispose<DashboardData>((
  ref,
) async {
  final collections = await ref
      .read(buildingServiceProvider)
      .getDetailedCollections(filterCollectorId: null);

  double totalFunds = 0;

  for (var item in collections) {
    final Unit unit = item['unit'];
    totalFunds += unit.amount;
  }

  // Filter out corrections and team funds for top donations (actual donor ranking)
  var sortedCollections = List<Map<String, dynamic>>.from(
    collections.where((item) {
      final Unit unit = item['unit'];
      final bool isCorrection = item['isCorrection'] == true;
      final Building building = item['building'];

      // Only include real units, exclude delta corrections & team funds
      return !isCorrection && building.id != 'team_funds' && unit.amount > 0;
    }),
  );

  sortedCollections.sort((a, b) {
    final Unit u1 = a['unit'];
    final Unit u2 = b['unit'];
    return u2.amount.compareTo(u1.amount);
  });

  // Extract sponsors (those who donated items, including those with amount = 0)
  var sponsors = List<Map<String, dynamic>>.from(
    collections.where((item) {
      final Unit unit = item['unit'];
      final bool isCorrection = item['isCorrection'] == true;
      final Building building = item['building'];
      return !isCorrection &&
          building.id != 'team_funds' &&
          unit.donationItem != null &&
          unit.donationItem!.trim().isNotEmpty;
    }),
  );

  return DashboardData(
    topDonations: sortedCollections,
    sponsors: sponsors,
    totalFunds: totalFunds,
  );
});
