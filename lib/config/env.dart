/// Compile-time environment configuration.
///
/// Values are injected via `--dart-define-from-file=env.json` (see
/// `env.example.json` for the required keys). Never hard-code secrets here.
class Env {
  const Env._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static void assertConfigured() {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw StateError(
        'Missing Supabase configuration. Run with '
        '--dart-define-from-file=env.json (copy env.example.json first).',
      );
    }
  }
}
