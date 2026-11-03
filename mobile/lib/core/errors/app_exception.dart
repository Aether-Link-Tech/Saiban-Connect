import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// An error whose message is safe to show to the user.
class AppException implements Exception {
  const AppException(this.message);
  final String message;
  @override
  String toString() => message;
}

String friendlyError(Object error) {
  if (error is AppException) return error.message;
  if (error is FirebaseFunctionsException) {
    switch (error.code) {
      case 'unavailable':
      case 'deadline-exceeded':
      case 'internal':
        return 'Could not reach the server. Check your internet connection and try again.';
      default:
        return error.message ?? 'Request failed (${error.code}).';
    }
  }
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
      case 'invalid-email':
        return 'Incorrect email/phone or password.';
      case 'email-already-in-use':
        return 'An account already exists with this email or phone. Please sign in instead.';
      case 'weak-password':
        return 'Choose a stronger password (at least 8 characters).';
      case 'user-disabled':
        return 'This account has been disabled. Contact HR.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a few minutes and try again.';
      case 'network-request-failed':
        return 'No internet connection.';
      default:
        return error.message ?? 'Sign-in failed (${error.code}).';
    }
  }
  if (error is FirebaseException) {
    if (error.code == 'permission-denied') return 'You do not have access to this information.';
    if (error.code == 'unavailable') return 'No internet connection.';
    return error.message ?? 'Something went wrong (${error.code}).';
  }
  return 'Something went wrong. Please try again.';
}
