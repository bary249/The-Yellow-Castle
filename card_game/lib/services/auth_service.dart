import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Handles user authentication and profile management
class AuthService {
  FirebaseAuth? _auth;
  FirebaseFirestore? _firestore;

  AuthService() {
    try {
      _auth = FirebaseAuth.instance;
      _firestore = FirebaseFirestore.instance;
    } catch (e) {
      print('AuthService: Firebase not available ($e)');
    }
  }

  /// Get current user
  User? get currentUser => _auth?.currentUser;

  /// Check if user is signed in
  bool get isSignedIn => currentUser != null;

  /// Stream of auth state changes
  Stream<User?> get authStateChanges =>
      _auth?.authStateChanges() ?? Stream.value(null);

  /// Sign in anonymously (quick start)
  Future<User?> signInAnonymously() async {
    if (_auth == null) return null;
    try {
      final credential = await _auth!.signInAnonymously();
      final user = credential.user;

      if (user != null) {
        // Create user profile in Firestore
        await _createUserProfile(user);
      }

      return user;
    } catch (e) {
      print('Error signing in anonymously: $e');
      return null;
    }
  }

  /// Sign in with email and password
  /// Returns (User?, errorMessage)
  Future<(User?, String?)> signInWithEmail(
    String email,
    String password,
  ) async {
    if (_auth == null) return (null, 'Offline mode');
    try {
      final credential = await _auth!.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return (credential.user, null);
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = 'No account found with this email.';
          break;
        case 'wrong-password':
          message = 'Incorrect password.';
          break;
        case 'invalid-email':
          message = 'Invalid email address.';
          break;
        case 'user-disabled':
          message = 'This account has been disabled.';
          break;
        case 'invalid-credential':
          message = 'Invalid email or password.';
          break;
        default:
          message = 'Login failed: ${e.message}';
      }
      print('Error signing in with email: $e');
      return (null, message);
    } catch (e) {
      print('Error signing in with email: $e');
      return (null, 'An unexpected error occurred.');
    }
  }

  /// Create account with email and password
  /// Returns (User?, errorMessage)
  Future<(User?, String?)> createAccountWithEmail(
    String email,
    String password,
    String displayName,
  ) async {
    if (_auth == null) return (null, 'Offline mode');
    try {
      final credential = await _auth!.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;

      if (user != null) {
        await user.updateDisplayName(displayName);
        await _createUserProfile(user, displayName: displayName);
      }

      return (user, null);
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'email-already-in-use':
          message = 'An account already exists with this email.';
          break;
        case 'invalid-email':
          message = 'Invalid email address.';
          break;
        case 'weak-password':
          message = 'Password is too weak. Use at least 6 characters.';
          break;
        case 'operation-not-allowed':
          message = 'Email/password accounts are not enabled.';
          break;
        default:
          message = 'Sign up failed: ${e.message}';
      }
      print('Error creating account: $e');
      return (null, message);
    } catch (e) {
      print('Error creating account: $e');
      return (null, 'An unexpected error occurred.');
    }
  }

  /// Upgrade anonymous account to email/password
  Future<bool> linkEmailToAnonymous(String email, String password) async {
    try {
      if (currentUser == null || !currentUser!.isAnonymous) return false;

      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );

      await currentUser!.linkWithCredential(credential);
      return true;
    } catch (e) {
      print('Error linking email: $e');
      return false;
    }
  }

  /// Sign out
  Future<void> signOut() async {
    await _auth?.signOut();
  }

  /// Create user profile in Firestore
  Future<void> _createUserProfile(User user, {String? displayName}) async {
    if (_firestore == null) return;
    final docRef = _firestore!.collection('users').doc(user.uid);
    final docSnap = await docRef.get();

    // Only create if doesn't exist
    if (!docSnap.exists) {
      await docRef.set({
        'userId': user.uid,
        'displayName':
            displayName ??
            user.displayName ??
            'Player${user.uid.substring(0, 6)}',
        'email': user.email,
        'elo': 1000,
        'gamesPlayed': 0,
        'wins': 0,
        'losses': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Get user profile
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    if (_firestore == null) return null;
    try {
      final doc = await _firestore!.collection('users').doc(userId).get();
      return doc.data();
    } catch (e) {
      print('Error getting user profile: $e');
      return null;
    }
  }

  /// Update user display name
  Future<void> updateDisplayName(String displayName) async {
    if (currentUser == null || _firestore == null) return;

    await currentUser!.updateDisplayName(displayName);
    await _firestore!.collection('users').doc(currentUser!.uid).update({
      'displayName': displayName,
    });
  }

  /// Update ELO after match
  Future<void> updateElo(String userId, int eloDelta, bool won) async {
    if (_firestore == null) return;
    final docRef = _firestore!.collection('users').doc(userId);

    await docRef.update({
      'elo': FieldValue.increment(eloDelta),
      'gamesPlayed': FieldValue.increment(1),
      if (won)
        'wins': FieldValue.increment(1)
      else
        'losses': FieldValue.increment(1),
    });
  }
}
