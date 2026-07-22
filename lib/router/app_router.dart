import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../screens/login_screen.dart';
import '../screens/home_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/reports_screen.dart';
import '../screens/admin_screen.dart';
import '../screens/main_scaffold.dart';
import '../screens/tasks_screen.dart';
import '../screens/leaderboard_screen.dart';
import '../screens/profile_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _shellNavigatorKey =
    GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  // Keep one router for the lifetime of the app. Recreating GoRouter when
  // Firebase/profile data resolves can briefly detach the shell's child route.
  final router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final collectorProfile = ref.read(collectorProfileProvider);

      // If the auth state is still loading, don't redirect yet
      if (authState.isLoading) return null;

      final isAuth = authState.value != null;
      final isLoggingIn = state.matchedLocation == '/login';

      if (!isAuth) {
        return isLoggingIn ? null : '/login';
      }

      if (isLoggingIn) {
        return '/';
      }

      // Role-based guards
      final profile = collectorProfile.value;
      if (profile != null) {
        final path = state.matchedLocation;

        if (path == '/admin' && !profile.hasAdminControlAccess) return '/';

        // Only admins, team members, and viewers get reports
        if (path == '/reports') {
          bool canSeeReports =
              profile.isAdmin ||
              profile.role == 'team_member' ||
              profile.role == 'viewer' ||
              profile.canSeeTeamData;
          if (!canSeeReports) return '/';
        }

        // Only collectors get tasks and leaderboard
        if ((path == '/tasks' || path == '/leaderboard') &&
            !profile.isCollector) {
          return '/';
        }
      }

      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainScaffold(
            location: state.matchedLocation,
            navigationShell: navigationShell,
          );
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/map',
                builder: (context, state) {
                  final lat = double.tryParse(state.uri.queryParameters['lat'] ?? '');
                  final lng = double.tryParse(state.uri.queryParameters['lng'] ?? '');
                  return HomeScreen(initialLat: lat, initialLng: lng);
                },
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/reports',
                builder: (context, state) => const ReportsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/tasks',
                builder: (context, state) => const TasksScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/leaderboard',
                builder: (context, state) => const LeaderboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/admin',
                builder: (context, state) => const AdminScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  // Re-evaluate access rules as auth/profile data changes without replacing the
  // Navigator or the currently displayed route.
  ref.listen(authStateProvider, (_, __) => router.refresh());
  ref.listen(collectorProfileProvider, (_, __) => router.refresh());
  ref.onDispose(router.dispose);

  return router;
});
