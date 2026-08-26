import 'package:supabase_flutter/supabase_flutter.dart';

/// Translates raw Supabase/Postgres exceptions into plain-language,
/// user-facing text. Per the project spec, users must never see raw
/// database error messages.
String friendlyError(Object error) {
  if (error is AuthException) {
    final msg = error.message.toLowerCase();
    if (msg.contains('invalid login credentials')) {
      return 'Incorrect email or password.';
    }
    if (msg.contains('email not confirmed')) {
      return 'Please confirm your email before signing in.';
    }
    if (msg.contains('user already registered')) {
      return 'An account with this email already exists.';
    }
    if (msg.contains('password should be at least')) {
      return 'Password is too short. Use at least 6 characters.';
    }
    return 'Authentication failed. Please try again.';
  }

  if (error is PostgrestException) {
    if (error.code == '23505') {
      return 'That record already exists.';
    }
    if (error.code == '42501' || error.message.toLowerCase().contains('permission')) {
      return "You don't have permission to do that.";
    }
    if (error.message.isNotEmpty && !error.message.startsWith('duplicate key') && error.code == null) {
      // Custom RAISE EXCEPTION messages from our own RPCs are already
      // written to be user-facing (see supabase/migrations).
      return error.message;
    }
    return 'Something went wrong saving your data. Please try again.';
  }

  return 'Something went wrong. Please check your connection and try again.';
}
