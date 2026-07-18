import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:cloud_firestore/cloud_firestore.dart';
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

  // Sign up with email, password, and name
  Future<auth.UserCredential?> signUp(String email, String password, String name) async {
    try {
      final credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      if (credential.user != null) {
        await _firestore.collection('collectors').doc(credential.user!.uid).set({
          'name': name,
          'email': email,
          'role': 'collector', // default role
        });
      }
      return credential;
    } catch (e) {
      print("Sign up error: $e");
      rethrow;
    }
  }

  // Sign in with email and password
  Future<auth.UserCredential?> signIn(String email, String password) async {
    try {
      return await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      print("Login error: $e");
      rethrow;
    }
  }

  // Update a user's role (Admin only)
  Future<void> updateCollectorRole(String uid, String role) async {
    await _firestore.collection('collectors').doc(uid).update({
      'role': role,
    });
  }

  // Sign out
  Future<void> signOut() async {
    await _firebaseAuth.signOut();
  }
}
