import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/auth_provider.dart';
import '../main.dart';

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
                  indicatorColor: AppColors.accent.withOpacity(0.2),
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
          bottomNavigationBar: Container(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: AppColors.border, width: 1),
              ),
            ),
            child: NavigationBarTheme(
              data: NavigationBarThemeData(
                labelTextStyle: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent,
                    );
                  }
                  return GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  );
                }),
                iconTheme: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return const IconThemeData(
                      color: AppColors.accent,
                      size: 24,
                    );
                  }
                  return const IconThemeData(
                    color: AppColors.textSecondary,
                    size: 24,
                  );
                }),
              ),
              child: NavigationBar(
                backgroundColor: AppColors.bgCard,
                indicatorColor: AppColors.accent.withOpacity(0.2),
                selectedIndex: currentIndex,
                onDestinationSelected: (index) {
                  context.go(items[index].route);
                },
                destinations: items.map((item) {
                  return NavigationDestination(
                    icon: Icon(item.icon),
                    label: item.label,
                  );
                }).toList(),
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
