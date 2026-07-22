import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import '../services/auth_service.dart';
import '../models/collector.dart';

// Provider for the AuthService
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

// StreamProvider that listens to Firebase Auth state changes
final authStateProvider = StreamProvider<auth.User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

// FutureProvider that fetches the Collector profile based on the current auth state
final collectorProfileProvider = FutureProvider<Collector?>((ref) async {
  final authUser = ref.watch(authStateProvider).value;

  if (authUser != null) {
    final profile = await ref
        .watch(authServiceProvider)
        .getCollectorProfile(authUser.uid);
    if (profile != null) {
      return profile;
    } else {
      // If profile doesn't exist (e.g. guest doc creation failed), return a fallback
      return Collector(
        id: authUser.uid,
        name: 'Guest Viewer',
        phone: '',
        role: 'viewer',
      );
    }
  }

  return null;
});
