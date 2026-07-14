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
    return await ref.watch(authServiceProvider).getCollectorProfile(authUser.uid);
  }
  
  return null;
});
