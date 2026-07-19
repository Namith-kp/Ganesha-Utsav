import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/collector.dart';
class AuthService {
  final auth.FirebaseAuth _firebaseAuth = auth.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Listen to auth state changes
  Stream<auth.User?> get authStateChanges => _firebaseAuth.authStateChanges();

  // Get current user details from Firestore
  Future<Collector?> getCollectorProfile(String uid) async {
    try {
      final doc = await _firestore.collection('collectors').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        return Collector.fromMap(doc.data()!, doc.id);
      }
    } catch (e) {
      print("Error fetching collector profile: $e");
    }
    return null;
  }

  // Stream all collectors for Admin
  Stream<List<Collector>> streamAllCollectors() {
    return _firestore.collection('collectors').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => Collector.fromMap(doc.data(), doc.id)).toList();
    });
  }

  // Future all collectors
  Future<List<Collector>> getAllCollectors() async {
    final snapshot = await _firestore.collection('collectors').get();
    return snapshot.docs.map((doc) => Collector.fromMap(doc.data(), doc.id)).toList();
  }

  // Sign in with Google
  Future<auth.UserCredential?> signInWithGoogle() async {
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return null; // user cancelled

      final googleAuth = await googleUser.authentication;
      final credential = auth.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _firebaseAuth.signInWithCredential(credential);
      
      // Create Firestore profile only on first sign-in
      if (userCredential.user != null) {
        final uid = userCredential.user!.uid;
        final doc = await _firestore.collection('collectors').doc(uid).get();
        if (!doc.exists) {
          await _firestore.collection('collectors').doc(uid).set({
            'name': userCredential.user!.displayName ?? 'Unknown',
            'email': userCredential.user!.email ?? '',
            'photoUrl': userCredential.user!.photoURL,
            'role': 'viewer', // Default role for new signups
            'isCoreTeamMember': false,
          });
        }
      }
      return userCredential;
    } catch (e) {
      print("Google Sign in error: $e");
      rethrow;
    }
  }

  // Update a user's role (Admin only)
  Future<void> updateCollectorRole(String uid, String role) async {
    final Map<String, dynamic> updates = {'role': role};
    if (role != 'collector') {
      updates['isCoreTeamMember'] = false;
    }
    await _firestore.collection('collectors').doc(uid).update(updates);
  }

  // Update core team member status
  Future<void> updateCollectorTeamStatus(String uid, bool isCoreTeamMember) async {
    await _firestore.collection('collectors').doc(uid).update({
      'isCoreTeamMember': isCoreTeamMember,
    });
  }

  // Sign out
  Future<void> signOut() async {
    await GoogleSignIn().signOut();
    await _firebaseAuth.signOut();
  }
}
