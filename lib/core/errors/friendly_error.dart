import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/generated/app_localizations.dart';

/// Translates raw Supabase/Postgres exceptions into plain-language,
/// user-facing text. Per the project spec, users must never see raw
/// database error messages.
String friendlyError(Object error, AppLocalizations l10n) {
  if (error is AuthException) {
    final msg = error.message.toLowerCase();
    if (msg.contains('invalid login credentials')) {
      return l10n.errorIncorrectCredentials;
    }
    if (msg.contains('email not confirmed')) {
      return l10n.errorEmailNotConfirmed;
    }
    if (msg.contains('user already registered')) {
      return l10n.errorUserAlreadyRegistered;
    }
    if (msg.contains('password should be at least')) {
      return l10n.errorPasswordTooShort;
    }
    return l10n.errorAuthGeneric;
  }

  if (error is PostgrestException) {
    if (error.code == '23505') {
      return l10n.errorRecordExists;
    }
    if (error.code == '42501' ||
        error.message.toLowerCase().contains('permission')) {
      return l10n.errorNoPermission;
    }
    if (error.message.isNotEmpty &&
        !error.message.startsWith('duplicate key') &&
        error.code == null) {
      // Custom RAISE EXCEPTION messages from our own RPCs are dynamic,
      // database-generated text (see supabase/migrations) -- not static
      // strings, so they cannot be routed through ARB and are shown as-is.
      return error.message;
    }
    return l10n.errorSaveGeneric;
  }

  return l10n.errorGeneric;
}
