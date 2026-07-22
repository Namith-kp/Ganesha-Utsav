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
      } else if (_firebaseAuth.currentUser != null && _firebaseAuth.currentUser!.uid == uid) {
        // Auto-create profile if it doesn't exist for the logged-in user
        final user = _firebaseAuth.currentUser!;
        final isAnonymous = user.isAnonymous;
        
        final newData = {
          'name': isAnonymous ? 'Web Guest' : (user.displayName ?? 'Unknown'),
          'email': user.email ?? '',
          'photoUrl': user.photoURL,
          'role': 'viewer',
          'isCoreTeamMember': false,
          'canAccessAdminControl': false,
        };
        
        await _firestore.collection('collectors').doc(uid).set(newData);
        return Collector.fromMap(newData, uid);
      }
    } catch (e) {
      print("Error fetching collector profile: $e");
    }
    return null;
  }

  // Stream all collectors for Admin
  Stream<List<Collector>> streamAllCollectors() {
    return _firestore.collection('collectors').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => Collector.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  // Future all collectors (Cache First)
  Future<List<Collector>> getAllCollectors() async {
    try {
      final query = _firestore.collection('collectors');
      QuerySnapshot snapshot;
      try {
        snapshot = await query.get(const GetOptions(source: Source.cache));
        if (snapshot.docs.isNotEmpty) {
          query.get(const GetOptions(source: Source.server)); // update cache in bg
        } else {
          snapshot = await query.get();
        }
      } catch (_) {
        snapshot = await query.get();
      }
      return snapshot.docs
          .map((doc) => Collector.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    } catch (e) {
      print('Error fetching collectors: $e');
      return [];
    }
  }

  // Sign in with Google
  Future<auth.UserCredential?> signInWithGoogle() async {
    try {
      final googleUser = await GoogleSignIn(
        clientId:
            '442465747713-9viehhaefh9dfrsip7kbkc1h246nk36q.apps.googleusercontent.com',
      ).signIn();
      if (googleUser == null) return null; // user cancelled

      final googleAuth = await googleUser.authentication;
      final credential = auth.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _firebaseAuth.signInWithCredential(
        credential,
      );

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
            'canAccessAdminControl': false,
          });
        }
      }
      return userCredential;
    } catch (e) {
      print("Google Sign in error: $e");
      rethrow;
    }
  }

  // Sign in as Guest (Web Only)
  Future<auth.UserCredential?> signInAsGuest() async {
    try {
      final userCredential = await _firebaseAuth.signInAnonymously();

      if (userCredential.user != null) {
        final uid = userCredential.user!.uid;
        final doc = await _firestore.collection('collectors').doc(uid).get();
        if (!doc.exists) {
          await _firestore.collection('collectors').doc(uid).set({
            'name': 'Web Guest',
            'email': '',
            'photoUrl': null,
            'role': 'viewer', // Default role for guests
            'isCoreTeamMember': false,
            'canAccessAdminControl': false,
          });
        }
      }
      return userCredential;
    } catch (e) {
      print("Guest Sign in error: $e");
      rethrow;
    }
  }

  // Update a user's role (Admin only)
  Future<void> updateCollectorRole(String uid, String role) async {
    final Map<String, dynamic> updates = {'role': role};
    if (role != 'collector') {
      updates['isCoreTeamMember'] = false;
    }
    if (role != 'admin') {
      updates['canAccessAdminControl'] = false;
    }
    await _firestore.collection('collectors').doc(uid).update(updates);
  }

  // Update whether an admin can access the admin control section
  Future<void> updateAdminControlAccess(String uid, bool enabled) async {
    await _firestore.collection('collectors').doc(uid).update({
      'canAccessAdminControl': enabled,
    });
  }

  // Update core team member status
  Future<void> updateCollectorTeamStatus(
    String uid,
    bool isCoreTeamMember,
  ) async {
    await _firestore.collection('collectors').doc(uid).update({
      'isCoreTeamMember': isCoreTeamMember,
    });
  }

  // Add a manual team member (for users who haven't installed the app)
  Future<void> addManualTeamMember(String name) async {
    await _firestore.collection('collectors').add({
      'name': name,
      'email': '',
      'photoUrl': null,
      'role': 'team_member',
      'isCoreTeamMember': true,
      'isManualEntry': true,
      'fundStatus': 'pending',
    });
  }

  // Update team fund status (Admin only)
  Future<void> updateTeamFundStatus({
    required String uid,
    required String fundStatus,
    double? fundAmount,
    String? fundPaymentMethod,
    String? fundCollectedBy,
  }) async {
    final updates = {
      'fundStatus': fundStatus,
      'fundAmount': fundAmount,
      'fundPaymentMethod': fundPaymentMethod,
      'fundCollectedAt': fundStatus == 'paid'
          ? FieldValue.serverTimestamp()
          : null,
      'fundCollectedBy': fundCollectedBy,
    };
    await _firestore.collection('collectors').doc(uid).update(updates);
  }

  // Sign out
  Future<void> signOut() async {
    await GoogleSignIn(
      clientId:
          '442465747713-9viehhaefh9dfrsip7kbkc1h246nk36q.apps.googleusercontent.com',
    ).signOut();
    await _firebaseAuth.signOut();
  }
}
