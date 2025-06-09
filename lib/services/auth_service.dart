import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  // Create a singleton instance
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  // Firebase Auth instance
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Google Sign In instance with updated configuration
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId:
        '103978403761-ejgfbeda55lnj04m5j3dkbbh23n9pdnq.apps.googleusercontent.com',
    scopes: [
      'email',
      'profile',
    ],
    // Add this to help with authentication issues
    signInOption: SignInOption.standard,
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

  // Sign in with Google - Updated with better error handling
  Future<UserCredential?> signInWithGoogle() async {
    try {
      // Sign out from any previous session to ensure clean state
      await _googleSignIn.signOut();

      // Begin interactive sign in process
      final GoogleSignInAccount? gUser = await _googleSignIn.signIn();

      // If the user cancels the sign-in process, return null
      if (gUser == null) {
        return null;
      }

      // Obtain auth details from request
      final GoogleSignInAuthentication gAuth = await gUser.authentication;

      // Verify we have the required tokens
      if (gAuth.accessToken == null || gAuth.idToken == null) {
        throw Exception('Failed to obtain Google authentication tokens');
      }

      // Create new credential
      final credential = GoogleAuthProvider.credential(
        accessToken: gAuth.accessToken,
        idToken: gAuth.idToken,
      );

      // Sign in with credential
      return await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      // Handle specific Firebase Auth errors
      switch (e.code) {
        case 'account-exists-with-different-credential':
          throw Exception(
              'An account already exists with a different sign-in method.');
        case 'invalid-credential':
          throw Exception('The credential is invalid or has expired.');
        case 'operation-not-allowed':
          throw Exception('Google sign-in is not enabled.');
        case 'user-disabled':
          throw Exception('This user account has been disabled.');
        default:
          throw Exception('Google sign-in failed: ${e.message}');
      }
    } catch (e) {
      // For the specific time synchronization error
      if (e.toString().contains('600 seconds') ||
          e.toString().contains('time is more than') ||
          e.toString().contains('org.openid.appauth.general')) {
        throw Exception(
            'Authentication failed due to time synchronization. Please check your device time and try again.');
      }
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
