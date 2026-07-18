import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../screens/login_screen.dart';
import '../screens/setup_profile_screen.dart';
import '../screens/home_screen.dart';
import '../screens/ar_view_screen.dart';
import '../screens/reports_screen.dart';
import '../screens/admin_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final profileState = ref.watch(collectorProfileProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      if (authState.isLoading) return null;

      final isAuth = authState.value != null;
      final isLoggingIn = state.matchedLocation == '/login';
      final isSettingUpProfile = state.matchedLocation == '/setup-profile';

      if (!isAuth) {
        return isLoggingIn ? null : '/login';
      }
      
      // If authState has a value, check profile State
      if (profileState.isLoading) return null;

      final hasProfile = profileState.value != null;

      if (!hasProfile) {
        return isSettingUpProfile ? null : '/setup-profile';
      }

      // User is authenticated and has a profile
      if (isLoggingIn || isSettingUpProfile) {
        return '/';
      }

      return null;
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
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/setup-profile',
        builder: (context, state) => const SetupProfileScreen(),
      ),
      GoRoute(
        path: '/ar',
        builder: (context, state) => const ARViewScreen(),
      ),
      GoRoute(
        path: '/reports',
        builder: (context, state) => const ReportsScreen(),
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminScreen(),
      ),
    ],
  );
});
