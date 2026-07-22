import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  try {
    final cred = await FirebaseAuth.instance.signInAnonymously();
    print("SUCCESS Anonymous Auth UID: ${cred.user?.uid}");
  } catch (e) {
    print("FAILED Anonymous Auth: $e");
  }
}
