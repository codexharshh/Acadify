import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  // ── Current user — builds UserModel from Firebase Auth ───────────
  UserModel? get currentUser {
    final u = _auth.currentUser;
    if (u == null) return null;
    // Prefer displayName; fall back to the email prefix.
    final name = u.displayName ?? u.email?.split('@')[0] ?? 'Student';
    return UserModel(
      uid: u.uid,
      username: name,
      email: u.email ?? '',
    );
  }

  // ── Login ─────────────────────────────────────────────────────────
  Future<void> login(String email, String password) async {
    final result = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    // Sync displayName from Firestore so the greeting shows the
    // correct username even after reinstall.
    final doc = await _db.collection('users').doc(result.user!.uid).get();
    final data = doc.data();
    if (data != null && data['username'] != null) {
      await result.user!.updateDisplayName(data['username']);
    }
  }

  // ── Sign Up ───────────────────────────────────────────────────────
  Future<void> signUp(String email, String password, String name) async {
    final result = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    // Persist the display name in Firebase Auth.
    await result.user!.updateDisplayName(name);

    // Create the user document in Firestore with default values.
    await _db.collection('users').doc(result.user!.uid).set({
      'username': name,
      'email': email.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'studyStreakDays': 0,
      'longestStreak': 0,
      'totalStudyDays': 0,
      'lastCheckinDate': '',
      'todayStudiedHours': 0,
      'todayGoalHours': 3,
      'lastResetDate': '',
    });
  }

  // ── Logout ────────────────────────────────────────────────────────
  Future<void> logout() async {
    await _auth.signOut();
  }
}
