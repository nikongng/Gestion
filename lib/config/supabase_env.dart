/// Variables injectées au build, par exemple :
/// - `flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
/// - ou `flutter run --dart-define-from-file=gestia_secrets.json` (fichier listé dans `.gitignore`).
class SupabaseEnv {
  SupabaseEnv._();

  static const String url = String.fromEnvironment('SUPABASE_URL');
  static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}
