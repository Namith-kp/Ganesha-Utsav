import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../screens/login_screen.dart';
import '../screens/home_screen.dart';
import '../screens/reports_screen.dart';
import '../screens/admin_screen.dart';
import '../screens/main_scaffold.dart';
import '../screens/tasks_screen.dart';
import '../screens/leaderboard_screen.dart';
import '../screens/profile_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _shellNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final collectorProfile = ref.watch(collectorProfileProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    redirect: (context, state) {
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
        
        if (path == '/admin' && !profile.isAdmin) return '/';
        
        // Only admins, team members, and viewers get reports
        if (path == '/reports') {
           bool canSeeReports = profile.isAdmin || 
                                profile.role == 'team_member' || 
                                profile.role == 'viewer' || 
                                profile.canSeeTeamData;
           if (!canSeeReports) return '/';
        }
        
        // Only collectors get tasks and leaderboard
        if ((path == '/tasks' || path == '/leaderboard') && !profile.isCollector) {
           return '/';
        }
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) {
          return MainScaffold(child: child);
        },
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) {
              final lat = double.tryParse(state.uri.queryParameters['lat'] ?? '');
              final lng = double.tryParse(state.uri.queryParameters['lng'] ?? '');
              return HomeScreen(initialLat: lat, initialLng: lng);
            },
          ),
          GoRoute(
            path: '/reports',
            builder: (context, state) => const ReportsScreen(),
          ),
          GoRoute(
            path: '/tasks',
            builder: (context, state) => const TasksScreen(),
          ),
          GoRoute(
            path: '/leaderboard',
            builder: (context, state) => const LeaderboardScreen(),
          ),
          GoRoute(
            path: '/admin',
            builder: (context, state) => const AdminScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),
    ],
  );
});
