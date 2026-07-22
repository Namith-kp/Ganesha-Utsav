import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../providers/dashboard_provider.dart';
import '../models/unit.dart';
import '../models/building.dart';
import '../utils/building_dialogs.dart';
import '../main.dart';
import 'dart:ui';
import 'package:intl/intl.dart';
import 'dart:convert';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  String _getDonorName(Building building, Unit unit) {
    if (building.totalUnits > 1 &&
        unit.unitLabel.isNotEmpty &&
        unit.unitLabel.toLowerCase() != 'main') {
      return unit.unitLabel;
    }
    return building.name;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardData = ref.watch(dashboardDataProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xF50A0D14),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [AppColors.accent, AppColors.accentLight],
                ).createShader(bounds),
                child: Text(
                  'Ganesha Funds Tracker',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    letterSpacing: -0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
      body: dashboardData.when(
        data: (data) => _buildBody(context, ref, data),
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
        error: (err, stack) => Center(
          child: Text('Error: $err', style: const TextStyle(color: Colors.red)),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, DashboardData data) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeroSection(data.totalFunds),
              if (data.sponsors.isNotEmpty) ...[
                const SizedBox(height: 32),
                _buildSectionTitle('Top Sponsors'),
                const SizedBox(height: 16),
                _buildSponsorsList(context, ref, data.sponsors),
              ],
              if (data.topDonations.isNotEmpty) ...[
                const SizedBox(height: 32),
                _buildSectionTitle('Top Contributors'),
                const SizedBox(height: 24),
                _buildPodium(context, ref, data.topDonations),
                const SizedBox(height: 24),
                _buildRankingList(context, ref, data.topDonations),
              ],
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text(
        title,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _buildHeroSection(double totalFunds) {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.accent.withOpacity(0.8),
            AppColors.purple.withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  LucideIcons.trendingUp,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Total Funds Raised',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '₹${totalFunds.toStringAsFixed(0)}',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSponsorsList(
    BuildContext context,
    WidgetRef ref,
    List<Map<String, dynamic>> sponsors,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 600) {
          // Desktop: Wrap to show all sponsors
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 16,
              alignment: WrapAlignment.center,
              children: sponsors.map((item) {
                final Unit unit = item['unit'];
                final Building building = item['building'];
                final donorName = _getDonorName(building, unit);

                return GestureDetector(
                  onTap: () => showUnitAmountForm(
                    context,
                    ref,
                    building,
                    unit,
                    fromReports: true,
                  ),
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      color: AppColors.bgCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.gold.withOpacity(0.5),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.gold.withOpacity(0.05),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: AppColors.gold.withOpacity(0.2),
                          child: const Icon(
                            LucideIcons.gift,
                            color: AppColors.gold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            donorName,
                            style: GoogleFonts.plusJakartaSans(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            unit.donationItem!,
                            style: GoogleFonts.plusJakartaSans(
                              color: AppColors.gold,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        }

        // Mobile: Horizontal scrolling list
        return Stack(
          alignment: Alignment.centerRight,
          children: [
            SizedBox(
              height: 160,
              child: ListView.builder(
                padding: const EdgeInsets.only(left: 16, right: 48),
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: sponsors.length,
                itemBuilder: (context, index) {
                  final item = sponsors[index];
                  final Unit unit = item['unit'];
                  final Building building = item['building'];

                  final donorName = _getDonorName(building, unit);

                  return GestureDetector(
                    onTap: () => showUnitAmountForm(
                      context,
                      ref,
                      building,
                      unit,
                      fromReports: true,
                    ),
                    child: Container(
                      width: 140,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: AppColors.bgCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.gold.withOpacity(0.5),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.gold.withOpacity(0.05),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: AppColors.gold.withOpacity(0.2),
                            child: const Icon(
                              LucideIcons.gift,
                              color: AppColors.gold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              donorName,
                              style: GoogleFonts.plusJakartaSans(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              unit.donationItem!,
                              style: GoogleFonts.plusJakartaSans(
                                color: AppColors.gold,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (sponsors.length > 2)
              Positioned(
                right: 8,
                child: IgnorePointer(
                  child: ClipOval(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.gold.withOpacity(0.12),
                          border: Border.all(
                            color: AppColors.gold.withOpacity(0.35),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.gold.withOpacity(0.15),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          LucideIcons.chevronRight,
                          color: AppColors.gold,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildPodium(
    BuildContext context,
    WidgetRef ref,
    List<Map<String, dynamic>> donations,
  ) {
    if (donations.length < 3) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildPodiumItem(
            context,
            ref,
            donations[1],
            2,
            140,
            AppColors.textSecondary,
          ), // Silver
          const SizedBox(width: 12),
          _buildPodiumItem(
            context,
            ref,
            donations[0],
            1,
            170,
            const Color(0xFFFFD700),
          ), // Gold
          const SizedBox(width: 12),
          _buildPodiumItem(
            context,
            ref,
            donations[2],
            3,
            120,
            const Color(0xFFCD7F32),
          ), // Bronze
        ],
      ),
    );
  }

  Widget _buildPodiumItem(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> item,
    int rank,
    double height,
    Color trophyColor,
  ) {
    final Unit unit = item['unit'];
    final Building building = item['building'];

    final donorName = _getDonorName(building, unit);

    return Expanded(
      child: GestureDetector(
        onTap: () =>
            showUnitAmountForm(context, ref, building, unit, fromReports: true),
        child: Column(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: trophyColor.withOpacity(0.2),
              child: Icon(LucideIcons.user, color: trophyColor),
            ),
            const SizedBox(height: 8),
            Text(
              donorName,
              style: GoogleFonts.plusJakartaSans(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Container(
              height: height,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    trophyColor.withOpacity(0.8),
                    trophyColor.withOpacity(0.3),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Icon(LucideIcons.trophy, color: Colors.white, size: 24),
                  const SizedBox(height: 8),
                  Text(
                    rank.toString(),
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 24,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₹${unit.amount.toStringAsFixed(0)}',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white.withOpacity(0.9),
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
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

  Widget _buildRankingList(
    BuildContext context,
    WidgetRef ref,
    List<Map<String, dynamic>> donations,
  ) {
    final startIndex = donations.length >= 3 ? 3 : 0;
    if (startIndex >= donations.length) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: List.generate(donations.length - startIndex, (index) {
          final actualIndex = startIndex + index;
          final item = donations[actualIndex];
          final Unit unit = item['unit'];
          final Building building = item['building'];

          final donorName = _getDonorName(building, unit);

          final isGoldTier = actualIndex < 10;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isGoldTier
                    ? AppColors.gold.withOpacity(0.5)
                    : AppColors.borderLight,
                width: isGoldTier ? 1.5 : 1.0,
              ),
              boxShadow: isGoldTier
                  ? [
                      BoxShadow(
                        color: AppColors.gold.withOpacity(0.1),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '#${actualIndex + 1}',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 12),
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: isGoldTier
                        ? AppColors.gold.withOpacity(0.2)
                        : AppColors.accent.withOpacity(0.2),
                    child: Icon(
                      isGoldTier ? LucideIcons.gem : LucideIcons.user,
                      color: isGoldTier ? AppColors.gold : AppColors.accent,
                      size: 18,
                    ),
                  ),
                ],
              ),
              title: Text(
                donorName,
                style: GoogleFonts.plusJakartaSans(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                '₹${unit.amount.toStringAsFixed(0)}',
                style: GoogleFonts.plusJakartaSans(
                  color: AppColors.green,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              onTap: () => showUnitAmountForm(
                context,
                ref,
                building,
                unit,
                fromReports: true,
              ),
            ),
          );
        }),
      ),
    );
  }
}
