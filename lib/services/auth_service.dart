import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  // Create a singleton instance
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  // Firebase Auth instance
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Google Sign In instance
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    // Use serverClientId for Android, as suggested by the plugin warning
    serverClientId:
        '103978403761-qns448am3bbr0qe7dibte8ejn0gcjr59.apps.googleusercontent.com',
  );

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Stream of auth changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign in with email and password
  Future<UserCredential> signInWithEmailAndPassword(
      String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (e) {
 
      rethrow;
    }
  }

  // Register with email and password
  Future<UserCredential> registerWithEmailAndPassword(
      String email, String password) async {
    try {
      return await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (e) {
 
      rethrow;
    }
  }

  // Sign in with Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      // Begin interactive sign in process
      final GoogleSignInAccount? gUser = await _googleSignIn.signIn();

      // If the user cancels the sign-in process, return null
      if (gUser == null) {
        return null;
      }

      // Obtain auth details from request
      final GoogleSignInAuthentication gAuth = await gUser.authentication;

      // Create new credential
      final credential = GoogleAuthProvider.credential(
        accessToken: gAuth.accessToken,
        idToken: gAuth.idToken,
      );

      // Sign in with credential
      return await _auth.signInWithCredential(credential);
    } catch (e) {
 
      rethrow;
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      // Sign out of Google if signed in with Google
      await _googleSignIn.signOut();
      // Sign out of Firebase
      await _auth.signOut();
    } catch (e) {
 
      rethrow;
    }
  }

  // Password reset
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } catch (e) {
 
      rethrow;
    }
  }

  // Update user profile
  Future<void> updateProfile({String? displayName, String? photoURL}) async {
    try {
      await _auth.currentUser?.updateDisplayName(displayName);
      await _auth.currentUser?.updatePhotoURL(photoURL);
    } catch (e) {
 
      rethrow;
    }
  }

  // Get user ID
  String? getUserId() {
    return _auth.currentUser?.uid;
  }

  // Check if user is logged in
  bool isUserLoggedIn() {
    return _auth.currentUser != null;
  }
}
