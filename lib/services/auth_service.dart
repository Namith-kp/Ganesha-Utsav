import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/collector.dart';

class AuthService {
  final auth.FirebaseAuth _firebaseAuth = auth.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

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

  // Sign in with Google
  Future<auth.UserCredential?> signInWithGoogle() async {
    try {
      // Trigger the authentication flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return null; // The user canceled the sign-in
      }

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // Create a new credential
      final auth.OAuthCredential credential = auth.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Once signed in, return the UserCredential
      return await _firebaseAuth.signInWithCredential(credential);
    } catch (e) {
      print("Google Sign-In error: $e");
      rethrow;
    }
  }

  // Complete profile for new users
  Future<void> completeProfile(String uid, String name, String email) async {
    await _firestore.collection('collectors').doc(uid).set({
      'name': name,
      'email': email,
      'role': 'collector', // default role
    });
  }

  // Update a user's role (Admin only)
  Future<void> updateCollectorRole(String uid, String role) async {
    await _firestore.collection('collectors').doc(uid).update({
      'role': role,
    });
  }

  // Sign out
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _firebaseAuth.signOut();
  }
}
