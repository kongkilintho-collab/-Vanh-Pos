import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';

/// Shorthand for the current screen's localized strings: `context.l10n.foo`.
extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}
