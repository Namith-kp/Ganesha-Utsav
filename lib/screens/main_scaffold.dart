import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/auth_provider.dart';
import '../main.dart';
import '../utils/add_tag_notifier.dart';
import '../utils/building_dialogs.dart';

class MainScaffold extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;
  final String location;

  const MainScaffold({super.key, required this.navigationShell, required this.location});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collectorAsync = ref.watch(collectorProfileProvider);
    final profile = collectorAsync.value;

    if (collectorAsync.isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.bgBase,
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }

    if (profile == null) {
      return Scaffold(
        backgroundColor: AppColors.bgBase,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Failed to load profile. Please sign out and try again.', style: TextStyle(color: Colors.white)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  ref.read(authServiceProvider).signOut();
                },
                child: const Text('Sign Out'),
              )
            ],
          ),
        ),
      );
    }

    // Build the dynamic list of navigation items
    final items = <_NavItem>[];

    // Everyone gets Dashboard
    items.add(_NavItem(icon: LucideIcons.home, label: 'Home', route: '/'));

    // Everyone gets Map
    items.add(_NavItem(icon: LucideIcons.map, label: 'Map', route: '/map'));

    final bool canSeeReports = profile.isAdmin ||
        profile.role == 'team_member' ||
        profile.role == 'viewer' ||
        (profile.canSeeTeamData == true);

    if (canSeeReports) {
      items.add(
        _NavItem(
          icon: LucideIcons.barChart2,
          label: 'Reports',
          route: '/reports',
        ),
      );
    }

    // Everyone gets Profile
    items.add(
      _NavItem(icon: LucideIcons.user, label: 'Profile', route: '/profile'),
    );

    // Determine current index based on route by subscribing to GoRouter state changes
    final location = GoRouterState.of(context).matchedLocation;

    int currentIndex = items.indexWhere((item) {
      if (item.route == '/') {
        return location == '/';
      }
      return location == item.route || location.startsWith('${item.route}/');
    });

    if (currentIndex == -1) {
      currentIndex = 0;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 800) {
          // Desktop / Web Wide Layout
          return Scaffold(
            backgroundColor: AppColors.bgBase,
            body: Row(
              children: [
                NavigationRail(
                  backgroundColor: AppColors.bgCard,
                  indicatorColor: AppColors.accent.withValues(alpha: 0.2),
                  selectedIndex: currentIndex,
                  onDestinationSelected: (index) {
                    context.go(items[index].route);
                  },
                  labelType: NavigationRailLabelType.all,
                  selectedLabelTextStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accent,
                  ),
                  unselectedLabelTextStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                  selectedIconTheme: const IconThemeData(
                    color: AppColors.accent,
                    size: 24,
                  ),
                  unselectedIconTheme: const IconThemeData(
                    color: AppColors.textSecondary,
                    size: 24,
                  ),
                  destinations: items.map((item) {
                    return NavigationRailDestination(
                      icon: Icon(item.icon),
                      label: Text(item.label),
                    );
                  }).toList(),
                ),
                const VerticalDivider(
                  thickness: 1,
                  width: 1,
                  color: AppColors.border,
                ),
                Expanded(child: navigationShell),
              ],
            ),
          );
        }

        // Mobile Layout
        return Scaffold(
          body: navigationShell,
          bottomNavigationBar: _buildBottomNav(
            context,
            ref,
            items,
            currentIndex,
            profile.canCreate,
          ),
        );
      },
    );
  }

  Widget _buildBottomNav(
    BuildContext context,
    WidgetRef ref,
    List<_NavItem> items,
    int currentIndex,
    bool canCreate,
  ) {
    // Split items around center button if canCreate
    final leftItems = canCreate
        ? items.sublist(0, (items.length / 2).floor())
        : items;
    final rightItems = canCreate
        ? items.sublist((items.length / 2).floor())
        : <_NavItem>[];

    return ValueListenableBuilder<bool>(
      valueListenable: HomeScreenAddTagNotifier.isPickingLocation,
      builder: (context, rawIsPicking, child) {
        // Location picking active state is only active when currently on /map
        final isPicking = rawIsPicking && location == '/map';

        Widget buildNavItem(_NavItem item, int index) {
          final isSelected = !isPicking && items.indexOf(item) == currentIndex;
          return Expanded(
            child: InkWell(
              onTap: () {
                HomeScreenAddTagNotifier.cancelPicking();
                context.go(item.route);
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    item.icon,
                    size: 24,
                    color: isSelected ? AppColors.accent : AppColors.textSecondary,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.label,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                      color:
                          isSelected ? AppColors.accent : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final isAddTagSelected = isPicking;

        return Container(
          decoration: const BoxDecoration(
            color: AppColors.bgCard,
            border: Border(top: BorderSide(color: AppColors.border, width: 1)),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 64,
              child: canCreate
                  ? Row(
                      children: [
                        ...leftItems.map(
                          (item) => buildNavItem(item, items.indexOf(item)),
                        ),
                        // Center Add Tag button
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              showAddTagDetailsDialog(context, ref);
                            },
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  isAddTagSelected
                                      ? Icons.add_location_alt_rounded
                                      : Icons.add_location_alt_outlined,
                                  size: 24,
                                  color: isAddTagSelected
                                      ? AppColors.accent
                                      : AppColors.textSecondary,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Add Tag',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    fontWeight: isAddTagSelected
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: isAddTagSelected
                                        ? AppColors.accent
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        ...rightItems.map(
                          (item) => buildNavItem(item, items.indexOf(item)),
                        ),
                      ],
                    )
                  : Row(
                      children: items
                          .map(
                            (item) => buildNavItem(item, items.indexOf(item)),
                          )
                          .toList(),
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final String route;

  _NavItem({required this.icon, required this.label, required this.route});
}
