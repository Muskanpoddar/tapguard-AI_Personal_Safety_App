// lib/data/repositories/auth_repository.dart
//
// Firebase Phone Authentication repository.
// Wraps FirebaseAuth.verifyPhoneNumber so the rest of the app has a clean API.

import 'package:firebase_auth/firebase_auth.dart';

class AuthRepository {
  AuthRepository({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  // ── Send OTP ──────────────────────────────────────────────────────────────
  Future<void> sendOtp(
    String phoneNumber, {
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(String error) onError,
    void Function()? onAutoVerified,
  }) async {
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            await _auth.signInWithCredential(credential);
            onAutoVerified?.call();
          } on FirebaseAuthException catch (e) {
            onError(friendlyMessage(e));
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          onError(friendlyMessage(e));
        },
        codeSent: (String verificationId, int? resendToken) {
          onCodeSent(verificationId, resendToken);
        },
        codeAutoRetrievalTimeout: (String verificationId) {},
      );
    } on FirebaseAuthException catch (e) {
      onError(friendlyMessage(e));
    } catch (e) {
      onError('Unexpected error: $e');
    }
  }

  // ── Verify / sign-in ──────────────────────────────────────────────────────
  Future<UserCredential> verifyOtp(String verificationId, String smsCode) {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    return _auth.signInWithCredential(credential);
  }

  // ── Resend OTP ────────────────────────────────────────────────────────────
  Future<void> resendOtp(
    String phoneNumber, {
    int? resendToken,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(String error) onError,
  }) async {
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        forceResendingToken: resendToken,
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            await _auth.signInWithCredential(credential);
          } on FirebaseAuthException catch (e) {
            onError(friendlyMessage(e));
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          onError(friendlyMessage(e));
        },
        codeSent: (String verificationId, int? newToken) {
          onCodeSent(verificationId, newToken);
        },
        codeAutoRetrievalTimeout: (_) {},
      );
    } on FirebaseAuthException catch (e) {
      onError(friendlyMessage(e));
    } catch (e) {
      onError('Unexpected error: $e');
    }
  }

  // ── Sign out ──────────────────────────────────────────────────────────────
  Future<void> signOut() => _auth.signOut();

  // ── Current user ──────────────────────────────────────────────────────────
  User? get currentUser => _auth.currentUser;

  // ── Auth state stream ─────────────────────────────────────────────────────
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ── Friendly error messages ───────────────────────────────────────────────
  static String friendlyMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-phone-number':
        return 'The phone number format is invalid.';
      case 'too-many-requests':
        return 'Too many requests. Please try again later.';
      case 'invalid-verification-code':
        return 'Wrong code. Please check and try again.';
      case 'session-expired':
        return 'The verification session expired. Please resend the code.';
      case 'quota-exceeded':
        return 'SMS quota exceeded. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Check your connection and retry.';
      case 'internal-error':
        return 'Firebase internal error. Make sure the SHA-1 fingerprint is registered in Firebase Console.';
      case 'app-not-authorized':
        return 'App not authorized for Firebase Phone Auth. Check SHA-1 setup.';
      default:
        return e.message ?? 'Authentication failed. Please try again.';
    }
  }
}
