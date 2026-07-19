import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../screens/login_screen.dart';
import '../screens/home_screen.dart';
import '../screens/ar_view_screen.dart';
import '../screens/reports_screen.dart';
import '../screens/admin_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final collectorProfile = ref.watch(collectorProfileProvider);

  return GoRouter(
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
        if (path == '/reports' && !profile.canAccessReports) return '/';
        if (path == '/ar' && !profile.canAccessAR) return '/';
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
