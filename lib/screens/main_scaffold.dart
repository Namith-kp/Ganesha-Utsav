import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/auth_provider.dart';
import '../main.dart';

class MainScaffold extends ConsumerWidget {
  final Widget child;
  final String location;

  const MainScaffold({
    super.key,
    required this.child,
    required this.location,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collectorAsync = ref.watch(collectorProfileProvider);
    final profile = collectorAsync.value;

    if (profile == null) {
      return const Scaffold(
        backgroundColor: AppColors.bgBase,
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }

    final isAdmin = profile.isAdmin;
    final hasAdminControlAccess = profile.hasAdminControlAccess;
    final isCollector = profile.isCollector;
    final canSeeTeamData = profile.canSeeTeamData;
    final isTeamMember = profile.role == 'team_member';
    final isViewer = profile.role == 'viewer';

    // Build the dynamic list of navigation items
    final items = <_NavItem>[];

    // Everyone gets Map
    items.add(_NavItem(
      icon: LucideIcons.map,
      label: 'Map',
      route: '/',
    ));

    if (isAdmin) {
      items.add(_NavItem(
        icon: LucideIcons.barChart2,
        label: 'Reports',
        route: '/reports',
      ));
      if (hasAdminControlAccess) {
        items.add(_NavItem(
          icon: LucideIcons.shieldAlert,
          label: 'Admin',
          route: '/admin',
        ));
      }
    } else if (isTeamMember) {
      items.add(_NavItem(
        icon: LucideIcons.barChart2,
        label: 'Reports',
        route: '/reports',
      ));
      if (isCollector) {
        items.add(_NavItem(
          icon: LucideIcons.checkSquare,
          label: 'Tasks',
          route: '/tasks',
        ));
        items.add(_NavItem(
          icon: LucideIcons.award,
          label: 'Leaderboard',
          route: '/leaderboard',
        ));
      }
    } else if (isViewer) {
      items.add(_NavItem(
        icon: LucideIcons.barChart2,
        label: 'Reports',
        route: '/reports',
      ));
    } else if (isCollector) {
      items.add(_NavItem(
        icon: LucideIcons.checkSquare,
        label: 'Tasks',
        route: '/tasks',
      ));
      items.add(_NavItem(
        icon: LucideIcons.award,
        label: 'Leaderboard',
        route: '/leaderboard',
      ));
    }

    // Everyone gets Profile
    items.add(_NavItem(
      icon: LucideIcons.user,
      label: 'Profile',
      route: '/profile',
    ));

    // Determine current index based on route without matching "/" against every path.
    int currentIndex = items.indexWhere((item) {
      if (item.route == '/') {
        return location == '/';
      }
      return location == item.route || location.startsWith('${item.route}/');
    });

    if (currentIndex == -1) {
      currentIndex = 0;
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border, width: 1)),
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
                return const IconThemeData(color: AppColors.accent, size: 24);
              }
              return const IconThemeData(color: AppColors.textSecondary, size: 24);
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
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final String route;

  _NavItem({
    required this.icon,
    required this.label,
    required this.route,
  });
}
